import SwiftUI
import WeatherKit

struct WeatherCardScene: View {
    let condition: WeatherCondition?
    let sun: SolarPosition?
    let moon: MoonPosition?
    @Environment(\.layoutDirection) private var direction
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = WeatherSceneStyle(condition)
        let daylight = Self.isDaylight(sun)
        GeometryReader { geometry in
            let x = geometry.size.width * (direction == .rightToLeft ? 0.25 : 0.75)
            ZStack {
                LinearGradient(colors: [
                    (daylight ? Color.cyan : Color.indigo).opacity(colorScheme == .dark ? 0.23 : 0.12),
                    .clear,
                ], startPoint: .top, endPoint: .bottom)
                Group {
                    if daylight {
                        SunDisc(warm: (sun?.elevation ?? 20) < 10)
                    } else {
                        ZStack {
                            Circle().fill(Color.gray.opacity(0.18))
                            if let moon {
                                MoonDisc(fraction: moon.illuminatedFraction, waxing: moon.isWaxing)
                            }
                        }
                    }
                }
                .frame(width: 38, height: 38)
                .opacity(style == .cloudy || style == .storm ? 0.45 : 1)
                .position(x: x, y: 39)

                if style != .clear {
                    cloud
                        .frame(width: 76, height: 36)
                        .position(x: x - (direction == .rightToLeft ? -12 : 12), y: 59)
                }
                if style == .rain {
                    Path { path in
                        for offset in [-12.0, 0, 12] {
                            path.move(to: CGPoint(x: x + offset, y: 78))
                            path.addLine(to: CGPoint(x: x + offset - 4, y: 86))
                        }
                    }
                    .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                } else if let symbol = style.detailSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(style == .storm ? Color.orange : Color.secondary)
                        .position(x: x, y: 83)
                }
            }
        }
        // Coordinates already account for the locale's trailing edge.
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func isDaylight(_ sun: SolarPosition?) -> Bool {
        sun?.daylightProgress != nil
    }

    private var cloud: some View {
        Canvas { context, size in
            var path = Path()
            path.addRoundedRect(in: CGRect(x: 0, y: size.height * 0.42, width: size.width, height: size.height * 0.58), cornerSize: CGSize(width: 12, height: 12))
            path.addEllipse(in: CGRect(x: size.width * 0.18, y: 0, width: size.width * 0.46, height: size.height))
            path.addEllipse(in: CGRect(x: size.width * 0.48, y: size.height * 0.2, width: size.width * 0.36, height: size.height * 0.8))
            context.fill(path, with: .linearGradient(Gradient(colors: colorScheme == .dark ? [Color(white: 0.65), Color(white: 0.4)] : [.white, Color(white: 0.78)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}
