package com.aljaroudi.muntathir.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.SystemClock
import androidx.core.content.ContextCompat
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

    /** One recent coarse fix within 5 km, with its time zone, or `null` when none arrives. */
    suspend fun locate(): SavedLocation?
}

/**
 * A fresh coarse Fused fix within 5 km (prayer times shift about a minute per 15–20 km), zoned with an offline time-zone map so a fix
 * taken while travelling gets the place's zone rather than the phone's. There's no reverse geocoding, so the
 * coordinates never leave the device. Qibla has its own precise session
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
            // Only a fix within 5 km that is at most a minute old counts: a just-taken cached fix answers at once,
            // otherwise ask for a new one (Wi-Fi/cell first, then GPS when that isn't close enough). Never fall
            // back to an old or vague fix; a failure lets the user retry instead of saving the wrong place.
            val fix =
                lastLocation()?.takeIf { it.isUsable }
                    ?: currentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY)?.takeIf { it.isUsable }
                    ?: currentLocation(Priority.PRIORITY_HIGH_ACCURACY)?.takeIf { it.isUsable }
                    ?: return null
            return SavedLocation(fix.latitude, fix.longitude, zone(fix.latitude, fix.longitude)).takeIf { it.isValid }
        }

        private val Location.isUsable: Boolean
            get() = hasAccuracy() && accuracy in 0f..MAX_ACCURACY_M && ageMillis in 0..MAX_AGE_MS

        @SuppressLint("MissingPermission")
        private suspend fun currentLocation(priority: Int): Location? =
            withTimeoutOrNull(FIX_TIMEOUT_MS) { requestCurrentLocation(priority) }

        @SuppressLint("MissingPermission")
        private suspend fun requestCurrentLocation(priority: Int): Location? {
            val request =
                CurrentLocationRequest
                    .Builder()
                    .setPriority(priority)
                    // Coarse even when Qibla has been granted precise access; its error stays well under 5 km.
                    .setGranularity(Granularity.GRANULARITY_COARSE)
                    .setMaxUpdateAgeMillis(MAX_AGE_MS)
                    .setDurationMillis(FIX_TIMEOUT_MS)
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
            /** Per attempt; Wi-Fi/cell then GPS, so a failure takes at most twice this. */
            const val FIX_TIMEOUT_MS = 15_000L

            /** Even driving fast, a minute-old fix is within the 5 km tolerance. */
            const val MAX_AGE_MS = 60_000L

            /** Prayer-time tolerance: Fused's reported (68%) horizontal accuracy radius. */
            const val MAX_ACCURACY_M = 5_000f
        }
    }
