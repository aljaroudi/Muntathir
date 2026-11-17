package com.aljaroudi.muntathir.assets

import com.aljaroudi.muntathir.core.assets.AssetPack
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import java.io.File
import java.io.IOException

/** A Play asset pack as a core [AssetPack]; [localDirectory] is the folder holding the pack's database. */
class PlayAssetPack(
    private val backend: AssetPackBackend,
    private val pack: ContentPack,
) : AssetPack {
    override suspend fun localDirectory(): File? =
        runCatching { backend.assets(pack) }
            .getOrNull()
            ?.let { File(it, pack.database) }
            ?.takeIf(File::isFile)
            ?.parentFile

    override suspend fun isDownloading(): Boolean =
        when (runCatching { backend.status(pack) }.getOrNull()) {
            PackStatus.Pending,
            is PackStatus.Downloading,
            PackStatus.Transferring,
            PackStatus.WaitingForWifi,
            PackStatus.RequiresConfirmation,
            -> true

            else -> false
        }

    /** Requests the pack, then waits until Play installs it or gives up. */
    override suspend fun download() {
        backend.download(pack)
        val result =
            backend.updates(pack).first {
                it is PackStatus.Installed || it is PackStatus.Failed ||
                    it is PackStatus.Canceled
            }
        if (result !is PackStatus.Installed) throw IOException("${pack.packName} download failed: $result")
    }

    override suspend fun remove() = backend.remove(pack)

    /** Play's status updates; none when the asset-pack API is unavailable (not installed from Play). */
    override fun events(): Flow<AssetPack.Event> =
        backend
            .updates(pack)
            .catch { }
            .mapNotNull { status ->
                when (status) {
                    PackStatus.Pending -> {
                        AssetPack.Event.Began
                    }

                    is PackStatus.Downloading -> {
                        AssetPack.Event.Progress(status.fraction)
                    }

                    PackStatus.Transferring -> {
                        AssetPack.Event.Progress(1f)
                    }

                    PackStatus.WaitingForWifi, PackStatus.RequiresConfirmation -> {
                        AssetPack.Event.NeedsConfirmation(
                            true,
                        )
                    }

                    is PackStatus.Installed -> {
                        AssetPack.Event.Finished
                    }

                    is PackStatus.Failed, PackStatus.Canceled -> {
                        AssetPack.Event.Failed
                    }

                    PackStatus.NotInstalled -> {
                        null
                    }
                }
            }
}
