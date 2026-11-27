import SpriteKit

/// Ready-made snowmen that build themselves on the ground. Click one to knock it over.
enum SnowmanStyle: Int, CaseIterable {
    case classic, gentleman, lady, kid, family, santa, melting

    var title: String {
        switch self {
        case .classic: return "Classic (Carrot and Scarf)"
        case .gentleman: return "Gentleman (Top Hat)"
        case .lady: return "Snow Lady (Bow)"
        case .kid: return "Snow Kid (Beanie)"
        case .family: return "Snow Family"
        case .santa: return "Santa Snowman"
        case .melting: return "Melting Snowman"
        }
    }
}

final class SnowmanBuilds: SceneEffect {
    private final class Built {
        let root = SKNode()
        var perch: Perched!
        var width: CGFloat = 60
        var height: CGFloat = 120
        var melting = false
        var meltLeft: CGFloat = 0
        var puddle: SKShapeNode?
    }

    private var built: [Built] = []
    var count: Int { built.count }

    func build(_ style: SnowmanStyle, in scene: SnowScene, at x: CGFloat? = nil) {
        if built.count >= 8, let oldest = built.first { knock(oldest, scene: scene) }
        let b = Built()
        let gx = x ?? .random(in: 120...max(121, scene.size.width - 120))
        switch style {
        case .family:
            let a = makeSnowman(.classic, scale: 1), m = makeSnowman(.lady, scale: 0.86), k = makeSnowman(.kid, scale: 0.58)
            a.node.position.x = -46; m.node.position.x = 10; k.node.position.x = 56
            for (i, n) in [a, m, k].enumerated() { animateBuild(n.node, delay: Double(i) * 0.9); b.root.addChild(n.node) }
            b.width = 170; b.height = a.height
        default:
            let s = makeSnowman(style, scale: style == .kid ? 0.7 : 1)
            animateBuild(s.node, delay: 0)
            b.root.addChild(s.node)
            b.width = s.width; b.height = s.height
            if style == .melting {
                b.melting = true
                b.meltLeft = 70
                let p = Shape.ellipse(CGRect(x: -30, y: -4, width: 60, height: 8), fill: rgb(0.7, 0.85, 1, 0.5))
                p.zPosition = -1
                p.xScale = 0.4
                b.root.addChild(p)
                b.puddle = p
            }
        }
        b.root.zPosition = 60
        scene.addChild(b.root)
        let c = scene.ground.column(forLocalX: gx) ?? 0
        b.perch = Perched(node: b.root, windowID: nil, localX: gx, yOffset: scene.ground.height(at: c))
        b.perch.onDislodge = { [weak b, weak scene] in if let b, let scene { scene.dropToGround(b.perch) } }
        scene.perch(b.perch)
        built.append(b)
        Sound.shared.play(.chime, volume: 0.6)
    }

