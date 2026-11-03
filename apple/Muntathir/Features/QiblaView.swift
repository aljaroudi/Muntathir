import MapKit
import SwiftUI

struct QiblaView: View {
    var isCovered = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var session = QiblaLocationSession()
    @State private var visible = false
    @State private var aligned = false

    private var alignment: QiblaAlignment? {
        guard let location = session.location, let heading = session.heading else { return nil }
        let saved = SavedLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                  name: "", countryCode: "", timeZoneID: TimeZone.current.identifier)
        return QiblaAlignment(bearing: PrayerCalculator.qibla(saved), heading: heading.trueHeading)
    }

    private var feedback: QiblaAlignment.Feedback {
        guard visible, !isCovered, scenePhase == .active else { return .none }
        return alignment?.feedback(aligned: aligned) ?? .none
    }

    var body: some View {
        Group {
            if let location = session.location {
                QiblaMap(location: location, aligned: aligned, onOrientationChange: session.orientHeading)
                    .accessibilityLabel(Text("Current location and direction to the Kaaba"))
                    .accessibilityIdentifier("qibla-map-ready")
                    .overlay {
                        if let heading = session.heading {
                            ZStack {
                                Circle()
                                    .stroke(aligned ? Color.green : .white.opacity(0.6), lineWidth: aligned ? 4 : 2)
                                    .frame(width: 76, height: 76)
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(aligned ? .green : .white)
                                    .offset(y: -28)
                                    .rotationEffect(.degrees(heading.trueHeading))
                                    .accessibilityLabel(Text("Device direction"))
                                    .accessibilityIdentifier("qibla-heading-indicator")
                            }
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .allowsHitTesting(false)
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        alignmentBadge
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
            } else {
                ContentUnavailableView {
                    Label("Precise location required", systemImage: "location")
                } description: {
                    switch session.status {
                    case .settings:
                        Text("Allow location access and Precise Location in Settings to find Qibla.")
                    case .failed:
                        Text("Could not get a precise current location. Try again outdoors.")
                    default:
                        Text("Finding your precise current location…")
                    }
                } actions: {
                    if session.status == .locating {
                        ProgressView()
                    } else {
                        if session.status == .settings {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                        }
                        Button("Retry") { session.start() }
                    }
                }
                .accessibilityIdentifier("qibla-location-required")
            }
        }
        .navigationTitle("Qibla")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: alignment, initial: true) {
            aligned = alignment?.isAligned(previously: aligned) ?? false
        }
        .task(id: feedback) {
            if feedback == .aligned {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else if let pulse = feedback.pulse {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                while !Task.isCancelled {
                    generator.prepare()
                    do { try await Task.sleep(for: .seconds(pulse.interval)) } catch { return }
                    guard !Task.isCancelled, visible, !isCovered, scenePhase == .active else { return }
                    generator.impactOccurred(intensity: pulse.intensity)
                }
            }
        }
        .onAppear { visible = true; updateSession() }
        .onDisappear { visible = false; session.stop() }
        .onChange(of: scenePhase) { updateSession() }
        .onChange(of: isCovered) { updateSession() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                session.refresh()
            }
        }
    }

    private var alignmentBadge: some View {
        HStack(spacing: 10) {
            if aligned {
                Label {
                    Text("Aligned with Kaaba")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .accessibilityIdentifier("qibla-aligned")
            } else if let alignment {
                Image(systemName: alignment.error < 0 ? "arrow.counterclockwise" : "arrow.clockwise")
                    .environment(\.layoutDirection, .leftToRight)
                Text(alignment.error < 0 ? LocalizedStringKey("Turn left") : LocalizedStringKey("Turn right"))
                Text(Measurement(value: abs(alignment.error), unit: UnitAngle.degrees),
                     format: .measurement(width: .narrow, usage: .asProvided,
                                          numberFormatStyle: .number.precision(.fractionLength(0))))
                    .monospacedDigit()
            } else {
                Label("Compass unavailable", systemImage: "location.slash")
            }
        }
        .font(.headline)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private func updateSession() {
        if visible, !isCovered, scenePhase == .active {
            session.start()
        } else {
            session.stop()
        }
    }
}

struct QiblaMap: UIViewRepresentable {
    // Same destination as Adhan's Qibla calculation.
    static let kaaba = CLLocationCoordinate2D(latitude: 21.4225241, longitude: 39.8261818)
    let location: CLLocation
    var aligned = false
    var onOrientationChange: (UIInterfaceOrientation) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> QiblaMapView {
        let map = QiblaMapView()
        map.delegate = context.coordinator
        map.onOrientationChange = onOrientationChange
        map.insetsLayoutMarginsFromSafeArea = false
        map.layoutMargins = .zero
        map.mapType = .hybrid
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: QiblaMapView, context: Context) {
        context.coordinator.aligned = aligned
        map.tintColor = aligned ? .systemGreen : .systemTeal
        for overlay in map.overlays {
            if let renderer = map.renderer(for: overlay) as? MKPolylineRenderer {
                renderer.strokeColor = aligned ? .systemGreen : .systemTeal
            }
        }
        // Supply only the validated fix; MapKit must not start a second location stream.
        if context.coordinator.location != location {
            map.removeAnnotations(map.annotations)
            map.addAnnotation(QiblaUserLocation(location: location))
            context.coordinator.location = location
        }
        if context.coordinator.coordinate?.latitude != location.coordinate.latitude
            || context.coordinator.coordinate?.longitude != location.coordinate.longitude
        {
            context.coordinator.coordinate = location.coordinate
            map.removeOverlays(map.overlays)
            var points = [location.coordinate, Self.kaaba]
            map.addOverlay(MKGeodesicPolyline(coordinates: &points, count: points.count))
            map.centerOnFix(location.coordinate)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var coordinate: CLLocationCoordinate2D?
        var location: CLLocation?
        var aligned = false

        func mapView(_: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let view = MKUserLocationView(annotation: annotation, reuseIdentifier: nil)
            view.isEnabled = false
            return view
        }

        func mapView(_: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = aligned ? .systemGreen : .systemTeal
            renderer.lineWidth = 4
            return renderer
        }
    }
}

private final class QiblaUserLocation: MKUserLocation {
    private let fix: CLLocation
    override var location: CLLocation? {
        fix
    }

    override var coordinate: CLLocationCoordinate2D {
        fix.coordinate
    }

    init(location: CLLocation) {
        fix = location
        super.init()
    }
}

final class QiblaMapView: MKMapView {
    var onOrientationChange: (UIInterfaceOrientation) -> Void = { _ in }
    private var lastOrientation: UIInterfaceOrientation?
    private var focus: CLLocationCoordinate2D?
    private var lastSize: CGSize = .zero

    func centerOnFix(_ coordinate: CLLocationCoordinate2D) {
        focus = coordinate
        updateRegion()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation, orientation != lastOrientation {
            lastOrientation = orientation
            onOrientationChange(orientation)
        }
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        updateRegion()
    }

    private func updateRegion() {
        guard let focus, bounds.width > 0, bounds.height > 0 else { return }
        setRegion(MKCoordinateRegion(center: focus, latitudinalMeters: 150 * bounds.height / bounds.width,
                                     longitudinalMeters: 150), animated: false)
    }
}
