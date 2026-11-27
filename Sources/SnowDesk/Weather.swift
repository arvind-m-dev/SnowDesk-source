import SpriteKit

enum WeatherKind: String, CaseIterable {
    case snow, rain, storm, leaves, petals, fireflies, meteors, mist, cloud, clear

    var title: String {
        switch self {
        case .snow: return "Snow"
        case .rain: return "Rain"
        case .storm: return "Storm"
        case .leaves: return "Autumn Leaves"
        case .petals: return "Blossom Petals"
        case .fireflies: return "Fireflies"
        case .meteors: return "Shooting Stars"
        case .mist: return "Mist"
        case .cloud: return "Clouds"
        case .clear: return "Clear Sky"
        }
    }
}

/// Every weather other than snow (snow lives in SnowScene because it piles up).
final class AmbientWeather: SceneEffect {
    private struct P {
        let node: SKSpriteNode
        var vx: CGFloat
        var vy: CGFloat          // upward positive here
        var spin: CGFloat
        var phase: CGFloat
        var life: CGFloat        // seconds left (droplets, meteors, resting leaves)
        var resting = false
        var isDroplet = false
    }

    let kind: WeatherKind
    private let root = SKNode()
    private var ps: [P] = []
    private var finishing = false
    private var fade: CGFloat = 0
    private var nextMeteor: TimeInterval = 0
    private var nextLightning: TimeInterval = 0
    private var flash: SKSpriteNode?

    init(kind: WeatherKind, scene: SnowScene) {
        self.kind = kind
        root.zPosition = kind == .cloud || kind == .mist ? 5 : 100
        root.alpha = 0
        scene.addChild(root)
        let w = scene.size.width, h = scene.size.height
        switch kind {
        case .mist:
            for _ in 0..<7 {         // few, large, faint puffs: big transparent sprites are costly to draw
                let s = glowSprite(.white, size: .random(in: 480...860), alpha: .random(in: 0.07...0.13))
                s.blendMode = .alpha
                s.yScale = 0.45
                s.position = CGPoint(x: .random(in: 0...w), y: .random(in: 0...(h * 0.45)))
                root.addChild(s)
                ps.append(P(node: s, vx: .random(in: 6...20), vy: 0, spin: 0, phase: .random(in: 0...6), life: 0))
            }
        case .cloud:
            for _ in 0..<8 {
                let width = CGFloat.random(in: 500...950)
                let s = SKSpriteNode(texture: Tex.cloud, size: CGSize(width: width, height: width * 0.43))
                s.alpha = .random(in: 0.35...0.6)
                s.position = CGPoint(x: .random(in: -200...(w + 200)), y: .random(in: (h * 0.62)...(h * 0.95)))
                root.addChild(s)
                ps.append(P(node: s, vx: .random(in: 5...16), vy: 0, spin: 0, phase: 0, life: 0))
            }
        case .storm:
            let f = SKSpriteNode(color: .white, size: scene.size)
            f.anchorPoint = .zero
            f.alpha = 0
            f.zPosition = 10
            root.addChild(f)
            flash = f
        default:
            break
        }
    }

    func finish() { finishing = true }

