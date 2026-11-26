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

    /// Continues counting with a baseline measured by a previous session under the same locked exposure.
    init(target: Int, baseline: Double) {
        self.init(target: target)
        self.baseline = baseline
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
            samples.removeAll { time - $0.time > 0.7 }
            guard let first = samples.first, time - first.time >= 0.5, samples.count >= 5 else { return }
            let mean = samples.map(\.light).reduce(0, +) / Double(samples.count)
            let spread = (samples.map(\.light).max() ?? 0) - (samples.map(\.light).min() ?? 0)
            guard mean >= 0.08, spread <= mean * 0.25 else { return }
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
                // Rise faster than we fall, so a baseline taken while the user was still over the phone
                // catches up once they step away, while gradual dimming is still tracked without counting.
                let rate = light > baseline ? 0.05 : 0.005
                self.baseline = baseline + (light - baseline) * rate
            }
        }
    }
}
