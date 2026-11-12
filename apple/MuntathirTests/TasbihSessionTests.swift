import CoreGraphics
@testable import Muntathir
import Testing

struct TasbihSessionTests {
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
