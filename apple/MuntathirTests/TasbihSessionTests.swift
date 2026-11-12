import CoreGraphics
@testable import Muntathir
import RealityKit
import Testing

struct TasbihSessionTests {
    @MainActor @Test func beadLayersStayAlignedAcrossDepthTransitions() {
        let scene = TasbihBeadScene()
        let rear = scene.rearRoot.children.compactMap { $0 as? ModelEntity }
        let front = scene.frontRoot.children.compactMap { $0 as? ModelEntity }
        #expect(rear.count == 193)
        #expect(front.count == rear.count)
        for phase: Float in [0, 0.25, 0.5, 1, 16.5, 33, 100] {
            scene.update(phase: phase, animated: false)
            for (back, near) in zip(rear, front) {
                #expect(back.position == near.position)
                let backOpacity = back.components[OpacityComponent.self]?.opacity ?? -1
                let frontOpacity = near.components[OpacityComponent.self]?.opacity ?? -1
                #expect(abs(frontOpacity + backOpacity * (1 - frontOpacity) - 1) < 0.0001)
                if near.position.z >= 0.12 {
                    #expect(frontOpacity == 1)
                } else if near.position.z <= -0.12 {
                    #expect(backOpacity == 1)
                } else {
                    #expect(frontOpacity > 0 && backOpacity > 0)
                }
            }
        }
    }

    @Test func countsTheThreePhrasesAndStops() {
        var session = TasbihSession()
        var total = 0
        for (phrase, target) in [("الله أكبر", 34), ("الحمد لله", 33), ("سبحان الله", 33)] {
            for count in 0 ..< target {
                #expect(session.total == total)
                #expect(session.complete == false)
                #expect(session.phrase == phrase)
                #expect(session.target == target)
                #expect(session.count == count)
                session.advance()
                total += 1
            }
        }
        #expect(session.complete)
        #expect(session.count == 33)
        session.advance()
        #expect(session.total == 100)
        session.reset()
        #expect(session == TasbihSession())
    }

    @Test(arguments: [CGSize(width: 0, height: 40), CGSize(width: 0, height: -100), CGSize(width: 100, height: 60), CGSize.zero])
    func rejectsInvalidPulls(_ translation: CGSize) {
        #expect(TasbihSession.acceptsPull(translation) == false)
    }

    @Test(arguments: [CGSize(width: 0, height: 41), CGSize(width: -20, height: 80), CGSize(width: 20, height: 400)])
    func acceptsOneCountPerDownwardPull(_ translation: CGSize) {
        var session = TasbihSession()
        if TasbihSession.acceptsPull(translation) {
            session.advance()
        }
        #expect(session.total == 1)
        #expect(TasbihSession.pullProgress(translation) <= 1)
    }

    @Test func dragProgressIsClampedAndDirectional() {
        #expect(TasbihSession.pullProgress(CGSize(width: 0, height: 40)) == 0.5)
        #expect(TasbihSession.pullProgress(CGSize(width: 0, height: 400)) == 1)
        #expect(TasbihSession.pullProgress(CGSize(width: 0, height: -80)) == 0)
        #expect(TasbihSession.pullProgress(CGSize(width: 90, height: 80)) == 0)
    }
}
