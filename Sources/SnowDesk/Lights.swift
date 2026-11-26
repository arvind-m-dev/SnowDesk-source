import SpriteKit
import AVFoundation

/// Strings of fairy lights along the top of every window.
final class LightsEffect: SceneEffect {
    private struct Bulb {
        let core: SKShapeNode
        let glow: SKSpriteNode
        let x: CGFloat
        let phase: CGFloat
        let speed: CGFloat
        let index: Int
    }

    private final class Strand {
        let root = SKNode()
        var wire = SKShapeNode()
        var bulbs: [Bulb] = []
        var width: CGFloat = 0
    }

    var mode: LightsMode {
        didSet { if mode != oldValue { updateMic() } }
    }
    private var strands: [CGWindowID: Strand] = [:]
    private var finishing = false
    private var fade: CGFloat = 0
    private var beat: CGFloat = 0
    private var beatPattern = 0
    private let mic = MicBeat()

    private static let colors = [rgb(1, 0.25, 0.2), rgb(0.3, 0.95, 0.4), rgb(1, 0.8, 0.3), rgb(0.35, 0.6, 1), rgb(1, 0.45, 0.8)]

    init(mode: LightsMode) {
        self.mode = mode
        mic.onBeat = { [weak self] strength in
            guard let self else { return }
            self.beat = max(self.beat, 0.5 + strength * 0.5)
            self.beatPattern = (self.beatPattern + Int.random(in: 1...3)) % 4
        }
        updateMic()
    }

    var isFinishing: Bool { finishing }

    func finish() {
        finishing = true
        mic.stop()
    }

    private func updateMic() {
        if mode == .music && !finishing { mic.start() } else { mic.stop() }
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        fade = finishing ? max(0, fade - dt * 1.5) : min(1, fade + dt * 1.2)
        if finishing && fade <= 0 {
            strands.values.forEach { $0.root.removeFromParent() }
            return false
        }
        beat *= exp(-5 * dt)
        let tf = CGFloat(t)
        var seen = Set<CGWindowID>()
        for s in scene.visibleWindows where s.rect.width > 140 && s.rect.maxY < scene.size.height - 4 {
            seen.insert(s.id)
            let strand = strands[s.id] ?? {
                let n = Strand()
                n.root.zPosition = 30
                scene.addChild(n.root)
                strands[s.id] = n
                return n
            }()
            if abs(strand.width - s.rect.width) > 1 { build(strand, width: s.rect.width) }
            strand.root.isHidden = false
            strand.root.alpha = fade
            strand.root.position = CGPoint(x: s.rect.minX, y: s.rect.maxY)
            let step = Int(tf * 6)
            var anyVisible = false
            defer { strand.wire.isHidden = !anyVisible }
            for b in strand.bulbs {
                let c = min(s.pile.count - 1, max(0, Int(b.x / Pile.colW)))
                let visible = s.pile.exposed[c]
                b.core.isHidden = !visible
                b.glow.isHidden = !visible
                guard visible else { continue }
                anyVisible = true
                var lvl: CGFloat
                switch mode {
                case .twinkle, .off:
                    lvl = 0.55 + 0.45 * sin(tf * b.speed + b.phase)
                case .chase:
                    lvl = (b.index + step) % 4 == 0 ? 1 : 0.25
                case .music:
                    let on: Bool
                    switch beatPattern {
                    case 0: on = true
                    case 1: on = b.index % 2 == 0
                    case 2: on = b.index % 2 == 1
                    default: on = b.index % 3 == 0
                    }
                    lvl = mic.isListening ? 0.15 + 0.85 * beat * (on ? 1 : 0.2) : 0.55 + 0.45 * sin(tf * b.speed + b.phase)
                }
                b.core.alpha = 0.45 + 0.55 * lvl
                b.glow.alpha = 0.1 + 0.8 * lvl
            }
        }
        for (id, st) in strands where !seen.contains(id) {
            if scene.windows[id] == nil {
                st.root.removeFromParent()
                strands[id] = nil
            } else {
                st.root.isHidden = true
            }
        }
        return true
    }

    private func build(_ strand: Strand, width: CGFloat) {
        strand.root.removeAllChildren()
        strand.bulbs = []
        strand.width = width
        let spans = max(1, Int(width / 110))
        let span = width / CGFloat(spans)
        let sag: CGFloat = 9
        func wireY(_ x: CGFloat) -> CGFloat {
            let u = (x.truncatingRemainder(dividingBy: span)) / span
            return -3 - sag * 4 * u * (1 - u)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: wireY(0)))
        var x: CGFloat = 0
        while x <= width {
            path.addLine(to: CGPoint(x: x, y: wireY(x)))
            x += 5
        }
        let wire = SKShapeNode(path: path)
        wire.strokeColor = rgb(0.15, 0.25, 0.15, 0.9)
        wire.lineWidth = 1.2
        strand.root.addChild(wire)
        strand.wire = wire

        var i = 0
        var bx: CGFloat = 13
        while bx < width - 8 {
            let color = LightsEffect.colors[i % LightsEffect.colors.count]
            let y = wireY(bx) - 5
            let glow = glowSprite(color, size: 24)
            glow.position = CGPoint(x: bx, y: y)
            let core = Shape.ellipse(CGRect(x: -2.6, y: -4.5, width: 5.2, height: 9), fill: color)
            core.position = CGPoint(x: bx, y: y)
            core.addChild(Shape.rect(CGRect(x: -1.8, y: 3.5, width: 3.6, height: 3), radius: 0.5, fill: rgb(0.2, 0.25, 0.2)))
            strand.root.addChild(glow)
            strand.root.addChild(core)
            strand.bulbs.append(Bulb(core: core, glow: glow, x: bx, phase: .random(in: 0...6.28), speed: .random(in: 0.8...2.2), index: i))
            i += 1
            bx += 26
        }
    }
}

/// Listens to the microphone and reports beats (sudden jumps in loudness).
final class MicBeat {
    var onBeat: ((CGFloat) -> Void)?
    private(set) var isListening = false
    private var engine: AVAudioEngine?
    private var avg: Float = 0.01
    private var lastBeat: CFTimeInterval = 0
    private var wanted = false

    func start() {
        wanted = true
        guard !isListening else { return }
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok, self.wanted, !self.isListening else { return }
                self.begin()
            }
        }
    }

    private func begin() {
        let e = AVAudioEngine()
        let input = e.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            guard let d = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += d[i] * d[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            DispatchQueue.main.async { self?.process(rms) }
        }
        do {
            try e.start()
            engine = e
            isListening = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func process(_ rms: Float) {
        avg = avg * 0.94 + rms * 0.06
        let now = CACurrentMediaTime()
        if rms > avg * 1.45 && rms > 0.008 && now - lastBeat > 0.18 {
            lastBeat = now
            onBeat?(CGFloat(min(1, rms / max(avg, 0.0001) / 3)))
        }
    }

    func stop() {
        wanted = false
        guard let e = engine else { return }
        e.inputNode.removeTap(onBus: 0)
        e.stop()
        engine = nil
        isListening = false
    }
}
