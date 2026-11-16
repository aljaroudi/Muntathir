package com.aljaroudi.muntathir.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.os.Build
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import us.dustinj.timezonemap.TimeZoneMap
import java.time.DateTimeException
import java.time.ZoneId
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

@Module
@InstallIn(SingletonComponent::class)
interface LocationModule {
    @Binds
    fun locator(impl: FusedDeviceLocator): DeviceLocator
}

/** The device's current place for prayer times. Never uploaded; the result stays in the device-local store. */
interface DeviceLocator {
    fun hasPermission(): Boolean

    /** One coarse fix with a name and time zone, or `null` when no fix arrives. */
    suspend fun locate(): SavedLocation?
}

/**
 * Fused coarse fix (prayer times need about a kilometre), named by reverse geocoding and zoned with an
 * offline time-zone map, so a fix taken while travelling gets the place's zone rather than the phone's.
 */
@Singleton
class FusedDeviceLocator
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
    ) : DeviceLocator {
        override fun hasPermission(): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        @SuppressLint("MissingPermission")
        override suspend fun locate(): SavedLocation? {
            if (!hasPermission()) return null
            // A recent last-known fix is fine for prayer times when no fresh fix arrives (e.g. indoors).
            val fix = withTimeoutOrNull(FIX_TIMEOUT_MS) { currentLocation() } ?: lastLocation() ?: return null
            val address = withTimeoutOrNull(GEOCODE_TIMEOUT_MS) { address(fix.latitude, fix.longitude) }
            // Geocoders may wrap names in bidi marks, which would leak into notifications and widgets.
            val name =
                listOfNotNull(address?.locality, address?.subAdminArea, address?.adminArea)
                    .map { name -> name.filterNot { it.code in BIDI_MARKS }.trim() }
                    .firstOrNull { it.isNotEmpty() } ?: context.getString(R.string.device_location)
            return SavedLocation(
                latitude = fix.latitude,
                longitude = fix.longitude,
                name = name,
                countryCode = address?.countryCode.orEmpty(),
                timeZoneID = zone(fix.latitude, fix.longitude),
            ).takeIf { it.isValid }
        }

        @SuppressLint("MissingPermission")
        private suspend fun currentLocation(): android.location.Location? {
            val request =
                CurrentLocationRequest
                    .Builder()
                    .setPriority(Priority.PRIORITY_BALANCED_POWER_ACCURACY)
                    .setMaxUpdateAgeMillis(MAX_AGE_MS)
                    .build()
            val cancellation = CancellationTokenSource()
            return suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { cancellation.cancel() }
                LocationServices
                    .getFusedLocationProviderClient(context)
                    .getCurrentLocation(request, cancellation.token)
                    .addOnCompleteListener { task -> continuation.resume(if (task.isSuccessful) task.result else null) }
            }
        }

        @SuppressLint("MissingPermission")
        private suspend fun lastLocation(): android.location.Location? =
            suspendCancellableCoroutine { continuation ->
                LocationServices
                    .getFusedLocationProviderClient(context)
                    .lastLocation
                    .addOnCompleteListener { task -> continuation.resume(if (task.isSuccessful) task.result else null) }
            }

        private suspend fun address(
            latitude: Double,
            longitude: Double,
        ): Address? {
            if (!Geocoder.isPresent()) return null
            // The per-app language, so place names match the interface.
            val geocoder = Geocoder(context, AppCompatDelegate.getApplicationLocales()[0] ?: Locale.getDefault())
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                suspendCancellableCoroutine { continuation ->
                    geocoder.getFromLocation(
                        latitude,
                        longitude,
                        1,
                        object : Geocoder.GeocodeListener {
                            override fun onGeocode(addresses: MutableList<Address>) =
                                continuation.resume(addresses.firstOrNull())

                            override fun onError(errorMessage: String?) = continuation.resume(null)
                        },
                    )
                }
            } else {
                withContext(Dispatchers.IO) {
                    @Suppress("DEPRECATION")
                    runCatching { geocoder.getFromLocation(latitude, longitude, 1)?.firstOrNull() }.getOrNull()
                }
            }
        }

        /** Loads only the map tiles around the fix, which takes milliseconds instead of the whole world. */
        private suspend fun zone(
            latitude: Double,
            longitude: Double,
        ): String =
            withContext(Dispatchers.Default) {
                val id =
                    runCatching {
                        TimeZoneMap
                            .forRegion(
                                (latitude - 0.1).coerceAtLeast(-90.0),
                                (longitude - 0.1).coerceAtLeast(-180.0),
                                (latitude + 0.1).coerceAtMost(90.0),
                                (longitude + 0.1).coerceAtMost(180.0),
                            ).getOverlappingTimeZone(latitude, longitude)
                            ?.zoneId
                    }.getOrNull()
                id?.takeIf(::isKnownZone) ?: ZoneId.systemDefault().id
            }

        private fun isKnownZone(id: String): Boolean =
            try {
                ZoneId.of(id)
                true
            } catch (_: DateTimeException) {
                false
            }

        private companion object {
            const val FIX_TIMEOUT_MS = 20_000L
            const val GEOCODE_TIMEOUT_MS = 10_000L
            const val MAX_AGE_MS = 10 * 60_000L

            /** LRM, RLM, embeddings/overrides and isolates (not ZWNJ, which Persian spelling needs). */
            val BIDI_MARKS: Set<Int> = setOf(0x200E, 0x200F) + (0x202A..0x202E) + (0x2066..0x2069)
        }
    }
