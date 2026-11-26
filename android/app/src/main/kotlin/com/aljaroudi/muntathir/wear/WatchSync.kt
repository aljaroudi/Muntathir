package com.aljaroudi.muntathir.wear

import android.content.Context
import android.util.Log
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.wear.WatchSnapshot
import com.aljaroudi.muntathir.data.AppScope
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Sends the watch its settings, like Swift `WatchConnectivityService` on iOS: one [WatchSnapshot] data item at
 * [WatchSnapshot.PATH], replaced whenever what the watch shows changes. The Data Layer delivers it when a watch
 * connects and skips items whose bytes didn't change, so every process start can simply put the current one.
 */
@Singleton
class WatchSync
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
        private val model: AppModel,
        @param:AppScope private val scope: CoroutineScope,
    ) {
        fun start() {
            scope.launch {
                model.state
                    .map { WatchSnapshot.from(it) }
                    .distinctUntilChanged()
                    .collect { put(it) }
            }
        }

        private suspend fun put(snapshot: WatchSnapshot) {
            val request = PutDataRequest.create(WatchSnapshot.PATH).setData(snapshot.encode()).setUrgent()
            try {
                Wearable.getDataClient(context).putDataItem(request).await()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                // No Wearable API (no watch ever paired, or no Play services); the next change tries again.
                Log.i(TAG, "Watch sync skipped: ${error.message}")
            }
        }

        private companion object {
            const val TAG = "WatchSync"
        }
    }
