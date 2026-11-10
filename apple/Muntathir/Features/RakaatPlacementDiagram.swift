import SwiftUI

struct RakaatPlacementDiagram: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / 260)
            context.translateBy(x: (size.width - 240 * scale) / 2, y: 0)
            context.scaleBy(x: scale, y: scale)
            let rug = Path(roundedRect: CGRect(x: 44, y: 15, width: 152, height: 230), cornerRadius: 8)
            context.fill(rug, with: .color(.accentColor.opacity(0.12)))
            context.stroke(rug, with: .color(.accentColor), lineWidth: 2)
            let border = Path(roundedRect: CGRect(x: 54, y: 25, width: 132, height: 210), cornerRadius: 4)
            context.stroke(border, with: .color(.accentColor.opacity(0.6)), lineWidth: 1)
            var arch = Path()
            arch.move(to: CGPoint(x: 68, y: 217))
            arch.addLine(to: CGPoint(x: 68, y: 85))
            arch.addQuadCurve(to: CGPoint(x: 120, y: 39), control: CGPoint(x: 68, y: 59))
            arch.addQuadCurve(to: CGPoint(x: 172, y: 85), control: CGPoint(x: 172, y: 59))
            arch.addLine(to: CGPoint(x: 172, y: 217))
            context.stroke(arch, with: .color(.accentColor.opacity(0.6)), lineWidth: 2)
            var fringe = Path()
            for x in stride(from: 54, through: 186, by: 11) {
                fringe.move(to: CGPoint(x: x, y: 8))
                fringe.addLine(to: CGPoint(x: x, y: 15))
                fringe.move(to: CGPoint(x: x, y: 245))
                fringe.addLine(to: CGPoint(x: x, y: 252))
            }
            context.stroke(fringe, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let phone = Path(roundedRect: CGRect(x: 103, y: 73, width: 34, height: 65), cornerRadius: 6)
            context.fill(phone, with: .color(.black))
            context.stroke(phone, with: .foreground, lineWidth: 1)
            context.fill(Path(roundedRect: CGRect(x: 106, y: 81, width: 28, height: 49), cornerRadius: 2), with: .color(.accentColor))
            context.fill(Path(ellipseIn: CGRect(x: 118, y: 75, width: 4, height: 4)), with: .color(.white))
        }
        .aspectRatio(240.0 / 260, contentMode: .fit)
        .frame(maxWidth: 240)
        .accessibilityHidden(true)
        .environment(\.layoutDirection, .leftToRight)
    }
}
