import SwiftUI

struct RakaatHeadingOrientation: UIViewRepresentable {
    let onChange: (UIInterfaceOrientation) -> Void

    func makeUIView(context _: Context) -> OrientationView {
        let view = OrientationView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: OrientationView, context _: Context) {
        view.onChange = onChange
        view.setNeedsLayout()
    }

    final class OrientationView: UIView {
        var onChange: ((UIInterfaceOrientation) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            if let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation {
                onChange?(orientation)
            }
        }
    }
}
