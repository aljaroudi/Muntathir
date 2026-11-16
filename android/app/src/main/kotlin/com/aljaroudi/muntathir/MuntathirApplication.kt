package com.aljaroudi.muntathir

import android.app.Application
import com.aljaroudi.muntathir.notifications.Rescheduler
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class MuntathirApplication : Application() {
    @Inject lateinit var rescheduler: Rescheduler

    override fun onCreate() {
        super.onCreate()
        // Every process start (launch, alarm, boot) re-derives the next alert from current settings.
        rescheduler.start()
    }
}
