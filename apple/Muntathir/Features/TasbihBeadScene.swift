import RealityKit
import SwiftUI

@MainActor
final class TasbihBeadScene {
    let root = Entity()
    private var beads: [ModelEntity] = []
    private var phase: Float = 0
    private static let beadCount = 33
    private static let radius: Float = 0.42
    private static let halfHeight: Float = 0.95
    private static let perimeter = 4 * halfHeight + 2 * Float.pi * radius

    init() {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 38
        camera.position = [0, 0, 5]
        root.addChild(camera)

        let key = DirectionalLight()
        key.light.intensity = 2400
        key.look(at: .zero, from: [-3, 4, 5], relativeTo: nil)
        root.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [3, 1, -2], relativeTo: nil)
        root.addChild(fill)

        let mesh = MeshResource.generateSphere(radius: 0.088)
        for index in 0 ..< Self.beadCount {
            let shade = CGFloat(index % 4) * 0.025
            let material = SimpleMaterial(color: UIColor(red: 0.43 + shade, green: 0.24 + shade, blue: 0.12 + shade, alpha: 1), roughness: 0.32, isMetallic: false)
            let bead = ModelEntity(mesh: mesh, materials: [material])
            bead.position = Self.position(Float(index) / Float(Self.beadCount))
            beads.append(bead)
            root.addChild(bead)
        }

        let cordMaterial = SimpleMaterial(color: .init(red: 0.70, green: 0.54, blue: 0.32, alpha: 1), roughness: 0.9, isMetallic: false)
        for index in 0 ..< 160 {
            let start = Self.position(Float(index) / 160)
            let end = Self.position(Float(index + 1) / 160)
            let segment = ModelEntity(mesh: .generateCylinder(height: simd_distance(start, end) + 0.002, radius: 0.012), materials: [cordMaterial])
            segment.position = (start + end) / 2
            segment.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(end - start))
            root.addChild(segment)
        }
    }

    func update(phase: Float, animated: Bool) {
        guard self.phase != phase else { return }
        self.phase = phase
        let move = {
            for (index, bead) in self.beads.enumerated() {
                bead.position = Self.position((Float(index) + phase) / Float(Self.beadCount))
            }
        }
        if animated {
            Entity.animate(.easeOut(duration: 0.18), body: move)
        } else {
            move()
        }
    }

    /// Constant spacing around a capsule; the nearer strand descends as the rear ascends.
    private static func position(_ fraction: Float) -> SIMD3<Float> {
        let distance = (fraction - floor(fraction)) * perimeter
        let straight = 2 * halfHeight
        let arc = Float.pi * radius
        let point: SIMD3<Float>
        if distance < straight {
            point = [radius, halfHeight - distance, 0]
        } else if distance < straight + arc {
            let angle = (distance - straight) / radius
            point = [radius * cos(angle), -halfHeight - radius * sin(angle), 0]
        } else if distance < 2 * straight + arc {
            point = [-radius, -halfHeight + distance - straight - arc, 0]
        } else {
            let angle = (distance - 2 * straight - arc) / radius
            point = [-radius * cos(angle), halfHeight + radius * sin(angle), 0]
        }
        return simd_quatf(angle: -.pi / 3, axis: [0, 1, 0]).act(point)
    }
}
