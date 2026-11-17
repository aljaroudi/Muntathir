package com.aljaroudi.muntathir.data.library

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.assets.ContentPack
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.first

/**
 * Keeps the process alive while a [ContentLibrary] copies its pack or removes a book. The work itself runs in
 * the library; this expedited job only raises the process's priority until it finishes. Below API 31 expedited
 * work runs as a foreground service, with a silent notification.
 */
@HiltWorker
class LibraryWorker
    @AssistedInject
    constructor(
        @Assisted context: Context,
        @Assisted parameters: WorkerParameters,
        private val libraries: ContentLibraries,
    ) : CoroutineWorker(context, parameters) {
        private val pack get() = ContentPack.entries.firstOrNull { it.packName == inputData.getString(PACK) }

        override suspend fun doWork(): Result {
            // Getting the library starts it; an interrupted install resumes here after a restart.
            val library = pack?.let(libraries::get) ?: return Result.success()
            library.state.first { !it.preparing && !it.busy }
            return Result.success()
        }

        override suspend fun getForegroundInfo(): ForegroundInfo {
            val system = applicationContext.getSystemService(NotificationManager::class.java)
            system.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    applicationContext.getString(R.string.downloads),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
            val title = if (pack == ContentPack.Supplications) R.string.supplications else R.string.hadith
            val notification =
                NotificationCompat
                    .Builder(applicationContext, CHANNEL)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle(applicationContext.getString(title))
                    .setContentText(applicationContext.getString(R.string.installing))
                    .setProgress(0, 0, true)
                    .setOngoing(true)
                    .setSilent(true)
                    .build()
            val id = NOTIFICATION + (pack?.ordinal ?: 0)
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ForegroundInfo(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                ForegroundInfo(id, notification)
            }
        }

        companion object {
            private const val PACK = "pack"
            private const val CHANNEL = "downloads.v1"
            private const val NOTIFICATION = 7_000

            /** Best effort: the work runs either way, this only keeps the process alive meanwhile. */
            fun keepAlive(
                context: Context,
                pack: ContentPack,
            ) {
                val request =
                    OneTimeWorkRequestBuilder<LibraryWorker>()
                        .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                        .setInputData(workDataOf(PACK to pack.packName))
                        .build()
                // Instrumented tests run without the app's WorkManager configuration.
                runCatching {
                    WorkManager
                        .getInstance(context)
                        .enqueueUniqueWork("content-library-${pack.packName}", ExistingWorkPolicy.KEEP, request)
                }.onFailure { Log.w("LibraryWorker", "Couldn't keep the process alive for ${pack.packName}", it) }
            }
        }
    }
