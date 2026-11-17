package com.aljaroudi.muntathir.feed

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.aljaroudi.muntathir.core.app.AppModel
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * Swift `BackgroundRefresh`: refreshes the corrections feed about every 12 hours on a network. The model
 * applies it (or drops it if settings changed meanwhile) and announces newly confirmed months.
 */
@HiltWorker
class FeedRefreshWorker
    @AssistedInject
    constructor(
        @Assisted context: Context,
        @Assisted parameters: WorkerParameters,
        private val model: AppModel,
    ) : CoroutineWorker(context, parameters) {
        override suspend fun doWork(): Result {
            model.refreshFeed()
            // Failures fall back to the cached feed; the next period tries again.
            return Result.success()
        }

        companion object {
            private const val NAME = "corrections-feed"

            fun schedule(workManager: WorkManager) {
                val request =
                    PeriodicWorkRequestBuilder<FeedRefreshWorker>(12, TimeUnit.HOURS)
                        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                        .build()
                workManager.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
            }
        }
    }
