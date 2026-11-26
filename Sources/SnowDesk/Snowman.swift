import SpriteKit

/// Hold ⌥ Option and sweep the pointer through a drift to roll a snowball.
/// Let go of ⌥ to drop it (or fling it to throw a snowball that splats).
/// Stack three balls and the snowman gets a hat, a scarf and a little chime.
final class SnowmanSystem: SceneEffect {
    private final class Ball {
        let node: SKSpriteNode
        let radius: CGFloat
        var vel: CGVector
        let thrown: Bool
        init(node: SKSpriteNode, radius: CGFloat, vel: CGVector, thrown: Bool) {
            self.node = node; self.radius = radius; self.vel = vel; self.thrown = thrown
        }
    }

    private final class Stack {
        let container = SKNode()
        var radii: [CGFloat] = []
        var height: CGFloat = 0           // top of the stack above its base
        var decorated = false
        var perch: Perched?
    }

    private var rolling: SKSpriteNode?
    private var volume: CGFloat = 0
    private var falling: [Ball] = []
    private var stacks: [Stack] = []

    private func radius(for v: CGFloat) -> CGFloat { min(46, sqrt(v * Pile.colW / .pi) * 1.1) }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if scene.optionHeld && scene.cursorInside && scene.enabled {
            if rolling == nil {
                let n = SKSpriteNode(texture: Tex.ball)
                n.zPosition = 70
                n.alpha = 0
                scene.addChild(n)
                rolling = n
                volume = 0
            }
            if scene.cursorSpeed > 25 {
                let r = radius(for: volume)
                volume += scene.collectSnow(around: scene.cursor, radius: max(14, r * 0.9), depthBelowCursor: r)
            }
            let r = radius(for: volume)
            if let n = rolling {
                n.size = CGSize(width: r * 2, height: r * 2)
                n.position = scene.cursor
                n.zRotation -= scene.cursorVel.dx * dt / max(r, 4)
                n.alpha = volume > 2 ? 1 : 0
            }
        } else if let n = rolling {
            rolling = nil
            let r = radius(for: volume)
            if volume < 5 {
                n.removeFromParent()
            } else {
                let v = CGVector(dx: scene.cursorVel.dx * 0.8, dy: scene.cursorVel.dy * 0.8)
                falling.append(Ball(node: n, radius: r, vel: v, thrown: scene.cursorSpeed > 700))
            }
            volume = 0
        }

