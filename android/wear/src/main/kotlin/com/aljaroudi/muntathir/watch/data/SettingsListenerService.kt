package com.aljaroudi.muntathir.watch.data

import com.aljaroudi.muntathir.core.wear.WatchSnapshot
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.runBlocking

/** Receives the phone's snapshot (Swift `session(_:didReceiveApplicationContext:)`), then refreshes surfaces. */
class SettingsListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        // Copy out before the buffer is released when this returns.
        val bytes =
            dataEvents
                .filter { it.type == DataEvent.TYPE_CHANGED && it.dataItem.uri.path == WatchSnapshot.PATH }
                .lastOrNull()
                ?.dataItem
                ?.data ?: return
        // Called on a background thread; the write is one small file.
        val changed = runBlocking { WatchStore.receive(this@SettingsListenerService, bytes) }
        if (changed) Surfaces.refresh(this)
    }
}
