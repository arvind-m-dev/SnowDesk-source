import SpriteKit

/// Bats: jittery, darting flight with fast irregular wingbeats. Now and then one hangs upside down
/// under a window edge (or a toolbar, row or button when Accessibility is allowed) and sways, until you come near.
final class BatsEffect: SceneEffect, Finishable {
    private enum Mode { case flying, roosting, hanging, leaving }
    private final class Bat {
        let node = SKNode()
        let body = SKNode()
        let left: SKNode, right: SKNode
        var p: CGPoint
        var v: CGVector
        var target: CGPoint
        var retarget: CGFloat = 0
        var phase = CGFloat.random(in: 0...6.28)
        let rate = CGFloat.random(in: 15...21)
        let speed = CGFloat.random(in: 150...250)
        var mode: Mode = .flying
        var ledge: Ledge?
        var perch: Perched?
        var roostAt: TimeInterval = 0
        var hangUntil: TimeInterval = 0
        let swayPhase = CGFloat.random(in: 0...6.28)

        init(at p: CGPoint, size: CGFloat) {
            self.p = p
            self.v = .zero
            self.target = p
            let ink = rgb(0.1, 0.07, 0.12)
            let membrane = rgb(0.2, 0.13, 0.2)
            func wing(_ side: CGFloat) -> SKNode {
                let n = SKNode()
                let pts: [CGPoint] = [(0, 2), (6, 7), (13, 10), (20, 8), (24, 3), (20, 0), (17, 2.5), (13, -1), (10, 1.5), (6, -1.5), (3, 0)]
                    .map { CGPoint(x: $0.0 * side, y: $0.1) }
                n.addChild(Shape.poly(pts, fill: membrane, stroke: ink, line: 0.8))
                for (a, b) in [((6.0, 7.0), (6.0, -1.5)), ((13.0, 10.0), (13.0, -1.0)), ((20.0, 8.0), (20.0, 0.0))] {
                    n.addChild(Shape.line([CGPoint(x: a.0 * side, y: a.1), CGPoint(x: b.0 * side, y: b.1)], color: ink, width: 0.7))
                }
                let holder = SKNode()
                holder.addChild(Bake.sprite(n, key: "bat-wing\(side)"))
                return holder
            }
            left = wing(-1); right = wing(1)
            body.addChild(left); body.addChild(right)
            let torso = SKNode()
            torso.addChild(Shape.ellipse(CGRect(x: -3.5, y: -5, width: 7, height: 10), fill: ink))
            torso.addChild(Shape.ellipse(CGRect(x: -3, y: 3, width: 6, height: 6), fill: ink))
            torso.addChild(Shape.poly([CGPoint(x: -3, y: 7), CGPoint(x: -2.4, y: 11), CGPoint(x: -0.6, y: 8)], fill: ink))
            torso.addChild(Shape.poly([CGPoint(x: 3, y: 7), CGPoint(x: 2.4, y: 11), CGPoint(x: 0.6, y: 8)], fill: ink))
            for ex in [CGFloat(-1.3), 1.3] { torso.addChild(Shape.ellipse(CGRect(x: ex - 0.7, y: 5.4, width: 1.4, height: 1.4), fill: rgb(1, 0.8, 0.25))) }
            layerInOrder(torso)
            body.addChild(Bake.sprite(torso, key: "bat-body"))
            layerInOrder(body)
            node.addChild(body)
            node.setScale(size)
        }

        func flap(_ dt: CGFloat) {
            phase += dt * rate * .random(in: 0.85...1.15)
            let a = sin(phase) * (0.7 + 0.25 * sin(phase * 0.37))
            left.zRotation = -a
            right.zRotation = a
            left.xScale = 1; right.xScale = 1
            left.yScale = 0.7 + 0.3 * abs(cos(phase)); right.yScale = left.yScale
        }

        func fold() {
            left.zRotation = -1.2; right.zRotation = 1.2
            left.xScale = 0.35; right.xScale = 0.35
            left.yScale = 1; right.yScale = 1
        }
    }

    private let root = SKNode()
    private var bats: [Bat] = []
    private var finishing = false
    var isFinishing: Bool { finishing }
    let population: Int
    private var nextSpawn: TimeInterval = 0

    init(scene: SnowScene, population: Int = 4) {
        self.population = population
        root.zPosition = 91
        scene.addChild(root)
    }

    func finish() {
        finishing = true
        for b in bats { leave(b, scene: root.scene as? SnowScene) }
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        guard dt > 0 else { return true }
        let w = scene.size.width, h = scene.size.height
        if !finishing && bats.count < population && t > nextSpawn {
            nextSpawn = t + .random(in: 1.5...6)
            let fromLeft = Bool.random()
            let b = Bat(at: CGPoint(x: fromLeft ? -30 : w + 30, y: .random(in: (h * 0.4)...(h * 0.9))), size: .random(in: 0.8...1.3))
            b.v = CGVector(dx: fromLeft ? 180 : -180, dy: 0)
            b.roostAt = t + .random(in: 6...22)
            root.addChild(b.node)
            bats.append(b)
        }
        bats = bats.filter { step($0, dt: dt, t: t, scene: scene, w: w, h: h) }
        if finishing && bats.isEmpty { root.removeFromParent(); return false }
        return true
    }