    private func target(_ scene: SnowScene) -> Int {
        let k = Settings.shared.intensity.factor
        switch kind {
        case .rain: return Int(320 * k)
        case .storm: return Int(650 * k)
        case .leaves: return Int(48 * k)
        case .petals: return Int(70 * k)
        case .fireflies: return Int(34 * k)
        default: return 0
        }
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        fade = finishing ? max(0, fade - dt * 0.7) : min(1, fade + dt * 0.5)
        root.alpha = fade
        if finishing && fade <= 0 {
            root.removeFromParent()
            return false
        }
        let w = scene.size.width, h = scene.size.height
        let tf = CGFloat(t)

        // Top up falling things.
        let want = finishing ? 0 : target(scene)
        let fallers = ps.filter { !$0.isDroplet }.count
        if fallers < want {
            for _ in 0..<min(want - fallers, 25) { spawn(in: scene, initial: t < 3 || fade < 0.5) }
        }

        // Occasional events.
        if kind == .meteors && !finishing && t > nextMeteor {
            nextMeteor = t + .random(in: 1.2...4.5)
            spawnMeteor(scene)
        }
        if kind == .storm && !finishing {
            if nextLightning == 0 { nextLightning = t + .random(in: 3...7) }
            if t > nextLightning {
                nextLightning = t + .random(in: 7...18)
                flash?.run(.sequence([.fadeAlpha(to: 0.55, duration: 0.05), .fadeAlpha(to: 0.1, duration: 0.08),
                                      .fadeAlpha(to: 0.4, duration: 0.05), .fadeAlpha(to: 0, duration: 0.5)]))
                DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 0.4...1.6)) { Sound.shared.play(.thunder, volume: 0.8) }
            }
        }

        let wind: CGFloat = kind == .storm ? -160 - sin(tf * 0.3) * 80 : -40 - sin(tf * 0.2) * 25
        var i = 0
        while i < ps.count {
            var p = ps[i]
            let pos = p.node.position
            var remove = false
            switch kind {
            case .rain, .storm:
                if p.isDroplet {
                    p.vy -= 900 * dt
                    p.life -= dt
                    p.node.position = CGPoint(x: pos.x + p.vx * dt, y: pos.y + p.vy * dt)
                    p.node.alpha = max(0, p.life * 2)
                    remove = p.life <= 0
                } else {
                    let nx = pos.x + (p.vx + wind) * dt
                    let ny = pos.y + p.vy * dt
                    let s = scene.surface(under: nx, atOrBelow: pos.y)
                    // Drops fall in front of windows; some hit a ledge they pass, the ground stops them all.
                    if ny <= s.top && (s.windowID == nil || Int.random(in: 0..<10) < 3) {
                        if Int.random(in: 0..<3) == 0 { splash(at: CGPoint(x: nx, y: s.top), ripple: s.windowID == nil) }
                        if finishing || ps.count > want * 2 { remove = true } else { respawnTop(&p, w: w, h: h) }
                    } else if ny < -20 {
                        if finishing { remove = true } else { respawnTop(&p, w: w, h: h) }
                    } else {
                        p.node.position = CGPoint(x: nx, y: ny)
                        p.node.zRotation = atan2(p.vy, p.vx + wind) + .pi / 2
                    }
                }
            case .leaves, .petals:
                if p.resting {
                    p.life -= dt
                    p.node.alpha = min(1, p.life)
                    if p.life <= 0 {
                        if finishing { remove = true } else { p.resting = false; respawnTop(&p, w: w, h: h) }
                    }
                } else {
                    var vx = p.vx + wind * 0.6 + sin(tf * 1.7 + p.phase) * (kind == .leaves ? 55 : 35)
                    if scene.cursorInside {
                        let dx = pos.x - scene.cursor.x, dy = pos.y - scene.cursor.y
                        let d = hypot(dx, dy)
                        if d < 120 { vx += scene.cursorVel.dx * (1 - d / 120) * 0.8; p.vy += scene.cursorVel.dy * (1 - d / 120) * dt * 3 }
                    }
                    p.vy += (-(kind == .leaves ? 55 : 40) - p.vy) * dt * 1.5
                    let nx = pos.x + vx * dt
                    let ny = pos.y + p.vy * dt + sin(tf * 2.3 + p.phase) * 0.6
                    p.node.zRotation += p.spin * dt
                    p.node.xScale = cos(tf * 2.1 + p.phase)
                    let s = scene.surface(under: nx, atOrBelow: pos.y)
                    if ny <= s.top + 2 && pos.y > s.top + 2 && (s.windowID == nil || Int.random(in: 0..<10) < 3) {
                        p.resting = true
                        p.life = .random(in: 4...9)
                        p.node.position = CGPoint(x: nx, y: s.top + 3)
                        p.node.xScale = 1
                    } else if ny < -30 || nx < -80 {
                        if finishing { remove = true } else { respawnTop(&p, w: w, h: h) }
                    } else {
                        p.node.position = CGPoint(x: nx, y: ny)
                    }
                }
            case .fireflies:
                p.vx += .random(in: -60...60) * dt
                p.vy += .random(in: -60...60) * dt
                if scene.cursorInside {
                    let dx = pos.x - scene.cursor.x, dy = pos.y - scene.cursor.y
                    let d = max(1, hypot(dx, dy))
                    if d < 140 { p.vx += dx / d * 90 * dt; p.vy += dy / d * 90 * dt }
                }
                if pos.y > h * 0.7 { p.vy -= 20 * dt }
                if pos.y < 20 { p.vy += 20 * dt }
                if pos.x < 0 { p.vx += 20 * dt }
                if pos.x > w { p.vx -= 20 * dt }
                let sp = hypot(p.vx, p.vy)
                if sp > 40 { p.vx *= 40 / sp; p.vy *= 40 / sp }
                p.node.position = CGPoint(x: pos.x + p.vx * dt, y: pos.y + p.vy * dt)
                let pulse = max(0, sin(tf * (0.8 + p.spin) + p.phase))
                p.node.alpha = 0.1 + 0.9 * pulse * pulse * pulse
                if finishing { p.node.alpha *= fade }
            case .meteors:
                p.life -= dt
                p.node.position = CGPoint(x: pos.x + p.vx * dt, y: pos.y + p.vy * dt)
                p.node.alpha = max(0, min(1, p.life * 1.5))
                remove = p.life <= 0
            case .mist:
                p.node.position.x += p.vx * dt
                p.node.position.y = pos.y + sin(tf * 0.1 + p.phase) * 0.05
                if p.node.position.x - p.node.size.width / 2 > w { p.node.position.x = -p.node.size.width / 2 }
            case .cloud:
                p.node.position.x += p.vx * dt
                if p.node.position.x - p.node.size.width / 2 > w { p.node.position.x = -p.node.size.width / 2 }
            case .snow, .clear:
                break
            }
            if remove {
                p.node.removeFromParent()
                ps.swapAt(i, ps.count - 1)
                ps.removeLast()
                continue
            }
            ps[i] = p
            i += 1
        }
        return true
    }

    private func respawnTop(_ p: inout P, w: CGFloat, h: CGFloat) {
        p.node.position = CGPoint(x: .random(in: -50...(w + 250)), y: h + .random(in: 10...80))
        p.node.alpha = kind == .rain || kind == .storm ? p.node.alpha : 1
        switch kind {
        case .rain, .storm: p.vy = -.random(in: 750...1050)
        default: p.vy = -.random(in: 30...60)
        }
    }

    private func spawn(in scene: SnowScene, initial: Bool) {
        let w = scene.size.width, h = scene.size.height
        let y = initial ? CGFloat.random(in: 0...h) : h + .random(in: 10...80)
        let x = CGFloat.random(in: -50...(w + 250))
        switch kind {
        case .rain, .storm:
            let len = CGFloat.random(in: 14...26)
            let s = SKSpriteNode(texture: Tex.streak, size: CGSize(width: 1.4, height: len))
            s.color = rgb(0.8, 0.88, 1)
            s.colorBlendFactor = 1
            s.alpha = .random(in: 0.25...0.55)
            s.position = CGPoint(x: x, y: y)
            root.addChild(s)
            ps.append(P(node: s, vx: .random(in: -10...10), vy: -.random(in: 750...1050), spin: 0, phase: 0, life: 0))
        case .leaves, .petals:
            let leaf = kind == .leaves
            let size = leaf ? CGFloat.random(in: 20...32) : CGFloat.random(in: 9...15)
            let s = SKSpriteNode(texture: leaf ? Tex.leaves.randomElement()! : Tex.petal,
                                 size: CGSize(width: size, height: size * (leaf ? 1 : 1.3)))
            s.position = CGPoint(x: x, y: y)
            s.zRotation = .random(in: 0...(2 * .pi))
            root.addChild(s)
            ps.append(P(node: s, vx: .random(in: -20...20), vy: -.random(in: 30...60), spin: .random(in: -3...3),
                        phase: .random(in: 0...6.28), life: 0))
        case .fireflies:
            let s = glowSprite(rgb(0.9, 1, 0.45), size: .random(in: 16...28))
            s.position = CGPoint(x: .random(in: 0...w), y: .random(in: 20...(h * 0.65)))
            root.addChild(s)
            ps.append(P(node: s, vx: .random(in: -20...20), vy: .random(in: -20...20), spin: .random(in: 0...1.5),
                        phase: .random(in: 0...6.28), life: 0))
        default:
            break
        }
    }

    private var ripples = 0

    private func splash(at p: CGPoint, ripple: Bool) {
        // A ring spreading on the wet ground (or the river).
        if ripple && ripples < 45 && Int.random(in: 0..<2) == 0 {
            ripples += 1
            let w = CGFloat.random(in: 5...8)
            let r = Shape.ellipse(CGRect(x: -w / 2, y: -w * 0.14, width: w, height: w * 0.28), fill: nil,
                                  stroke: rgb(0.85, 0.92, 1, 0.7), line: 0.8)
            r.position = CGPoint(x: p.x, y: max(2, p.y))
            root.addChild(r)
            let d = Double.random(in: 0.5...0.8)
            r.run(.sequence([.group([.scale(to: .random(in: 3...5), duration: d), .fadeOut(withDuration: d)]),
                             .run { [weak self] in self?.ripples -= 1 }, .removeFromParent()]))
        }
        for _ in 0..<(kind == .storm ? 3 : 2) {
            let s = SKSpriteNode(texture: Tex.glow, size: CGSize(width: 3, height: 3))
            s.color = rgb(0.85, 0.92, 1)
            s.colorBlendFactor = 1
            s.position = p
            root.addChild(s)
            ps.append(P(node: s, vx: .random(in: -70...70), vy: .random(in: 60...150), spin: 0, phase: 0, life: 0.35, isDroplet: true))
        }
    }

    private func spawnMeteor(_ scene: SnowScene) {
        let w = scene.size.width, h = scene.size.height
        let angle = CGFloat.random(in: 0.25...0.6)
        let dir: CGFloat = Bool.random() ? 1 : -1
        let speed = CGFloat.random(in: 700...1100)
        let len = CGFloat.random(in: 120...220)
        let node = SKSpriteNode(texture: Tex.streak, size: CGSize(width: 2.2, height: len))
        node.color = rgb(0.85, 0.92, 1)
        node.colorBlendFactor = 1
        node.blendMode = .add
        let vx = cos(angle) * speed * dir, vy = -sin(angle) * speed
        node.zRotation = atan2(vy, vx) + .pi / 2
        let head = glowSprite(.white, size: 10)
        head.position = CGPoint(x: 0, y: -len / 2)
        node.addChild(head)
        node.position = CGPoint(x: .random(in: (w * 0.1)...(w * 0.9)), y: .random(in: (h * 0.6)...(h * 0.95)))
        root.addChild(node)
        ps.append(P(node: node, vx: vx, vy: vy, spin: 0, phase: 0, life: .random(in: 0.6...1.1)))
    }
}
