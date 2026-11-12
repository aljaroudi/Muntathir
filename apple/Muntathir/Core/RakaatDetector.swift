import Foundation

struct RakaatDetector: Sendable {
    let target: Int
    private(set) var sujoodCount = 0
    private(set) var baseline: Double?
    private var samples: [(time: Double, light: Double)] = []
    private var transitionStart: Double?
    private var covered = false
    private var lastTime: Double?

    var rakaat: Int {
        sujoodCount / 2
    }

    var complete: Bool {
        sujoodCount >= target * 2
    }

    init(target: Int) {
        precondition((2 ... 4).contains(target))
        self.target = target
    }

    mutating func sample(_ light: Double, at time: Double) {
        guard !complete, light.isFinite, (0 ... 1).contains(light), time.isFinite else { return }
        if let lastTime {
            guard time > lastTime else { return }
            if time - lastTime > 0.3 {
                transitionStart = nil
                samples.removeAll()
            }
        }
        lastTime = time
        guard let baseline else {
            samples.append((time, light))
            samples.removeAll { time - $0.time > 1.2 }
            guard let first = samples.first, time - first.time >= 1, samples.count >= 8 else { return }
            let mean = samples.map(\.light).reduce(0, +) / Double(samples.count)
            let spread = (samples.map(\.light).max() ?? 0) - (samples.map(\.light).min() ?? 0)
            guard mean >= 0.08, spread <= mean * 0.15 else { return }
            baseline = mean
            samples.removeAll()
            return
        }
        let transitioning = covered ? light >= baseline * 0.7 : light <= baseline * 0.4
        if transitioning {
            if transitionStart == nil {
                transitionStart = time
            }
            if time - (transitionStart ?? time) >= 0.5 {
                covered.toggle()
                if covered {
                    sujoodCount += 1
                }
                transitionStart = nil
            }
        } else {
            transitionStart = nil
            if !covered, light >= baseline * 0.7 {
                self.baseline = baseline * 0.995 + light * 0.005
            }
        }
    }
}
