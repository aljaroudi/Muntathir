package com.aljaroudi.muntathir.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.SystemClock
import androidx.core.content.ContextCompat
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.Granularity
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

    /** One coarse fix with a time zone, or `null` when no fix arrives. */
    suspend fun locate(): SavedLocation?
}

/**
 * A coarse Fused fix (prayer times only need about a kilometre), zoned with an offline time-zone map so a fix
 * taken while travelling gets the place's zone rather than the phone's. Like iOS, there's no reverse geocoding:
 * the place is "Device location" and the coordinates never leave the device. Qibla has its own precise session
 * ([DeviceQiblaSensors]).
 */
@Singleton
class FusedDeviceLocator
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
    ) : DeviceLocator {
        private val fused get() = LocationServices.getFusedLocationProviderClient(context)

        override fun hasPermission(): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        override suspend fun locate(): SavedLocation? {
            if (!hasPermission()) return null
            // A recent cached fix answers at once; otherwise wait for a new one, falling back to any cached fix
            // (e.g. indoors).
            val last = lastLocation()
            val fix =
                last?.takeIf { it.ageMillis <= MAX_AGE_MS }
                    ?: withTimeoutOrNull(FIX_TIMEOUT_MS) { currentLocation() }
                    ?: last
                    ?: return null
            return SavedLocation(
                latitude = fix.latitude,
                longitude = fix.longitude,
                name = context.getString(R.string.device_location),
                countryCode = "",
                timeZoneID = zone(fix.latitude, fix.longitude),
            ).takeIf { it.isValid }
        }

        @SuppressLint("MissingPermission")
        private suspend fun currentLocation(): Location? {
            val request =
                CurrentLocationRequest
                    .Builder()
                    .setPriority(Priority.PRIORITY_BALANCED_POWER_ACCURACY)
                    // Coarse even when Qibla has been granted precise access.
                    .setGranularity(Granularity.GRANULARITY_COARSE)
                    .setMaxUpdateAgeMillis(MAX_AGE_MS)
                    .build()
            val cancellation = CancellationTokenSource()
            return suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { cancellation.cancel() }
                fused
                    .getCurrentLocation(request, cancellation.token)
                    .addOnCompleteListener { task -> continuation.resume(if (task.isSuccessful) task.result else null) }
            }
        }

        @SuppressLint("MissingPermission")
        private suspend fun lastLocation(): Location? =
            suspendCancellableCoroutine { continuation ->
                fused.lastLocation.addOnCompleteListener { task ->
                    continuation.resume(if (task.isSuccessful) task.result else null)
                }
            }

        private val Location.ageMillis: Long
            get() = (SystemClock.elapsedRealtimeNanos() - elapsedRealtimeNanos) / 1_000_000

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
            const val MAX_AGE_MS = 10 * 60_000L
        }
    }
