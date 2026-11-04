import BackgroundAssets
import ExtensionFoundation
import StoreKit

@main
struct AssetDownloader: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        ["hadith", "quran-translations"].contains(assetPack.id)
    }
}