        var i = 0
        while i < falling.count {
            let b = falling[i]
            if step(b, dt: dt, scene: scene) { i += 1 } else { falling.remove(at: i) }
        }
        stacks.removeAll { $0.container.parent == nil }
        return true
    }

    // MARK: Test hooks (used by --demo)

    func testDrop(at p: CGPoint, radius r: CGFloat, vel: CGVector, thrown: Bool, in scene: SnowScene) {
        let n = SKSpriteNode(texture: Tex.ball, size: CGSize(width: r * 2, height: r * 2))
        n.position = p
        n.zPosition = 70
        scene.addChild(n)
        falling.append(Ball(node: n, radius: r, vel: vel, thrown: thrown))
    }

    var summary: String { "stacks=\(stacks.count) balls=\(stacks.map { $0.radii.count }) decorated=\(stacks.filter { $0.decorated }.count) falling=\(falling.count)" }

    /// Returns false when the ball is gone (landed, stacked or splatted).
    private func step(_ b: Ball, dt: CGFloat, scene: SnowScene) -> Bool {
        b.vel.dy -= 1300 * dt
        let p = b.node.position
        let np = CGPoint(x: p.x + b.vel.dx * dt, y: p.y + b.vel.dy * dt)
        b.node.zRotation -= b.vel.dx * dt / b.radius
        let impact = hypot(b.vel.dx, b.vel.dy)

        // Onto a stack?
        for st in stacks where !st.container.isHidden {
            let top = CGPoint(x: st.container.position.x, y: st.container.position.y + st.height)
            let topR = st.radii.last ?? 0
            if abs(np.x - top.x) < topR * 0.8 + b.radius * 0.3 && p.y - b.radius >= top.y - 3 && np.y - b.radius <= top.y {
                if b.thrown && impact > 650 { splat(b, scene: scene); return false }
                b.node.removeFromParent()
                addBall(b.radius, to: st, scene: scene)
                return false
            }
        }

        let s = scene.surface(under: np.x, atOrBelow: p.y - b.radius)
        if np.y - b.radius <= s.top {
            if b.thrown && impact > 650 { splat(b, scene: scene); return false }
            b.node.removeFromParent()
            let st = Stack()
            st.container.zPosition = 65
            scene.addChild(st.container)
            let perch = Perched(node: st.container, windowID: s.windowID, localX: np.x - s.ledgeX, yOffset: s.top - s.baseY)
            perch.onDislodge = { [weak self, weak st, weak scene] in
                guard let self, let st, let scene else { return }
                self.breakStack(st, scene: scene)
            }
            st.perch = perch
            scene.perch(perch)
            stacks.append(st)
            addBall(b.radius, to: st, scene: scene)
            return false
        }
        if np.y < -100 || np.x < -200 || np.x > scene.size.width + 200 {
            b.node.removeFromParent()
            return false
        }
        b.node.position = np
        return true
    }

    private func addBall(_ r: CGFloat, to st: Stack, scene: SnowScene) {
        let n = SKSpriteNode(texture: Tex.ball, size: CGSize(width: r * 2, height: r * 2))
        let sink = st.radii.isEmpty ? r * 0.12 : r * 0.28     // balls squash into each other a little
        n.position = CGPoint(x: 0, y: st.height - sink + r)
        n.zPosition = CGFloat(st.radii.count) * 0.1
        st.container.addChild(n)
        st.radii.append(r)
        st.height = st.height - sink + 2 * r
        if st.radii.count == 3 && !st.decorated { decorate(st) }
    }

    private func decorate(_ st: Stack) {
        st.decorated = true
        Sound.shared.play(.chime)
        let r1 = st.radii[1], r2 = st.radii[2]
        let midY = st.container.children[1].position.y
        let topY = st.container.children[2].position.y
        let z: CGFloat = 1
        func add(_ n: SKNode) { n.zPosition = z; st.container.addChild(n) }
        // Eyes, carrot, smile
        for ex in [-0.32, 0.32] {
            add(Shape.ellipse(CGRect(x: ex * r2 - r2 * 0.09, y: topY + r2 * 0.2, width: r2 * 0.18, height: r2 * 0.18), fill: rgb(0.1, 0.1, 0.12)))
        }
        add(Shape.poly([CGPoint(x: 0, y: topY + r2 * 0.08), CGPoint(x: 0, y: topY - r2 * 0.14), CGPoint(x: r2 * 0.8, y: topY - r2 * 0.05)],
                       fill: rgb(0.98, 0.5, 0.1)))
        for k in 0..<5 {
            let a = CGFloat.pi * (1.25 + 0.125 * CGFloat(k))
            add(Shape.ellipse(CGRect(x: cos(a) * r2 * 0.5 - 1.5, y: topY + sin(a) * r2 * 0.5 - 1.5, width: 3, height: 3), fill: rgb(0.1, 0.1, 0.12)))
        }
        // Hat
        add(Shape.rect(CGRect(x: -r2 * 0.85, y: topY + r2 * 0.72, width: r2 * 1.7, height: r2 * 0.16), radius: 1.5, fill: rgb(0.1, 0.1, 0.12)))
        add(Shape.rect(CGRect(x: -r2 * 0.55, y: topY + r2 * 0.86, width: r2 * 1.1, height: r2 * 0.95), radius: 2, fill: rgb(0.1, 0.1, 0.12)))
        add(Shape.rect(CGRect(x: -r2 * 0.55, y: topY + r2 * 0.9, width: r2 * 1.1, height: r2 * 0.2), fill: rgb(0.8, 0.12, 0.15)))
        // Scarf
        add(Shape.rect(CGRect(x: -r2 * 0.95, y: topY - r2 * 1.05, width: r2 * 1.9, height: r2 * 0.32), radius: r2 * 0.12, fill: rgb(0.85, 0.15, 0.18)))
        add(Shape.rect(CGRect(x: r2 * 0.3, y: topY - r2 * 1.7, width: r2 * 0.32, height: r2 * 0.75), radius: r2 * 0.1, fill: rgb(0.78, 0.12, 0.15)))
        // Buttons and stick arms
        for k in 0..<3 {
            add(Shape.ellipse(CGRect(x: -2.5, y: midY + r1 * (0.45 - CGFloat(k) * 0.4) - 2.5, width: 5, height: 5), fill: rgb(0.1, 0.1, 0.12)))
        }
        let brown = rgb(0.4, 0.25, 0.12)
        add(Shape.line([CGPoint(x: -r1 * 0.85, y: midY + r1 * 0.2), CGPoint(x: -r1 * 1.9, y: midY + r1 * 0.85)], color: brown, width: 2.5))
        add(Shape.line([CGPoint(x: -r1 * 1.6, y: midY + r1 * 0.68), CGPoint(x: -r1 * 1.75, y: midY + r1 * 1.05)], color: brown, width: 1.8))
        add(Shape.line([CGPoint(x: r1 * 0.85, y: midY + r1 * 0.2), CGPoint(x: r1 * 1.9, y: midY + r1 * 0.85)], color: brown, width: 2.5))
        add(Shape.line([CGPoint(x: r1 * 1.6, y: midY + r1 * 0.68), CGPoint(x: r1 * 1.85, y: midY + r1 * 0.6)], color: brown, width: 1.8))
        st.container.run(.sequence([.scale(to: 1.08, duration: 0.12), .scale(to: 1, duration: 0.18)]))
    }

    private func splat(_ b: Ball, scene: SnowScene) {
        Sound.shared.play(.splat, volume: 0.8)
        let p = b.node.position
        let n = Int(b.radius * 1.2)
        for _ in 0..<n {
            let a = CGFloat.random(in: 0...(2 * .pi))
            scene.spawnChunk(at: CGPoint(x: p.x + cos(a) * b.radius * 0.5, y: p.y + sin(a) * b.radius * 0.5),
                             vx: cos(a) * .random(in: 60...240) + b.vel.dx * 0.15, vy: -.random(in: 80...300))
        }
        b.node.removeFromParent()
    }

    private func breakStack(_ st: Stack, scene: SnowScene) {
        if let p = st.perch { scene.unperch(p) }
        let base = st.container.position
        for r in st.radii {
            for _ in 0..<Int(r) {
                scene.spawnChunk(at: CGPoint(x: base.x + .random(in: -r...r), y: base.y + .random(in: 0...st.height)),
                                 vx: .random(in: -120...120), vy: -.random(in: 0...150))
            }
        }
        st.container.removeFromParent()
    }
}
