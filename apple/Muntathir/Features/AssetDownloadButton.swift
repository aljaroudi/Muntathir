import SwiftUI

struct AssetDownloadButton: View {
    let pack: String
    var retry = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                if let bytes = AssetDownloadSize.bytes(for: pack) {
                    AssetSizeText(bytes: bytes)
                } else {
                    Text("Download")
                }
            } icon: {
                Image(systemName: retry ? "arrow.clockwise" : "arrow.down.circle")
            }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(retry ? Text("Try again") : Text("Download"))
        .accessibilityValue(Text(AssetDownloadSize.roundedBytes(AssetDownloadSize.bytes(for: pack) ?? 0), format: .byteCount(style: .file, spellsOutZero: false)))
    }
}
