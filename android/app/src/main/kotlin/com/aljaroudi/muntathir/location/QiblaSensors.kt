package com.aljaroudi.muntathir.location

import com.aljaroudi.muntathir.BuildConfig
import com.aljaroudi.muntathir.core.qibla.QiblaSession
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.flow.Flow

/** A snapshot of a running [QiblaSession]. */
data class QiblaReading(
    val status: QiblaSession.Status = QiblaSession.Status.Locating,
    val fix: QiblaSession.Fix? = null,
    val heading: QiblaSession.Heading? = null,
)

/**
 * Swift `QiblaLocationSession`: its own precise location and compass session, separate from the prayer location
 * and never saved. Collecting [readings] starts it; cancelling stops it. In [optional] mode (the Rakaat hint) it
 * never asks for permission.
 */
fun interface QiblaSensors {
    fun readings(optional: Boolean): Flow<QiblaReading>
}

/** Separate so instrumented tests can swap in fake readings. */
@Module
@InstallIn(SingletonComponent::class)
interface QiblaModule {
    @Binds
    fun qiblaSensors(impl: DeviceQiblaSensors): QiblaSensors
}

/** Whether Qibla draws the Google map (a Maps API key is configured) or the compass dial. */
data class QiblaMapConfig(
    val enabled: Boolean,
)

/** Separate from [QiblaModule], so tests that only fake readings keep the build's map choice. */
@Module
@InstallIn(SingletonComponent::class)
object QiblaMapModule {
    @Provides
    fun mapConfig(): QiblaMapConfig = QiblaMapConfig(BuildConfig.MAPS_API_KEY_SET)
}
