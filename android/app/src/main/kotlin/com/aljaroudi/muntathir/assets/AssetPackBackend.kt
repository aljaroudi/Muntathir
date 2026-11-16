package com.aljaroudi.muntathir.assets

import android.app.Activity
import android.content.Context
import com.google.android.play.core.assetpacks.AssetPackManager
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import com.google.android.play.core.assetpacks.AssetPackState
import com.google.android.play.core.assetpacks.AssetPackStateUpdateListener
import com.google.android.play.core.assetpacks.model.AssetPackStatus
import com.google.android.play.core.ktx.assetsPath
import com.google.android.play.core.ktx.bytesDownloaded
import com.google.android.play.core.ktx.errorCode
import com.google.android.play.core.ktx.name
import com.google.android.play.core.ktx.requestCellularDataConfirmation
import com.google.android.play.core.ktx.requestFetch
import com.google.android.play.core.ktx.requestPackStates
import com.google.android.play.core.ktx.requestRemovePack
import com.google.android.play.core.ktx.status
import com.google.android.play.core.ktx.totalBytesToDownload
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.io.File

/** Downloadable content packs, named as in `android/packs/`. */
enum class ContentPack(
    val packName: String,
    /** Database path inside the pack's assets folder. */
    val database: String,
) {
    Hadith("hadith", "Hadith/hadith.db"),
    Supplications("supplications", "Supplications/supplications.db"),
}

sealed interface PackStatus {
    data object NotInstalled : PackStatus

    data object Pending : PackStatus

    data class Downloading(
        val bytes: Long,
        val total: Long,
    ) : PackStatus {
        val fraction: Float get() = if (total > 0) bytes.toFloat() / total else 0f
    }

    /** Downloaded; Play is moving files into app storage. */
    data object Transferring : PackStatus

    /** Large packs wait for Wi-Fi until the user allows mobile data. */
    data object WaitingForWifi : PackStatus

    /** Play needs the user to confirm the download (e.g. the app wasn't installed from Play). */
    data object RequiresConfirmation : PackStatus

    data class Installed(
        val assets: File,
    ) : PackStatus

    data class Failed(
        val errorCode: Int,
    ) : PackStatus

    data object Canceled : PackStatus
}

/** Where content packs come from. Mirrors iOS `AssetPackBackend`; tests substitute a fake. */
interface AssetPackBackend {
    /** The installed pack's assets folder, or `null` while it isn't installed. */
    fun assets(pack: ContentPack): File?

    suspend fun status(pack: ContentPack): PackStatus

    /** Status updates for downloads started by [download]. */
    fun updates(pack: ContentPack): Flow<PackStatus>

    suspend fun download(pack: ContentPack): PackStatus

    /** Asks to download over mobile data or confirm the download; returns whether the user accepted. */
    suspend fun confirm(activity: Activity): Boolean

    suspend fun remove(pack: ContentPack)
}

class PlayAssetPackBackend(
    context: Context,
    private val manager: AssetPackManager = AssetPackManagerFactory.getInstance(context),
) : AssetPackBackend {
    override fun assets(pack: ContentPack): File? = manager.getPackLocation(pack.packName)?.assetsPath?.let(::File)

    override suspend fun status(pack: ContentPack): PackStatus =
        manager.requestPackStates(listOf(pack.packName)).packStates()[pack.packName]?.let(::status)
            ?: PackStatus.NotInstalled

    /**
     * Starts with the current status, then each update. Not ktx's `requestProgressFlow`: asset-delivery-ktx 2.3.0
     * calls a coroutines API removed in kotlinx-coroutines 1.11 and crashes (NoSuchMethodError).
     */
    override fun updates(pack: ContentPack): Flow<PackStatus> =
        callbackFlow {
            val listener =
                AssetPackStateUpdateListener { state ->
                    if (state.name == pack.packName) trySend(status(state))
                }
            manager.registerListener(listener)
            send(status(pack))
            awaitClose { manager.unregisterListener(listener) }
        }

    override suspend fun download(pack: ContentPack): PackStatus =
        manager.requestFetch(listOf(pack.packName)).packStates()[pack.packName]?.let(::status) ?: PackStatus.Pending

    override suspend fun confirm(activity: Activity): Boolean =
        manager.requestCellularDataConfirmation(activity) == Activity.RESULT_OK

    override suspend fun remove(pack: ContentPack) = manager.requestRemovePack(pack.packName)

    private fun status(state: AssetPackState): PackStatus =
        when (state.status) {
            AssetPackStatus.PENDING -> {
                PackStatus.Pending
            }

            AssetPackStatus.DOWNLOADING -> {
                PackStatus.Downloading(state.bytesDownloaded, state.totalBytesToDownload)
            }

            AssetPackStatus.TRANSFERRING -> {
                PackStatus.Transferring
            }

            AssetPackStatus.WAITING_FOR_WIFI -> {
                PackStatus.WaitingForWifi
            }

            AssetPackStatus.REQUIRES_USER_CONFIRMATION -> {
                PackStatus.RequiresConfirmation
            }

            AssetPackStatus.FAILED -> {
                PackStatus.Failed(state.errorCode)
            }

            AssetPackStatus.CANCELED -> {
                PackStatus.Canceled
            }

            AssetPackStatus.COMPLETED -> {
                manager.getPackLocation(state.name)?.assetsPath?.let { PackStatus.Installed(File(it)) }
                    ?: PackStatus.Transferring
            }

            else -> {
                PackStatus.NotInstalled
            }
        }
}
