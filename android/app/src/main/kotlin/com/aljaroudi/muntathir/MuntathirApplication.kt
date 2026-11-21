package com.aljaroudi.muntathir

import android.app.Application
import android.os.StrictMode
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import androidx.work.WorkManager
import com.aljaroudi.muntathir.feed.FeedRefreshWorker
import com.aljaroudi.muntathir.notifications.Rescheduler
import com.aljaroudi.muntathir.ui.rakaat.SessionFocus
import com.aljaroudi.muntathir.wear.WatchSync
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

    @Inject lateinit var focus: SessionFocus

    @Inject lateinit var watch: WatchSync

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()

    override fun onCreate() {
        // Debug builds log main-thread disk and network access. The small preference reads that load AppModel
        // and ReadingSettings at injection are expected (see DataModule); anything else is an ANR risk.
        if (BuildConfig.DEBUG) {
            StrictMode.setThreadPolicy(
                StrictMode.ThreadPolicy
                    .Builder()
                    .detectAll()
                    .penaltyLog()
                    .build(),
            )
            StrictMode.setVmPolicy(
                StrictMode.VmPolicy
                    .Builder()
                    .detectAll()
                    .penaltyLog()
                    .build(),
            )
        }
        super.onCreate()
        // Every process start (launch, alarm, boot) re-derives the next alert from current settings.
        rescheduler.start()
        widgets.start()
        watch.start()
        FeedRefreshWorker.schedule(WorkManager.getInstance(this))
        // A rakaat session cut short by process death must not leave Do Not Disturb on.
        focus.recover()
    }

    // The per-app language (Android 13+) arrives as a configuration change; widget text follows it.
    override fun onConfigurationChanged(newConfig: ResourcesConfiguration) {
        super.onConfigurationChanged(newConfig)
        widgets.refresh()
    }
}
