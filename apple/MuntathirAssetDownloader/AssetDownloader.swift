import BackgroundAssets
import StoreKit
import ExtensionFoundation

@main
struct AssetDownloader: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        assetPack.id == "hadith"
    }
}
