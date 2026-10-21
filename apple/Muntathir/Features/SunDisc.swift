import SwiftUI

struct SunDisc: View {
    let warm: Bool

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white, warm ? Color(red: 1, green: 0.72, blue: 0.34) : Color(red: 1, green: 0.94, blue: 0.68)], center: .topLeading, startRadius: 0, endRadius: 30))
            .shadow(color: .orange.opacity(0.35), radius: 12)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [Color.orange.opacity(0.4), .clear], center: .center, startRadius: 12, endRadius: 52))
                    .frame(width: 104, height: 104)
            }
    }
}
