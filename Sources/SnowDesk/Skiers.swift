import SpriteKit

/// Skiers and sledders that ride across the snowy ground and along window tops, jumping off the ends.
final class RidersEffect: SceneEffect, Finishable {
    enum Kind { case skier, sledder }

    private final class Rider {
        let kind: Kind
        let node = SKNode()
        let figure = SKNode()
        var poles: [SKNode] = []
        var scarf: SKNode?
        var pos: CGPoint
        var vx: CGFloat
        var vy: CGFloat = 0
        var airborne = false
        var lastTop: CGFloat
        var phase: CGFloat = 0
        init(kind: Kind, pos: CGPoint, vx: CGFloat) {
            self.kind = kind
            self.pos = pos
            self.vx = vx
            self.lastTop = pos.y
            node.addChild(figure)
        }
    }

    var skiers: Bool
    var sledders: Bool
    private let root = SKNode()
    private var riders: [Rider] = []
    private var next: TimeInterval = 0
    private var finishing = false
    var isFinishing: Bool { finishing }

    init(skiers: Bool, sledders: Bool, scene: SnowScene) {
        self.skiers = skiers
        self.sledders = sledders
        root.zPosition = 95
        scene.addChild(root)
    }

    func finish() { finishing = true }

    /// Send one right now (from the menu).
    func send(_ kind: Kind, scene: SnowScene) { spawn(kind, scene: scene) }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if !finishing && (skiers || sledders) {
            if next == 0 { next = t + .random(in: 3...8) }
            if t > next {
                next = t + .random(in: 14...35)
                let kinds = (skiers ? [Kind.skier, .skier] : []) + (sledders ? [Kind.sledder] : [])
                if riders.count < 4, let k = kinds.randomElement() { spawn(k, scene: scene) }
            }
        }
        riders = riders.filter { step($0, dt: dt, scene: scene) }
        if finishing && riders.isEmpty { root.removeFromParent(); return false }
        return true
    }

    private func spawn(_ kind: Kind, scene: SnowScene) {
        let dir: CGFloat = Bool.random() ? 1 : -1
        var start = CGPoint(x: dir > 0 ? -30 : scene.size.width + 30, y: 0)
        // Half the time, start on top of a window so it can ski off the end.
        let ledges = scene.visibleWindows.filter {
            $0.rect.width > 240 && $0.rect.maxY < scene.size.height - 60 && $0.rect.minX >= 0 && $0.rect.maxX <= scene.size.width
        }
        if Bool.random(), let w = ledges.randomElement() {
            start = CGPoint(x: dir > 0 ? w.rect.minX + 12 : w.rect.maxX - 12, y: w.rect.maxY + 40)
        } else {
            start.y = scene.surface(under: max(0, min(start.x, scene.size.width - 1)), atOrBelow: scene.size.height).top
        }
        let speed: CGFloat = kind == .skier ? .random(in: 120...190) : .random(in: 95...150)
        let r = Rider(kind: kind, pos: start, vx: dir * speed)
        r.airborne = true
        if kind == .skier { buildSkier(r) } else { buildSledder(r) }
        r.node.xScale = dir
        r.node.position = start
        r.node.alpha = 0
        r.node.run(.fadeIn(withDuration: 0.3))
        root.addChild(r.node)
        riders.append(r)
    }

    private func step(_ r: Rider, dt: CGFloat, scene: SnowScene) -> Bool {
        guard dt > 0 else { return true }
        r.phase += dt
        let nx = r.pos.x + r.vx * dt
        let clampedX = min(max(nx, 0), scene.size.width - 1)
        let s = scene.surface(under: clampedX, atOrBelow: r.pos.y + 3)
        if r.airborne {
            r.vy -= 950 * dt
            var ny = r.pos.y + r.vy * dt
            if ny <= s.top && r.vy <= 0 {
                ny = s.top
                r.airborne = false
                if r.vy < -250 { puff(at: CGPoint(x: nx, y: ny), n: 10, scene: scene) }
                r.vy = 0
            }
            r.pos = CGPoint(x: nx, y: ny)
            r.figure.zRotation += ((r.vy > 0 ? 0.25 : -0.15) - r.figure.zRotation) * min(1, dt * 4)
        } else if s.top < r.pos.y - 5 {
            // Ran off a ledge: a little hop, then fly.
            r.airborne = true
            r.vy = r.kind == .skier ? 170 : 90
            r.pos = CGPoint(x: nx, y: r.pos.y)
            Sound.shared.play(.pop, volume: 0.25)
        } else {
            // Ride the surface, tilting with the slope.
            let ahead = scene.surface(under: min(max(nx + 6 * (r.vx > 0 ? 1 : -1), 0), scene.size.width - 1), atOrBelow: s.top + 4).top
            let slope = atan2(ahead - s.top, 6)     // nose up going uphill (the node is mirrored when heading left)
            r.figure.zRotation += (max(-0.5, min(0.5, slope)) - r.figure.zRotation) * min(1, dt * 8)
            r.pos = CGPoint(x: nx, y: s.top)
            if Int.random(in: 0..<4) == 0 && s.top - s.baseY > 1.5 {
                scene.spawnChunk(at: CGPoint(x: nx - r.vx * 0.06, y: s.top + 2), vx: -r.vx * .random(in: 0.2...0.5), vy: -.random(in: 60...160))
            }
        }
        r.node.position = r.pos
        // Pole push and flapping scarf
        for (i, p) in r.poles.enumerated() { p.zRotation = 0.35 + sin(r.phase * 6 + CGFloat(i) * 0.6) * 0.3 }
        if let sc = r.scarf { sc.zRotation = sin(r.phase * 9) * 0.15 }
        let out = r.pos.x < -60 || r.pos.x > scene.size.width + 60 || r.pos.y < -40
        if out { r.node.removeFromParent() }
        return !out
    }

    private func puff(at p: CGPoint, n: Int, scene: SnowScene) {
        for _ in 0..<n { scene.spawnChunk(at: p, vx: .random(in: -120...120), vy: -.random(in: 80...220)) }
    }

    /// Bakes the rider's vector shapes (everything but the swinging poles and scarf) into one image.
    private func bake(_ r: Rider) {
        let f = r.figure
        let moving: [SKNode] = r.poles + [r.scarf].compactMap { $0 }
        for p in r.poles {
            for c in p.children where c is SKShapeNode { c.removeFromParent(); p.addChild(Bake.sprite(c, key: "ski-pole")) }
        }
        let still = SKNode()
        for c in f.children where !moving.contains(c) { c.removeFromParent(); still.addChild(c) }
        let baked = Bake.sprite(still)
        baked.zPosition = 0.5
        f.addChild(baked)
    }

    // MARK: Drawings (facing right, feet at y = 0)

    private static let jackets = [rgb(0.85, 0.15, 0.2), rgb(0.15, 0.45, 0.85), rgb(0.1, 0.65, 0.45), rgb(0.95, 0.6, 0.1), rgb(0.55, 0.25, 0.75)]

    private func buildSkier(_ r: Rider) {
        let f = r.figure
        let jacket = Self.jackets.randomElement()!
        let pants = rgb(0.15, 0.17, 0.25)
        let skin = [rgb(0.98, 0.82, 0.68), rgb(0.85, 0.62, 0.45), rgb(0.55, 0.38, 0.25)].randomElement()!
        let poleNode = SKNode()
        poleNode.position = CGPoint(x: 6, y: 20)
        poleNode.addChild(Shape.line([.zero, CGPoint(x: -4, y: -22)], color: rgb(0.7, 0.7, 0.75), width: 1.3))
        f.addChild(poleNode)
        r.poles = [poleNode]
        // skis with upturned tips
        let ski = CGMutablePath()
        ski.move(to: CGPoint(x: -16, y: 0.5)); ski.addLine(to: CGPoint(x: 15, y: 0.5))
        ski.addQuadCurve(to: CGPoint(x: 20, y: 4), control: CGPoint(x: 19, y: 0.5))
        let sk = Shape.node(ski, fill: nil, stroke: rgb(0.2, 0.2, 0.25), line: 2.2)
        sk.lineCap = .round
        f.addChild(sk)
        // legs (bent), body leaning forward
        f.addChild(Shape.line([CGPoint(x: -1, y: 2), CGPoint(x: 4, y: 9), CGPoint(x: -1, y: 16)], color: pants, width: 4.2))
        f.addChild(Shape.line([CGPoint(x: 3, y: 2), CGPoint(x: 8, y: 9), CGPoint(x: 2, y: 16)], color: pants.blended(withFraction: 0.2, of: .black)!, width: 4.2))
        let torso = Shape.rect(CGRect(x: -4, y: 14, width: 9, height: 13), radius: 3, fill: jacket)
        torso.zRotation = -0.35
        f.addChild(torso)
        f.addChild(Shape.line([CGPoint(x: 3, y: 24), CGPoint(x: 8, y: 19), CGPoint(x: 7, y: 20)], color: jacket.blended(withFraction: 0.15, of: .black)!, width: 3))
        f.addChild(Shape.ellipse(CGRect(x: 3, y: 27, width: 8, height: 8), fill: skin))
        f.addChild(Shape.rect(CGRect(x: 6, y: 30, width: 5.5, height: 2.4), radius: 1.2, fill: rgb(0.95, 0.65, 0.1)))        // goggles
        f.addChild(Shape.poly([CGPoint(x: 2.5, y: 32), CGPoint(x: 11.5, y: 32), CGPoint(x: 6, y: 38)], fill: jacket.blended(withFraction: 0.3, of: .white)!))
        f.addChild(Shape.ellipse(CGRect(x: 4, y: 36.5, width: 4, height: 4), fill: .white))                                    // pompom
        layerInOrder(f)
        bake(r)
    }

    private func buildSledder(_ r: Rider) {
        let f = r.figure
        let coat = Self.jackets.randomElement()!
        let skin = [rgb(0.98, 0.82, 0.68), rgb(0.85, 0.62, 0.45), rgb(0.55, 0.38, 0.25)].randomElement()!
        let wood = rgb(0.6, 0.36, 0.18)
        // runners
        let run = CGMutablePath()
        run.move(to: CGPoint(x: -14, y: 1)); run.addLine(to: CGPoint(x: 12, y: 1))
        run.addQuadCurve(to: CGPoint(x: 15, y: 8), control: CGPoint(x: 19, y: 1))
        let rn = Shape.node(run, fill: nil, stroke: rgb(0.3, 0.3, 0.35), line: 1.8)
        rn.lineCap = .round
        f.addChild(rn)
        f.addChild(Shape.rect(CGRect(x: -13, y: 4, width: 26, height: 3.5), radius: 1.2, fill: wood))
        for x in [CGFloat(-9), 7] { f.addChild(Shape.line([CGPoint(x: x, y: 1), CGPoint(x: x, y: 4)], color: wood, width: 1.5)) }
        // kid sitting: legs forward, body upright
        f.addChild(Shape.line([CGPoint(x: -4, y: 9), CGPoint(x: 9, y: 9)], color: rgb(0.2, 0.2, 0.3), width: 4.5))
        f.addChild(Shape.rect(CGRect(x: -8, y: 7, width: 9, height: 13), radius: 3, fill: coat))
        f.addChild(Shape.ellipse(CGRect(x: -7.5, y: 19, width: 8.5, height: 8.5), fill: skin))
        f.addChild(Shape.ellipse(CGRect(x: -2.2, y: 23, width: 1.5, height: 1.5), fill: rgb(0.1, 0.1, 0.1)))
        f.addChild(Shape.rect(CGRect(x: -8.5, y: 24, width: 10, height: 5), radius: 2.5, fill: coat.blended(withFraction: 0.35, of: .white)!))
        let scarfColor = Self.jackets.randomElement()!
        f.addChild(Shape.rect(CGRect(x: -8, y: 18, width: 9, height: 2.6), radius: 1, fill: scarfColor))
        let tail = SKNode()
        tail.addChild(Bake.sprite(Shape.poly([CGPoint(x: -7, y: 19.5), CGPoint(x: -17, y: 21), CGPoint(x: -16, y: 18)], fill: scarfColor)))
        f.addChild(tail)
        r.scarf = tail
        // arms holding the rope
        f.addChild(Shape.line([CGPoint(x: -2, y: 15), CGPoint(x: 8, y: 11)], color: coat.blended(withFraction: 0.15, of: .black)!, width: 3))
        f.addChild(Shape.line([CGPoint(x: 8, y: 11), CGPoint(x: 14, y: 7)], color: rgb(0.85, 0.75, 0.5), width: 0.8))
        layerInOrder(f)
        bake(r)
    }
}
