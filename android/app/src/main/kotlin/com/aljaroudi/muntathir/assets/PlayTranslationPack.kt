package com.aljaroudi.muntathir.assets

import com.aljaroudi.muntathir.core.quran.TranslationPack
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import java.io.File
import java.io.IOException

/** The `quran_translations` Play asset pack as the store's [TranslationPack]. */
class PlayTranslationPack(
    private val backend: AssetPackBackend,
) : TranslationPack {
    private val pack = ContentPack.QuranTranslations

    override suspend fun localDirectory(): File? =
        runCatching { backend.assets(pack) }
            .getOrNull()
            ?.let { File(it, pack.database).parentFile }
            ?.takeIf { File(it, File(pack.database).name).isFile }

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
        if (result !is PackStatus.Installed) throw IOException("Translations download failed: $result")
    }

    override suspend fun remove() = backend.remove(pack)

    /** Play's status updates; none when the asset-pack API is unavailable (not installed from Play). */
    override fun events(): Flow<TranslationPack.Event> =
        backend
            .updates(pack)
            .catch { }
            .mapNotNull { status ->
                when (status) {
                    PackStatus.Pending -> {
                        TranslationPack.Event.Began
                    }

                    is PackStatus.Downloading -> {
                        TranslationPack.Event.Progress(status.fraction)
                    }

                    PackStatus.Transferring -> {
                        TranslationPack.Event.Progress(1f)
                    }

                    PackStatus.WaitingForWifi, PackStatus.RequiresConfirmation -> {
                        TranslationPack.Event.NeedsConfirmation(
                            true,
                        )
                    }

                    is PackStatus.Installed -> {
                        TranslationPack.Event.Finished
                    }

                    is PackStatus.Failed, PackStatus.Canceled -> {
                        TranslationPack.Event.Failed
                    }

                    PackStatus.NotInstalled -> {
                        null
                    }
                }
            }
}
