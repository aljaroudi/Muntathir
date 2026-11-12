import SwiftUI

extension View {
    func readingBackground() -> some View {
        scrollContentBackground(.hidden)
            .background {
                Color(uiColor: .secondarySystemGroupedBackground)
                    .mix(with: Color(red: 0, green: 188 / 255, blue: 125 / 255), by: 0.06)
                    .ignoresSafeArea()
            }
    }
}
