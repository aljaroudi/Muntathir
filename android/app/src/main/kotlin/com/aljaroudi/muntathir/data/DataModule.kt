package com.aljaroudi.muntathir.data

import android.content.Context
import com.aljaroudi.muntathir.core.app.Announcer
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.feed.FeedClient
import com.aljaroudi.muntathir.core.feed.FeedTransport
import com.aljaroudi.muntathir.feed.KtorFeedTransport
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import java.io.File
import java.time.Clock
import javax.inject.Qualifier
import javax.inject.Singleton

/** Process-lifetime scope for work that must outlive a screen (saves, rescheduling). */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class AppScope

@Module
@InstallIn(SingletonComponent::class)
object DataModule {
    @Provides
    @Singleton
    @AppScope
    fun scope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Provides
    @Singleton
    fun clock(): Clock = Clock.systemDefaultZone()

    @Provides
    @Singleton
    fun storage(
        @ApplicationContext context: Context,
        @AppScope scope: CoroutineScope,
    ): AppStorage = DataStoreAppStorage.create(context, CoroutineScope(scope.coroutineContext + Dispatchers.IO))

    // Replaced by the notification poster in P2.6.
    @Provides
    fun announcer(): Announcer = Announcer { false }

    @Provides
    @Singleton
    fun transport(): FeedTransport = KtorFeedTransport()

    @Provides
    @Singleton
    fun feedClient(
        @ApplicationContext context: Context,
        transport: FeedTransport,
    ): FeedClient =
        FeedClient(FeedClient.PRODUCTION_URL, File(context.cacheDir, "calendar/corrections-v1.json"), transport)

    /**
     * Loads both stores before first use. They are a few hundred bytes each, and every screen and receiver
     * needs the validated state, so a short blocking read once per process is simpler than an async gate.
     */
    @Provides
    @Singleton
    fun model(
        storage: AppStorage,
        feedClient: FeedClient,
        announcer: Announcer,
        clock: Clock,
    ): AppModel =
        runBlocking(Dispatchers.IO) {
            AppModel.load(storage, feedClient, announcer, clock = clock::instant)
        }
}