    private func step(_ b: Bat, dt: CGFloat, t: TimeInterval, scene: SnowScene, w: CGFloat, h: CGFloat) -> Bool {
        let near = scene.cursorInside && hypot(scene.cursor.x - b.node.position.x, scene.cursor.y - b.node.position.y) < 120
        switch b.mode {
        case .hanging:
            if near || t > b.hangUntil || b.node.isHidden || b.ledge.flatMap({ scene.point(of: $0) }) == nil {
                takeOff(b, scene: scene, t: t)
                return true
            }
            // Gentle sway, now and then a wing stretch.
            b.body.zRotation = sin(CGFloat(t) * 1.6 + b.swayPhase) * 0.12
            if Int.random(in: 0..<600) == 0 {
                b.left.run(.sequence([.scaleX(to: 1, duration: 0.15), .wait(forDuration: 0.3), .scaleX(to: 0.35, duration: 0.2)]))
            }
            return true
        case .roosting:
            guard let l = b.ledge, let pt = scene.point(of: l) else { b.mode = .flying; return true }
            let goal = CGPoint(x: pt.x, y: pt.y - 9)
            let d = CGVector(dx: goal.x - b.p.x, dy: goal.y - b.p.y)
            let dist = max(0.001, hypot(d.dx, d.dy))
            let sp = min(b.speed, max(50, dist * 2.5))
            b.v.dx += (d.dx / dist * sp - b.v.dx) * min(1, dt * 5)
            b.v.dy += (d.dy / dist * sp - b.v.dy) * min(1, dt * 5)
            b.p.x += b.v.dx * dt; b.p.y += b.v.dy * dt
            b.flap(dt)
            b.node.position = b.p
            if near { b.mode = .flying; b.roostAt = t + .random(in: 6...15) }
            if dist < 4 { hang(b, on: l, at: goal, scene: scene, t: t) }
            return true
        case .flying, .leaving:
            b.retarget -= dt
            if b.retarget <= 0 {
                b.retarget = .random(in: 0.2...0.8)
                if b.mode == .leaving {
                    b.target = CGPoint(x: b.p.x + (b.v.dx >= 0 ? 1 : -1) * .random(in: 200...400), y: b.p.y + .random(in: -40...160))
                } else {
                    // Erratic: jump to a new nearby aim point, pulled loosely toward the upper middle.
                    let cx = w * 0.5 + .random(in: -w * 0.4...w * 0.4), cy = h * .random(in: 0.35...0.85)
                    b.target = CGPoint(x: b.p.x + .random(in: -260...260) + (cx - b.p.x) * 0.3,
                                       y: b.p.y + .random(in: -160...160) + (cy - b.p.y) * 0.3)
                }
                if Int.random(in: 0..<5) == 0 { b.v.dx += .random(in: -220...220); b.v.dy += .random(in: -220...140) }   // sudden dart
            }
            if near {                                   // dodge the pointer
                let dx = b.p.x - scene.cursor.x, dy = b.p.y - scene.cursor.y, d = max(1, hypot(dx, dy))
                b.v.dx += dx / d * 900 * dt; b.v.dy += dy / d * 900 * dt
            }
            let d = CGVector(dx: b.target.x - b.p.x, dy: b.target.y - b.p.y)
            let dist = max(0.001, hypot(d.dx, d.dy))
            b.v.dx += (d.dx / dist * b.speed - b.v.dx) * min(1, dt * 4)
            b.v.dy += (d.dy / dist * b.speed - b.v.dy) * min(1, dt * 4)
            b.p.x += b.v.dx * dt; b.p.y += b.v.dy * dt + sin(b.phase) * 0.8
            b.flap(dt)
            b.node.position = b.p
            b.node.zRotation = max(-0.4, min(0.4, b.v.dx / 900))
            if b.mode == .leaving {
                if b.p.x < -60 || b.p.x > w + 60 || b.p.y > h + 60 || b.p.y < -60 { b.node.removeFromParent(); return false }
            } else if !finishing && t > b.roostAt, let l = scene.randomLedge(hang: true) {
                b.ledge = l
                b.mode = .roosting
            } else if b.p.x < -200 || b.p.x > w + 200 {
                b.target = CGPoint(x: w / 2, y: h * 0.6)
            }
            return true
        }
    }

    private func hang(_ b: Bat, on l: Ledge, at goal: CGPoint, scene: SnowScene, t: TimeInterval) {
        b.fold()
        b.node.zRotation = .pi                       // upside down, feet on the ledge
        b.node.position = goal
        let yOff: CGFloat
        if let wid = l.windowID, let w = scene.visibleWindows.first(where: { $0.id == wid }) { yOff = goal.y - w.rect.maxY } else { yOff = goal.y }
        let p = Perched(node: b.node, windowID: l.windowID, localX: l.localX, yOffset: yOff)
        p.draggable = false
        p.onDislodge = { [weak self, weak b, weak scene] in if let b, let scene { self?.takeOff(b, scene: scene, t: scene.now) } }
        scene.perch(p)
        b.perch = p
        b.mode = .hanging
        b.v = .zero
        b.hangUntil = t + .random(in: 8...30)
    }

    private func takeOff(_ b: Bat, scene: SnowScene, t: TimeInterval) {
        if let p = b.perch { scene.unperch(p) }
        b.perch = nil
        b.ledge = nil
        b.node.isHidden = false
        b.node.zRotation = 0
        b.body.zRotation = 0
        b.p = b.node.position
        b.v = CGVector(dx: .random(in: -200...200), dy: -.random(in: 60...160))    // drop, then fly
        b.retarget = 0
        b.roostAt = t + .random(in: 8...25)
        b.mode = Int.random(in: 0..<4) == 0 ? .leaving : .flying
    }

    private func leave(_ b: Bat, scene: SnowScene?) {
        if let p = b.perch { scene?.unperch(p) }
        b.perch = nil
        b.node.isHidden = false
        b.node.zRotation = 0
        b.p = b.node.position
        b.mode = .leaving
        b.retarget = 0
    }
}
