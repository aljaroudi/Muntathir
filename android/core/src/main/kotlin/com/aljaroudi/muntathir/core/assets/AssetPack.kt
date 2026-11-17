package com.aljaroudi.muntathir.core.assets

import kotlinx.coroutines.flow.Flow
import java.io.File

/** One downloadable content pack. Port of Swift `AssetPackBackend`; the app adapts Play Asset Delivery. */
interface AssetPack {
    /** The installed pack's assets folder, or `null`; never starts a download. */
    suspend fun localDirectory(): File?

    /** Whether the store (Play) is already fetching the pack. */
    suspend fun isDownloading(): Boolean

    /** Fetches the pack, returning once it's installed and throwing when it fails. */
    suspend fun download()

    suspend fun remove()

    fun events(): Flow<Event>

    sealed interface Event {
        data object Began : Event

        data class Progress(
            val fraction: Float,
        ) : Event

        data object Finished : Event

        data object Failed : Event

        /** Play waits for Wi-Fi or for the user to confirm the download. */
        data class NeedsConfirmation(
            val waiting: Boolean,
        ) : Event
    }
}
