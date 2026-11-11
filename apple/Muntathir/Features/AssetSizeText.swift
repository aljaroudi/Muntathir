import SwiftUI

struct AssetSizeText: View {
    @Environment(\.locale) private var locale
    let bytes: Int64
    var isEstimated = false

    var body: some View {
        let size = AssetDownloadSize.roundedBytes(bytes)
            .formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))

        if isEstimated {
            Text(verbatim: "≈ \(size)")
                .accessibilityLabel(Text("Estimated size: \(size)"))
        } else {
            Text(verbatim: size)
        }
    }
}
