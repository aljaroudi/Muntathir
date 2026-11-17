package com.aljaroudi.muntathir.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.location.Location
import android.location.LocationManager
import android.os.Looper
import android.os.SystemClock
import android.view.Display
import android.view.Surface
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import androidx.core.location.LocationManagerCompat
import com.aljaroudi.muntathir.core.qibla.QiblaGeometry
import com.aljaroudi.muntathir.core.qibla.QiblaSession
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Swift `QiblaLocationSession` on Android: a Fused high-accuracy stream every second and the rotation-vector
 * compass, run through [QiblaSession] on the elapsed-realtime clock. Nothing is stored; cancelling stops both.
 *
 * Permission is never requested here; the screen asks. Without precise access the status is Settings.
 */
@Singleton
class DeviceQiblaSensors
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
    ) : QiblaSensors {
        override fun readings(optional: Boolean): Flow<QiblaReading> =
            callbackFlow {
                val session = QiblaSession(optional)
                session.start(now())

                fun emit() {
                    trySend(QiblaReading(session.status, session.fix, session.heading))
                }

                val locations = context.getSystemService<LocationManager>()
                val fused = LocationServices.getFusedLocationProviderClient(context)
                val callback =
                    object : LocationCallback() {
                        override fun onLocationResult(result: LocationResult) {
                            session.receive(result.locations.map(::fix), precise = isPrecise(), now = now())
                            emit()
                        }
                    }
                val compass = Compass(session, ::emit)

                fun locationOff() = locations == null || !LocationManagerCompat.isLocationEnabled(locations)

                when {
                    !isPrecise() -> {
                        session.needsSettings()
                    }

                    locationOff() -> {
                        session.fail()
                    }

                    else -> {
                        startUpdates(fused, callback, optional, session, ::emit)
                        compass.start()
                    }
                }
                emit()

                launch {
                    while (true) {
                        delay(1_000)
                        if (session.status != QiblaSession.Status.Settings && locationOff()) session.fail()
                        session.refresh(now())
                        emit()
                    }
                }

                awaitClose {
                    fused.removeLocationUpdates(callback)
                    compass.stop()
                    session.stop()
                }
            }.buffer(capacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
                .distinctUntilChanged()
                // Sensor and location callbacks arrive on the main looper; the session stays on that thread.
                .flowOn(Dispatchers.Main.immediate)

        @SuppressLint("MissingPermission")
        private fun startUpdates(
            fused: com.google.android.gms.location.FusedLocationProviderClient,
            callback: LocationCallback,
            optional: Boolean,
            session: QiblaSession,
            emit: () -> Unit,
        ) {
            val request =
                LocationRequest
                    .Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_MS)
                    .setMinUpdateIntervalMillis(UPDATE_MS)
                    .setWaitForAccurateLocation(false)
                    .build()
            try {
                // Swift's optional mode also uses the cached fix; the session accepts it when it's recent enough.
                if (optional) {
                    fused.lastLocation.addOnSuccessListener { location ->
                        if (location != null && session.fix == null) {
                            session.receive(listOf(fix(location)), precise = isPrecise(), now = now())
                            emit()
                        }
                    }
                }
                fused
                    .requestLocationUpdates(request, callback, Looper.getMainLooper())
                    .addOnFailureListener {
                        session.fail()
                        emit()
                    }
            } catch (_: SecurityException) {
                session.needsSettings()
            }
        }

        private fun isPrecise(): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        /** True heading from the rotation vector, remapped for the display rotation and corrected by declination. */
        private inner class Compass(
            private val session: QiblaSession,
            private val emit: () -> Unit,
        ) : SensorEventListener {
            private val sensors = context.getSystemService<SensorManager>()
            private val sensor =
                sensors?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                    ?: sensors?.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
            private val display = context.getSystemService<DisplayManager>()?.getDisplay(Display.DEFAULT_DISPLAY)
            private val rotation = FloatArray(9)
            private val remapped = FloatArray(9)
            private val orientation = FloatArray(3)
            private var status = SensorManager.SENSOR_STATUS_UNRELIABLE
            private var displayRotation: Int? = null
            private var declination: Pair<QiblaSession.Fix, Double>? = null

            fun start() {
                // No compass: the heading stays null and the screen shows "Compass unavailable".
                sensor?.let { sensors?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
            }

            fun stop() {
                sensors?.unregisterListener(this)
            }

            override fun onAccuracyChanged(
                sensor: Sensor,
                accuracy: Int,
            ) {
                status = accuracy
            }

            override fun onSensorChanged(event: SensorEvent) {
                status = event.accuracy
                val turn = display?.rotation ?: Surface.ROTATION_0
                if (displayRotation != null && displayRotation != turn) session.resetHeading()
                displayRotation = turn
                // True north needs the fix, as `CLHeading.trueHeading` does.
                val fix = session.fix ?: return emit()
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                val (x, y) =
                    when (turn) {
                        Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
                        Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
                        Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
                        else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
                    }
                SensorManager.remapCoordinateSystem(rotation, x, y, remapped)
                SensorManager.getOrientation(remapped, orientation)
                val degrees = QiblaGeometry.trueHeading(Math.toDegrees(orientation[0].toDouble()), declination(fix))
                val estimate = event.values.getOrNull(4)?.toDouble()
                val accuracy = QiblaGeometry.headingAccuracy(estimate, status)
                val now = now()
                // Received now: `SensorEvent.timestamp` isn't on elapsed realtime on every device.
                session.receiveHeading(
                    QiblaSession.Heading(degrees ?: Double.NaN, accuracy ?: Double.NaN, now),
                    now,
                )
                emit()
            }

            private fun declination(fix: QiblaSession.Fix): Double {
                declination?.let { (at, value) ->
                    if (at.latitude == fix.latitude &&
                        at.longitude == fix.longitude
                    ) {
                        return value
                    }
                }
                val value =
                    GeomagneticField(
                        fix.latitude.toFloat(),
                        fix.longitude.toFloat(),
                        0f,
                        System.currentTimeMillis(),
                    ).declination.toDouble()
                declination = fix to value
                return value
            }
        }

        private companion object {
            const val UPDATE_MS = 1_000L

            fun now(): Double = SystemClock.elapsedRealtimeNanos() / 1e9

            fun fix(location: Location) =
                QiblaSession.Fix(
                    latitude = location.latitude,
                    longitude = location.longitude,
                    accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else Double.POSITIVE_INFINITY,
                    time = location.elapsedRealtimeNanos / 1e9,
                )
        }
    }
