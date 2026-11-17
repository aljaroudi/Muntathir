package com.aljaroudi.muntathir.camera

import androidx.camera.core.SurfaceRequest
import com.aljaroudi.muntathir.core.rakaat.RakaatUpdate
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Singleton

/**
 * Swift `RakaatCamera`: counts sujood with the front camera. Collecting [updates] starts the camera and cancelling
 * stops it. The flow ends after a complete or failed update; ending without one means the camera couldn't be used
 * or capture was interrupted. Frames are measured in memory and never stored.
 */
interface SujoodCamera {
    fun updates(target: Int): Flow<RakaatUpdate>

    /** The live preview's surface request while [updates] is collected. */
    val preview: StateFlow<SurfaceRequest?>
}

/** Separate so instrumented tests can swap in a fake camera. */
@Module
@InstallIn(SingletonComponent::class)
abstract class CameraModule {
    @Binds
    @Singleton
    abstract fun sujoodCamera(camera: DeviceSujoodCamera): SujoodCamera
}
