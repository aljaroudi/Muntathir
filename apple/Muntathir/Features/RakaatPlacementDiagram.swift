import SwiftUI

struct RakaatPlacementDiagram: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 320
            context.scaleBy(x: scale, y: scale)
            var body = Path()
            body.move(to: CGPoint(x: 275, y: 112))
            body.addLine(to: CGPoint(x: 238, y: 108))
            body.addQuadCurve(to: CGPoint(x: 211, y: 35), control: CGPoint(x: 250, y: 50))
            body.addQuadCurve(to: CGPoint(x: 125, y: 70), control: CGPoint(x: 175, y: 20))
            body.addLine(to: CGPoint(x: 158, y: 108))
            body.addLine(to: CGPoint(x: 110, y: 112))
            context.stroke(body, with: .foreground, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: 82, y: 70, width: 39, height: 36)), with: .foreground)
            context.fill(Path(roundedRect: CGRect(x: 92, y: 118, width: 66, height: 7), cornerRadius: 3), with: .color(.accentColor))
            context.fill(Path(ellipseIn: CGRect(x: 99, y: 115, width: 6, height: 6)), with: .color(.white))
            var ground = Path()
            ground.move(to: CGPoint(x: 20, y: 128)); ground.addLine(to: CGPoint(x: 300, y: 128))
            context.stroke(ground, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
        }
        .aspectRatio(320 / 145, contentMode: .fit)
        .frame(maxWidth: 360)
        .accessibilityHidden(true)
        .environment(\.layoutDirection, .leftToRight)
    }
}
