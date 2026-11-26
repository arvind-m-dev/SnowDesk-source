import AVFoundation

/// Tiny synthesizer: every sound is generated in code, nothing is bundled.
final class Sound {
    static let shared = Sound()

    enum Kind { case chime, bells, thunder, pop, splat }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let loopPlayer = AVAudioPlayerNode()
    private var buffers: [Kind: AVAudioPCMBuffer] = [:]
    private lazy var crackle = makeCrackle()

    private init() {
        for _ in 0..<5 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.attach(loopPlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.6
        // macOS stops the engine when the output device changes (headphones, AirPods...). Start it again.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.crackleWanted { self.startCrackle() }
        }
    }

    private var crackleWanted = false

    private func ensureStarted() -> Bool {
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        return true
    }

    func play(_ kind: Kind, volume: Float = 1) {
        guard Settings.shared.sounds, ensureStarted() else { return }
        let buf = buffers[kind] ?? make(kind)
        buffers[kind] = buf
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = volume
        p.scheduleBuffer(buf, at: nil, options: .interrupts)
        p.play()
    }

    func startCrackle() {
        crackleWanted = true
        guard Settings.shared.sounds, ensureStarted() else { return }
        loopPlayer.volume = 0.5
        loopPlayer.scheduleBuffer(crackle, at: nil, options: [.loops, .interrupts])
        loopPlayer.play()
    }

    func stopCrackle() {
        crackleWanted = false
        loopPlayer.stop()
    }

    /// Follow the Sounds switch: silence the crackle, or bring it back if the fire is still lit.
    func soundsChanged() {
        if Settings.shared.sounds { if crackleWanted { startCrackle() } } else { loopPlayer.stop() }
    }

    // MARK: - Synthesis

    private func buffer(seconds: Double, _ fill: (Int, Double) -> Float) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * 44100)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let d = b.floatChannelData![0]
        for i in 0..<Int(n) { d[i] = fill(i, Double(i) / 44100) }
        return b
    }

    private func make(_ kind: Kind) -> AVAudioPCMBuffer {
        switch kind {
        case .chime:
            let f: [(Double, Double)] = [(1318.5, 0.5), (1975.5, 0.3), (2637, 0.2), (3951, 0.08)]
            return buffer(seconds: 1.6) { _, t in
                Float(f.reduce(0) { $0 + sin(2 * .pi * $1.0 * t) * $1.1 * exp(-t * (2.5 + $1.0 / 1500)) } * 0.5)
            }
        case .bells:
            // A shake of small jingle bells: random metallic hits.
            var hits: [(Double, Double)] = []
            var t0 = 0.0
            while t0 < 1.7 { hits.append((t0, Double.random(in: 0.92...1.08))); t0 += Double.random(in: 0.05...0.14) }
            return buffer(seconds: 2.0) { _, t in
                var v = 0.0
                for (start, k) in hits where t >= start && t < start + 0.25 {
                    let u = t - start
                    let env = exp(-u * 22)
                    v += (sin(2 * .pi * 2900 * k * u) + 0.7 * sin(2 * .pi * 4100 * k * u) + 0.4 * sin(2 * .pi * 5600 * k * u)) * env * 0.18
                    v += Double.random(in: -1...1) * exp(-u * 60) * 0.05
                }
                let fade = t > 1.6 ? max(0, 1 - (t - 1.6) / 0.4) : 1
                return Float(v * fade)
            }
        case .thunder:
            var lp = 0.0, lp2 = 0.0
            return buffer(seconds: 4.0) { _, t in
                let n = Double.random(in: -1...1)
                lp += (n - lp) * 0.02
                lp2 += (lp - lp2) * 0.05
                let env = min(1, t / 0.08) * exp(-t * 0.9) * (0.7 + 0.3 * sin(t * 7) * sin(t * 2.3))
                return Float(lp2 * env * 9)
            }
        case .pop:
            return buffer(seconds: 0.5) { _, t in
                let f = 350 + 900 * min(1, t / 0.12)
                let s = sin(2 * .pi * f * t) * exp(-t * 14) * 0.4
                let sparkle = sin(2 * .pi * 2637 * t) * exp(-(t - 0.1) * 8) * (t > 0.1 ? 0.25 : 0)
                return Float(s + sparkle)
            }
        case .splat:
            var lp = 0.0
            return buffer(seconds: 0.25) { _, t in
                lp += (Double.random(in: -1...1) - lp) * 0.25
                return Float(lp * exp(-t * 18) * 1.2)
            }
        }
    }

    /// Loopable fire crackle: soft rumble plus random pops.
    private func makeCrackle() -> AVAudioPCMBuffer {
        var lp = 0.0
        var pops: [(Double, Double)] = []
        var t0 = 0.0
        while t0 < 6 { pops.append((t0, Double.random(in: 0.2...1))); t0 += Double.random(in: 0.02...0.25) }
        return buffer(seconds: 6) { _, t in
            lp += (Double.random(in: -1...1) - lp) * 0.03
            var v = lp * 0.25
            for (start, a) in pops where t >= start && t < start + 0.02 {
                v += Double.random(in: -1...1) * a * exp(-(t - start) * 300) * 0.6
            }
            return Float(v)
        }
    }
}
