package com.aljaroudi.muntathir.location

import com.aljaroudi.muntathir.core.qibla.QiblaSession
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import javax.inject.Singleton

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
object QiblaModule {
    // Replaced by the device implementation in P5.1.
    @Provides
    @Singleton
    fun qiblaSensors(): QiblaSensors = QiblaSensors { flowOf(QiblaReading(QiblaSession.Status.Failed)) }
}
