package com.aljaroudi.muntathir.data

import com.aljaroudi.muntathir.core.calendar.EventLibrary
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.time.Clock
import java.time.Instant
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object ContentModule {
    /** `shared/events.json`, bundled in `core`. */
    @Provides
    @Singleton
    fun events(): EventLibrary = EventLibrary.bundled()
}

/** Now, then at every minute boundary; collect only while visible (stops in the background, restarts fresh). */
fun Clock.minutes(): Flow<Instant> =
    flow {
        while (true) {
            val now = instant()
            emit(now)
            delay(60_000 - now.toEpochMilli() % 60_000)
        }
    }
