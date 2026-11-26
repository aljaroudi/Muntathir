package com.aljaroudi.muntathir.watch.data

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import com.aljaroudi.muntathir.core.wear.WatchSnapshot
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The last valid snapshot from the phone (Swift `WatchSettings.read`/`receive`). Invalid transfers are dropped
 * and the previous snapshot stays. One per process; every surface (app, complications, tile) reads it.
 */
object WatchStore {
    private const val TAG = "WatchStore"
    private val mutex = Mutex()
    private val state = MutableStateFlow<WatchSnapshot?>(null)
    private var loaded = false

    /** The snapshot flow, after the saved one has been read. */
    suspend fun snapshots(context: Context): StateFlow<WatchSnapshot?> {
        load(context)
        return state.asStateFlow()
    }

    suspend fun current(context: Context): WatchSnapshot? = snapshots(context).value

    /**
     * Validates and saves a transfer; returns whether what the watch shows changed. Surfaces are asked to
     * refresh by the caller.
     */
    suspend fun receive(
        context: Context,
        bytes: ByteArray,
    ): Boolean {
        val value =
            try {
                WatchSnapshot.decode(bytes)
            } catch (error: Exception) {
                Log.w(TAG, "Ignored an invalid snapshot", error)
                return false
            }
        load(context)
        return mutex.withLock {
            if (value == state.value) return@withLock false
            withContext(Dispatchers.IO) {
                val file = file(context)
                val stream = file.startWrite()
                try {
                    stream.write(bytes)
                    file.finishWrite(stream)
                } catch (error: Exception) {
                    file.failWrite(stream)
                    throw error
                }
            }
            state.value = value
            true
        }
    }

    /** Catches up with the phone's current item, for changes delivered while the listener wasn't bound. */
    suspend fun sync(context: Context): Boolean =
        try {
            val items = Wearable.getDataClient(context).dataItems.await()
            try {
                items.firstOrNull { it.uri.path == WatchSnapshot.PATH }?.data
            } finally {
                items.release()
            }?.let { receive(context, it) } ?: false
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Log.i(TAG, "Sync skipped: ${error.message}")
            false
        }

    private suspend fun load(context: Context) {
        if (loaded) return
        mutex.withLock {
            if (loaded) return
            state.value =
                withContext(Dispatchers.IO) {
                    runCatching { WatchSnapshot.decode(file(context).readFully()) }.getOrNull()
                }
            loaded = true
        }
    }

    private fun file(context: Context) = AtomicFile(File(context.applicationContext.filesDir, "watch-settings.v1.json"))
}
