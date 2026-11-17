package com.aljaroudi.muntathir

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import androidx.work.WorkManager
import com.aljaroudi.muntathir.feed.FeedRefreshWorker
import com.aljaroudi.muntathir.notifications.Rescheduler
import com.aljaroudi.muntathir.widgets.WidgetUpdater
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject
import android.content.res.Configuration as ResourcesConfiguration

@HiltAndroidApp
class MuntathirApplication :
    Application(),
    Configuration.Provider {
    @Inject lateinit var rescheduler: Rescheduler

    @Inject lateinit var workerFactory: HiltWorkerFactory

    @Inject lateinit var widgets: WidgetUpdater

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()

    override fun onCreate() {
        super.onCreate()
        // Every process start (launch, alarm, boot) re-derives the next alert from current settings.
        rescheduler.start()
        widgets.start()
        FeedRefreshWorker.schedule(WorkManager.getInstance(this))
    }

    // The per-app language (Android 13+) arrives as a configuration change; widget text follows it.
    override fun onConfigurationChanged(newConfig: ResourcesConfiguration) {
        super.onConfigurationChanged(newConfig)
        widgets.refresh()
    }
}
