package com.aljaroudi.muntathir.camera

import android.content.Context
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.util.Size
import androidx.annotation.OptIn
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.aljaroudi.muntathir.core.rakaat.RakaatCapture
import com.aljaroudi.muntathir.core.rakaat.RakaatCapture.Step
import com.aljaroudi.muntathir.core.rakaat.RakaatUpdate
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.ProducerScope
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.inject.Inject
import javax.inject.Singleton

/**
 * CameraX [SujoodCamera]: the front camera at about 320×240 and 10 fps. Each frame's light is the mean of its luma
 * (Y) plane sampled every 8 pixels. Once auto-exposure, white balance and focus have converged they are locked,
 * so covering the camera darkens the frame instead of being compensated; only frames captured under the lock
 * are counted. The camera runs on its own lifecycle, from collection until cancellation.
 */
@Singleton
class DeviceSujoodCamera
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
    ) : SujoodCamera {
        private val requests = MutableStateFlow<SurfaceRequest?>(null)
        override val preview: StateFlow<SurfaceRequest?> = requests.asStateFlow()

        @OptIn(ExperimentalCamera2Interop::class)
        override fun updates(target: Int): Flow<RakaatUpdate> =
            callbackFlow {
                val provider = ProcessCameraProvider.awaitInstance(context)
                val selector = CameraSelector.DEFAULT_FRONT_CAMERA
                if (!runCatching { provider.hasCamera(selector) }.getOrDefault(false)) {
                    close()
                    return@callbackFlow
                }
                val info = Camera2CameraInfo.from(provider.getCameraInfo(selector))
                val canLockExposure =
                    info.getCameraCharacteristic(CameraCharacteristics.CONTROL_AE_LOCK_AVAILABLE) == true
                val canLockBalance =
                    info.getCameraCharacteristic(CameraCharacteristics.CONTROL_AWB_LOCK_AVAILABLE) == true
                val canFocus =
                    (info.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f) > 0f &&
                        info
                            .getCameraCharacteristic(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
                            ?.contains(CaptureRequest.CONTROL_AF_MODE_AUTO) == true
                val frameRate =
                    info
                        .getCameraCharacteristic(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                        ?.filter { it.lower <= FRAME_RATE && it.upper >= FRAME_RATE }
                        ?.minByOrNull { it.upper }

                val capture = RakaatCapture(target)
                val settled = AtomicBoolean(false)
                // Sensor time of the first frame captured with exposure locked.
                val lockedSince = AtomicLong(Long.MAX_VALUE)
                val callback =
                    object : CameraCaptureSession.CaptureCallback() {
                        override fun onCaptureCompleted(
                            session: CameraCaptureSession,
                            request: CaptureRequest,
                            result: TotalCaptureResult,
                        ) {
                            val exposure = result.get(CaptureResult.CONTROL_AE_STATE)
                            val balance = result.get(CaptureResult.CONTROL_AWB_STATE)
                            val focus = result.get(CaptureResult.CONTROL_AF_STATE)
                            settled.set(
                                (exposure == null || exposure in SETTLED_EXPOSURE) &&
                                    (balance == null || balance in SETTLED_BALANCE) &&
                                    focus !in SCANNING_FOCUS,
                            )
                            val locked =
                                request.get(CaptureRequest.CONTROL_AE_LOCK) == true &&
                                    (exposure == null || exposure == CaptureResult.CONTROL_AE_STATE_LOCKED)
                            val time = result.get(CaptureResult.SENSOR_TIMESTAMP)
                            if (locked && time != null) lockedSince.compareAndSet(Long.MAX_VALUE, time)
                        }
                    }

                val resolution =
                    ResolutionSelector
                        .Builder()
                        .setResolutionStrategy(
                            ResolutionStrategy(
                                Size(320, 240),
                                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                            ),
                        ).build()
                val analysisBuilder =
                    ImageAnalysis
                        .Builder()
                        .setResolutionSelector(resolution)
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                Camera2Interop.Extender(analysisBuilder).apply {
                    setSessionCaptureCallback(callback)
                    frameRate?.let { setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it) }
                }
                val analysis = analysisBuilder.build()
                val preview = Preview.Builder().setResolutionSelector(resolution).build()
                preview.setSurfaceProvider { requests.value = it }

                val lifecycle = SessionLifecycle()
                val camera = provider.bindToLifecycle(lifecycle, selector, preview, analysis)
                lifecycle.registry.currentState = Lifecycle.State.RESUMED
                // Another app taking the camera, or a camera error, ends the session (Swift: interruption).
                camera.cameraInfo.cameraState.observe(lifecycle) { if (it.error != null) close() }

                fun lock() {
                    if (!canLockExposure) return handle(synchronized(capture) { capture.lockFailed() }, ::lock)
                    val options =
                        CaptureRequestOptions
                            .Builder()
                            .setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, true)
                            .apply {
                                if (canLockBalance) setCaptureRequestOption(CaptureRequest.CONTROL_AWB_LOCK, true)
                                // Without a trigger, AUTO holds the lens where it is.
                                if (canFocus) {
                                    setCaptureRequestOption(
                                        CaptureRequest.CONTROL_AF_MODE,
                                        CaptureRequest.CONTROL_AF_MODE_AUTO,
                                    )
                                }
                            }.build()
                    val future = Camera2CameraControl.from(camera.cameraControl).addCaptureRequestOptions(options)
                    future.addListener({
                        if (runCatching { future.get() }.isFailure) {
                            handle(synchronized(capture) { capture.lockFailed() }, ::lock)
                        }
                    }, Runnable::run)
                }

                val executor = Executors.newSingleThreadExecutor()
                val timing = AtomicBoolean(false)
                analysis.setAnalyzer(executor) { image ->
                    val step =
                        image.use { frame ->
                            val time = frame.imageInfo.timestamp
                            val state =
                                when {
                                    time >= lockedSince.get() -> RakaatCapture.Camera.Locked
                                    settled.get() -> RakaatCapture.Camera.Settled
                                    else -> RakaatCapture.Camera.Adjusting
                                }
                            synchronized(capture) { capture.frame(luminance(frame), time / 1e9, state) }
                        }
                    if (timing.compareAndSet(false, true)) {
                        launch {
                            delay(RakaatCapture.PREPARATION_TIMEOUT_MILLIS)
                            handle(synchronized(capture) { capture.expirePreparation() }, ::lock)
                        }
                    }
                    handle(step, ::lock)
                }

                awaitClose {
                    analysis.clearAnalyzer()
                    provider.unbind(preview, analysis)
                    lifecycle.registry.currentState = Lifecycle.State.DESTROYED
                    requests.value = null
                    executor.shutdown()
                }
            }.conflate().flowOn(Dispatchers.Main.immediate)

        private fun ProducerScope<RakaatUpdate>.handle(
            step: Step,
            lock: () -> Unit,
        ) {
            when (step) {
                Step.Skip -> {}

                is Step.Publish -> {
                    trySend(step.update)
                }

                is Step.Lock -> {
                    trySend(step.update)
                    lock()
                }

                is Step.Finish -> {
                    step.update?.let { trySend(it) }
                    close()
                }
            }
        }

        /** Mean luma (BT.601 Y) of every eighth pixel in each direction, 0…1. */
        private fun luminance(image: ImageProxy): Double {
            val plane = image.planes[0]
            val buffer = plane.buffer
            var sum = 0L
            var count = 0
            for (y in 0 until image.height step 8) {
                val row = y * plane.rowStride
                for (x in 0 until image.width step 8) {
                    sum += buffer.get(row + x * plane.pixelStride).toInt() and 0xFF
                    count += 1
                }
            }
            return sum.toDouble() / maxOf(count, 1) / 255
        }

        private class SessionLifecycle : LifecycleOwner {
            val registry = LifecycleRegistry(this)
            override val lifecycle: Lifecycle get() = registry
        }

        private companion object {
            const val FRAME_RATE = 10
            val SETTLED_EXPOSURE =
                setOf(
                    CaptureResult.CONTROL_AE_STATE_CONVERGED,
                    CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED,
                    CaptureResult.CONTROL_AE_STATE_LOCKED,
                )
            val SETTLED_BALANCE =
                setOf(CaptureResult.CONTROL_AWB_STATE_CONVERGED, CaptureResult.CONTROL_AWB_STATE_LOCKED)
            val SCANNING_FOCUS =
                setOf(CaptureResult.CONTROL_AF_STATE_PASSIVE_SCAN, CaptureResult.CONTROL_AF_STATE_ACTIVE_SCAN)
        }
    }