    func knockAll(in scene: SnowScene) { built.forEach { knock($0, scene: scene) } }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        for b in built {
            // Sit on top of the snow as it piles up or melts.
            if !b.perch.held, let h = scene.restOffset(for: b.perch) {
                b.perch.yOffset += (h - b.perch.yOffset) * min(1, dt * 3)
            }
            if b.melting {
                b.meltLeft -= dt
                let k = max(0.05, b.meltLeft / 70)
                b.root.children.first?.yScale = 0.35 + 0.65 * k
                b.root.children.first?.xScale = 1 + (1 - k) * 0.25
                b.puddle?.xScale = 0.4 + (1 - k) * 1.4
                if b.meltLeft <= 0 { remove(b, scene: scene) }
            }
        }
        return true
    }

    func click(at p: CGPoint, count: Int, in scene: SnowScene) -> Bool {
        for b in built.reversed() {
            let o = b.root.position
            if abs(p.x - o.x) < b.width / 2 && p.y > o.y - 4 && p.y < o.y + b.height {
                knock(b, scene: scene)
                return true
            }
        }
        return false
    }

    private func knock(_ b: Built, scene: SnowScene) {
        Sound.shared.play(.splat, volume: 0.7)
        let o = b.root.position
        for _ in 0..<Int(b.width * 0.9) {
            scene.spawnChunk(at: CGPoint(x: o.x + .random(in: -b.width / 2...b.width / 2), y: o.y + .random(in: 0...b.height)),
                             vx: .random(in: -160...160), vy: -.random(in: 0...200))
        }
        remove(b, scene: scene)
    }

    private func remove(_ b: Built, scene: SnowScene) {
        scene.unperch(b.perch)
        b.root.removeFromParent()
        built.removeAll { $0 === b }
    }

    /// Balls drop in one by one with a squash, then the accessories pop on.
    private func animateBuild(_ n: SKNode, delay: Double) {
        let balls = n.children.filter { $0.name == "ball" }
        let extras = n.children.filter { $0.name != "ball" }
        for (i, b) in balls.enumerated() {
            let final = b.position
            b.position.y += 140
            b.alpha = 0
            let d = delay + Double(i) * 0.35
            b.run(.sequence([.wait(forDuration: d), .group([.fadeIn(withDuration: 0.1), .moveTo(y: final.y, duration: 0.28)]),
                             .scaleX(to: 1.12, y: 0.86, duration: 0.07), .scale(to: 1, duration: 0.12)]))
        }
        for e in extras {
            e.alpha = 0
            e.run(.sequence([.wait(forDuration: delay + Double(balls.count) * 0.35 + .random(in: 0.1...0.5)), .fadeIn(withDuration: 0.25)]))
        }
    }

    // MARK: Drawing

    private func makeSnowman(_ style: SnowmanStyle, scale k: CGFloat) -> (node: SKNode, width: CGFloat, height: CGFloat) {
        let n = SKNode()
        let radii: [CGFloat] = (style == .kid ? [24, 18] : [26, 19.5, 14.5]).map { $0 * k }
        var y: CGFloat = 0
        var centers: [CGFloat] = []
        for (i, r) in radii.enumerated() {
            let sink = i == 0 ? r * 0.1 : r * 0.28
            let c = y - sink + r
            centers.append(c)
            y = c + r
            let ball = SKSpriteNode(texture: Tex.ball, size: CGSize(width: r * 2, height: r * 2))
            ball.name = "ball"
            ball.position = CGPoint(x: 0, y: c)
            ball.zPosition = CGFloat(i) * 0.1
            n.addChild(ball)
            // soft contact shadow under each upper ball
            if i > 0 {
                let sh = Shape.ellipse(CGRect(x: -r * 0.8, y: c - r * 1.02, width: r * 1.6, height: r * 0.35), fill: rgb(0.55, 0.62, 0.78, 0.35))
                sh.zPosition = CGFloat(i) * 0.1 - 0.01
                n.addChild(sh)
            }
        }
        let head = radii.last!, hy = centers.last!
        let body = radii.count > 2 ? radii[1] : radii[0], by = radii.count > 2 ? centers[1] : centers[0]
        let ink = rgb(0.1, 0.1, 0.12)
        func add(_ s: SKNode) { s.zPosition = 1 + CGFloat(n.children.count) * 0.001; n.addChild(s) }

        // Face
        for ex in [-0.32, 0.32] {
            add(Shape.ellipse(CGRect(x: ex * head - head * 0.1, y: hy + head * 0.18, width: head * 0.2, height: head * 0.2), fill: ink))
            add(Shape.ellipse(CGRect(x: ex * head - head * 0.03, y: hy + head * 0.28, width: head * 0.07, height: head * 0.07), fill: .white))
        }
        add(Shape.poly([CGPoint(x: 0, y: hy + head * 0.08), CGPoint(x: 0, y: hy - head * 0.14), CGPoint(x: head * (style == .lady ? 0.6 : 0.85), y: hy - head * 0.04)],
                       fill: rgb(0.98, 0.5, 0.1)))
        for i in 0..<5 {
            let a = CGFloat.pi * (1.25 + 0.125 * CGFloat(i))
            add(Shape.ellipse(CGRect(x: cos(a) * head * 0.5 - head * 0.07, y: hy + sin(a) * head * 0.5 - head * 0.07, width: head * 0.14, height: head * 0.14), fill: ink))
        }
        if style == .lady || style == .kid {
            for ex in [-0.55, 0.55] {
                add(Shape.ellipse(CGRect(x: ex * head - head * 0.13, y: hy - head * 0.2, width: head * 0.26, height: head * 0.14), fill: rgb(1, 0.55, 0.6, 0.6)))
            }
        }
        if style == .lady {
            for ex in [-0.32, 0.32] {
                add(Shape.line([CGPoint(x: ex * head - head * 0.08, y: hy + head * 0.4), CGPoint(x: ex * head - head * 0.16, y: hy + head * 0.5)], color: ink, width: 1))
                add(Shape.line([CGPoint(x: ex * head + head * 0.08, y: hy + head * 0.4), CGPoint(x: ex * head + head * 0.16, y: hy + head * 0.5)], color: ink, width: 1))
            }
        }

        // Buttons and arms
        for i in 0..<(radii.count > 2 ? 3 : 2) {
            let r = body * 0.12
            add(Shape.ellipse(CGRect(x: -r, y: by + body * (0.45 - CGFloat(i) * 0.4) - r, width: r * 2, height: r * 2), fill: ink))
        }
        let brown = rgb(0.4, 0.25, 0.12)
        for side in [CGFloat(-1), 1] {
            let up: CGFloat = style == .kid ? 1.1 : (side > 0 && style == .gentleman ? 0.2 : 0.85)
            add(Shape.line([CGPoint(x: side * body * 0.85, y: by + body * 0.2), CGPoint(x: side * body * 1.9, y: by + body * up)], color: brown, width: max(1.6, 2.5 * k)))
            add(Shape.line([CGPoint(x: side * body * 1.6, y: by + body * (0.2 + (up - 0.2) * 0.72)), CGPoint(x: side * body * 1.75, y: by + body * (up + 0.2))], color: brown, width: max(1.2, 1.8 * k)))
        }

        // Scarf
        let scarfColors: [SnowmanStyle: NSColor] = [.classic: rgb(0.85, 0.15, 0.18), .gentleman: rgb(0.2, 0.3, 0.6), .lady: rgb(0.95, 0.45, 0.65),
                                                    .kid: rgb(0.2, 0.65, 0.4), .santa: rgb(0.9, 0.15, 0.15), .melting: rgb(0.95, 0.6, 0.1)]
        let scarf = scarfColors[style] ?? rgb(0.85, 0.15, 0.18)
        add(Shape.rect(CGRect(x: -head * 0.95, y: hy - head * 1.05, width: head * 1.9, height: head * 0.32), radius: head * 0.12, fill: scarf))
        add(Shape.rect(CGRect(x: head * 0.3, y: hy - head * 1.7, width: head * 0.32, height: head * 0.75), radius: head * 0.1, fill: scarf.blended(withFraction: 0.12, of: .black)))
        for i in 0..<3 { add(Shape.rect(CGRect(x: -head * 0.8 + CGFloat(i) * head * 0.55, y: hy - head * 1.0, width: head * 0.12, height: head * 0.22), fill: rgb(1, 1, 1, 0.35))) }

        // Headwear
        var top = hy + head
        switch style {
        case .classic, .melting:
            add(Shape.rect(CGRect(x: -head * 0.85, y: hy + head * 0.72, width: head * 1.7, height: head * 0.16), radius: 1.5, fill: ink))
            add(Shape.rect(CGRect(x: -head * 0.55, y: hy + head * 0.86, width: head * 1.1, height: head * 0.8), radius: 2, fill: ink))
            add(Shape.rect(CGRect(x: -head * 0.55, y: hy + head * 0.9, width: head * 1.1, height: head * 0.18), fill: rgb(0.8, 0.12, 0.15)))
            top = hy + head * 1.66
        case .gentleman:
            add(Shape.rect(CGRect(x: -head * 0.95, y: hy + head * 0.72, width: head * 1.9, height: head * 0.15), radius: 1.5, fill: ink))
            add(Shape.rect(CGRect(x: -head * 0.6, y: hy + head * 0.85, width: head * 1.2, height: head * 1.4), radius: 2, fill: ink))
            add(Shape.rect(CGRect(x: -head * 0.6, y: hy + head * 0.9, width: head * 1.2, height: head * 0.2), fill: rgb(0.55, 0.45, 0.2)))
            add(Shape.ellipse(CGRect(x: head * 0.14, y: hy + head * 0.1, width: head * 0.38, height: head * 0.38), fill: nil, stroke: rgb(0.85, 0.7, 0.3), line: 1.2))
            top = hy + head * 2.25
        case .lady:
            let bow = rgb(0.95, 0.35, 0.55)
            add(Shape.poly([CGPoint(x: head * 0.2, y: hy + head * 0.85), CGPoint(x: -head * 0.25, y: hy + head * 1.2), CGPoint(x: -head * 0.2, y: hy + head * 0.6)], fill: bow))
            add(Shape.poly([CGPoint(x: head * 0.2, y: hy + head * 0.85), CGPoint(x: head * 0.65, y: hy + head * 1.2), CGPoint(x: head * 0.6, y: hy + head * 0.6)], fill: bow))
            add(Shape.ellipse(CGRect(x: head * 0.08, y: hy + head * 0.73, width: head * 0.24, height: head * 0.24), fill: bow.blended(withFraction: 0.2, of: .black)))
            top = hy + head * 1.25
        case .kid:
            let cap = [rgb(0.2, 0.5, 0.9), rgb(0.95, 0.55, 0.1), rgb(0.6, 0.3, 0.8)].randomElement()!
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 0, y: hy + head * 0.45), radius: head * 0.95, startAngle: 0.1, endAngle: .pi - 0.1, clockwise: false)
            p.closeSubpath()
            add(Shape.node(p, fill: cap))
            add(Shape.rect(CGRect(x: -head * 0.98, y: hy + head * 0.5, width: head * 1.96, height: head * 0.25), radius: head * 0.1, fill: cap.blended(withFraction: 0.3, of: .white)))
            add(Shape.ellipse(CGRect(x: -head * 0.22, y: hy + head * 1.3, width: head * 0.44, height: head * 0.44), fill: .white))
            top = hy + head * 1.75
        case .santa:
            add(Shape.poly([CGPoint(x: -head * 0.9, y: hy + head * 0.7), CGPoint(x: head * 0.9, y: hy + head * 0.7), CGPoint(x: head * 0.9, y: hy + head * 1.75)], fill: rgb(0.85, 0.1, 0.12)))
            add(Shape.rect(CGRect(x: -head * 0.98, y: hy + head * 0.6, width: head * 1.96, height: head * 0.28), radius: head * 0.12, fill: .white))
            add(Shape.ellipse(CGRect(x: head * 0.7, y: hy + head * 1.6, width: head * 0.4, height: head * 0.4), fill: .white))
            top = hy + head * 2
        case .family:
            break
        }
        // Bake the vector parts: the face, hat, scarf and arms become one image, each contact shadow its own.
        let extras = SKNode()
        for c in n.children where c.name != "ball" && c.zPosition >= 1 { c.removeFromParent(); extras.addChild(c) }
        let face = Bake.sprite(extras)
        face.zPosition = 1
        n.addChild(face)
        for c in n.children where c is SKShapeNode {
            let z = c.zPosition
            c.removeFromParent()
            let sh = Bake.sprite(c)
            sh.zPosition = z
            n.addChild(sh)
        }
        return (n, body * 4, top)
    }
}
