import SwiftUI

enum HadithBookStyle {
    static func background(for collectionID: String) -> Color {
        // Tailwind orange-500 and emerald-500, blended into the adaptive surface as book identity, not status.
        let accent: Color = switch HadithBookGroup(collectionID: collectionID) {
        case .six:
            Color(red: 1, green: 105 / 255, blue: 0)
        default:
            Color(red: 0, green: 188 / 255, blue: 125 / 255)
        }
        return Color(uiColor: .secondarySystemGroupedBackground).mix(with: accent, by: 0.06)
    }
}
