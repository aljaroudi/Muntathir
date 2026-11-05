import SwiftUI

struct AssetSizeText: View {
    let bytes: Int64

    var body: some View {
        Text(AssetDownloadSize.roundedBytes(bytes), format: .byteCount(style: .file, spellsOutZero: false))
    }
}
