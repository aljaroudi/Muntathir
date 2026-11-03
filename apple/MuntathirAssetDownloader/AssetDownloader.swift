import BackgroundAssets
import ExtensionFoundation
import StoreKit

@main
struct AssetDownloader: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        assetPack.id == "hadith"
    }
}
