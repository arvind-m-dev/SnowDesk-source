import SpriteKit

/// Decorations and animations for a holiday or festival.
final class EventEffect: SceneEffect, Finishable {
    let kind: EventKind
    private let root = SKNode()
    private var finishing = false
    var isFinishing: Bool { finishing }
    private var props: [Perched] = []

    private struct Spark { let node: SKSpriteNode; var v: CGVector; var life: CGFloat; let total: CGFloat; let drag: CGFloat; let gravity: CGFloat; var crackle = false }
    private var sparks: [Spark] = []
    private struct Rocket { let node: SKSpriteNode; var v: CGVector; var fuse: CGFloat; let color: [NSColor]; var small = false }
    private let rocketGravity: CGFloat = 420
    private var rockets: [Rocket] = []
    private final class Flier { let node: SKNode; var v: CGVector; let phase: CGFloat; var life: CGFloat; let parts: [SKNode]
        init(node: SKNode, v: CGVector, life: CGFloat, parts: [SKNode] = []) { self.node = node; self.v = v; self.life = life; self.parts = parts; phase = .random(in: 0...6.28) } }
    private var fliers: [Flier] = []      // bats, ghosts, hearts, bunnies
    private var nextBurst: TimeInterval = 0
    private var nextFlier: TimeInterval = 0
    private var flickers: [SKNode] = []
    private var bats: BatsEffect?

    init(kind: EventKind, scene: SnowScene) {
        self.kind = kind
        root.zPosition = 85
        scene.addChild(root)
        greet(scene)
        switch kind {
        case .diwali: placeAlongGround(scene, spacing: 150) { self.diya() }
        case .halloween:
            placeAlongGround(scene, spacing: 260) { self.pumpkin(size: .random(in: 26...40)) }
            let b = BatsEffect(scene: scene, population: 7)
            b.eventOwned = true
            scene.add(b)
            bats = b
        case .easter: placeAlongGround(scene, spacing: 170) { self.egg() }
        case .christmas:
            for i in 0..<3 {
                let x = scene.size.width * (0.25 + CGFloat(i) * 0.25) + .random(in: -60...60)
                scene.add(PresentEffect(at: CGPoint(x: x, y: scene.size.height * 0.85), vx: .random(in: -40...40), scene: scene))
            }
        default: break
        }
    }

    func finish() {
        finishing = true
        bats?.finish()
        if let scene = root.scene as? SnowScene { props.forEach { scene.unperch($0) } }
        props.removeAll()
        root.run(.sequence([.fadeOut(withDuration: 1), .removeFromParent()]))
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if finishing { return root.parent != nil }
        let w = scene.size.width, h = scene.size.height, tf = CGFloat(t)

        for p in props {        // keep props on top of the snow
            if !p.held, let h = scene.restOffset(for: p) { p.yOffset += (h - p.yOffset) * min(1, dt * 3) }
        }
        for (i, f) in flickers.enumerated() { f.alpha = 0.65 + 0.35 * sin(tf * 9 + CGFloat(i) * 1.7) * sin(tf * 5.3 + CGFloat(i)) }

        // Scheduled events
        if t > nextBurst {
            switch kind {
            case .newYear: nextBurst = t + .random(in: 0.5...1.8); launch(scene)
            case .diwali: nextBurst = t + .random(in: 2...5); launch(scene)
            case .holi: nextBurst = t + .random(in: 1.5...4); colourBurst(at: CGPoint(x: .random(in: 0...w), y: .random(in: (h * 0.2)...(h * 0.8))))
            default: nextBurst = .infinity
            }
        }
        if t > nextFlier {
            switch kind {
            case .halloween:
                nextFlier = t + .random(in: 3...8)
                if fliers.count < 3 { spawnGhost(w: w, h: h) }
            case .valentines:
                nextFlier = t + .random(in: 0.6...1.6)
                if fliers.count < 24 { spawnHeart(w: w) }
            case .easter:
                nextFlier = t + .random(in: 18...35)
                spawnBunny(scene)
            default: nextFlier = .infinity
            }
        }

        stepRockets(dt: dt)
        stepSparks(dt: dt)
        stepFliers(dt: dt, tf: tf, scene: scene)
        return true
    }

    func click(at p: CGPoint, count: Int, in scene: SnowScene) -> Bool {
        if kind == .holi { colourBurst(at: p) }
        if kind == .newYear || kind == .diwali { burst(at: p, colors: palette()) }
        return false
    }

    // MARK: Greeting

    private func greet(_ scene: SnowScene) {
        let g = SKNode()
        for (off, color) in [(CGPoint(x: 2, y: -2), NSColor.black.withAlphaComponent(0.45)), (.zero, NSColor.white)] {
            let l = SKLabelNode(text: kind.greeting)
            l.fontName = "Avenir Next Demi Bold"
            l.fontSize = 46
            l.fontColor = color
            l.position = off
            g.addChild(l)
        }
        let glow = glowSprite(palette()[0], size: 520, alpha: 0.25)
        glow.yScale = 0.25
        glow.position.y = 16
        glow.zPosition = -1
        g.addChild(glow)
        g.position = CGPoint(x: scene.size.width / 2, y: scene.size.height * 0.78)
        g.alpha = 0
        g.setScale(0.8)
        root.addChild(g)
        g.run(.sequence([.wait(forDuration: 0.8), .group([.fadeIn(withDuration: 0.8), .scale(to: 1, duration: 0.8)]),
                         .wait(forDuration: 5), .fadeOut(withDuration: 1.5), .removeFromParent()]))
    }

    private func palette() -> [NSColor] {
        switch kind {
        case .diwali: return [rgb(1, 0.75, 0.2), rgb(1, 0.45, 0.15), rgb(1, 0.95, 0.6), rgb(0.95, 0.3, 0.5)]
        case .valentines: return [rgb(1, 0.35, 0.5), rgb(1, 0.6, 0.7)]
        case .halloween: return [rgb(1, 0.55, 0.1), rgb(0.6, 0.3, 0.9)]
        case .holi: return [rgb(1, 0.2, 0.55), rgb(0.2, 0.8, 0.3), rgb(1, 0.85, 0.1), rgb(0.2, 0.5, 1), rgb(0.7, 0.25, 0.9), rgb(1, 0.5, 0.1)]
        case .easter: return [rgb(0.7, 0.9, 0.6), rgb(1, 0.8, 0.9)]
        case .christmas: return [rgb(1, 0.3, 0.3), rgb(0.3, 0.9, 0.4)]
        case .newYear: return [rgb(1, 0.85, 0.3), rgb(0.4, 0.8, 1), rgb(1, 0.4, 0.6), rgb(0.6, 1, 0.5), rgb(0.85, 0.55, 1)]
        }
    }

    // MARK: Fireworks

    /// A rocket aimed to peak (and burst) in the middle band of the screen, never off the top.
    private func launch(_ scene: SnowScene) {
        let w = scene.size.width, h = scene.size.height
        let s = glowSprite(rgb(1, 0.9, 0.7), size: 10)
        s.position = CGPoint(x: .random(in: (w * 0.12)...(w * 0.88)), y: -10)
        root.addChild(s)
        let peak = CGFloat.random(in: (h * 0.4)...(h * 0.66))
        let vy = sqrt(2 * rocketGravity * (peak - s.position.y))      // just enough speed to reach the peak
        let colors = palette().shuffled()
        rockets.append(Rocket(node: s, v: CGVector(dx: .random(in: -30...30), dy: vy), fuse: vy / rocketGravity,
                              color: Array(colors.prefix(Int.random(in: 1...2)))))
        Sound.shared.play(.pop, volume: 0.12)
    }

    private func stepRockets(dt: CGFloat) {
        var i = 0
        while i < rockets.count {
            var r = rockets[i]
            r.fuse -= dt
            r.v.dy -= (r.small ? 160 : rocketGravity) * dt
            r.node.position.x += r.v.dx * dt
            r.node.position.y += r.v.dy * dt
            if Int.random(in: 0..<(r.small ? 3 : 2)) == 0 {      // sparkling trail
                addSpark(at: r.node.position, v: CGVector(dx: .random(in: -15...15), dy: -.random(in: 20...60)), color: rgb(1, 0.8, 0.5),
                         size: r.small ? 2 : 3, life: 0.4, gravity: 60)
            }
            if r.fuse <= 0 {
                if r.small { smallBurst(at: r.node.position, color: r.color[0]) } else { burst(at: r.node.position, colors: r.color) }
                r.node.removeFromParent()
                rockets.remove(at: i)          // (a crossette burst may have appended new rockets; they're stepped next frame)
                continue
            }
            rockets[i] = r                     // write back: the struct is a copy
            i += 1
        }
    }

    private enum Shell: CaseIterable { case peony, ring, willow, crossette, crackle }

    /// The main blast: a bright flash and shockwave, then one of several shell patterns sized to the screen.
    private func burst(at p: CGPoint, colors: [NSColor]) {
        guard sparks.count < 1100, let scene = root.scene else { return }
        Sound.shared.play(.pop, volume: 0.45)
        let radius = min(scene.size.width, scene.size.height) * .random(in: 0.13...0.2)
        let shell = Shell.allCases.randomElement()!
        let drag: CGFloat = 2.2
        let speed = radius * drag                               // with this drag, sparks coast out to about `radius`

        // Flash, wide glow and an expanding shockwave ring.
        let flash = glowSprite(.white, size: radius * 0.9, alpha: 0.95)
        flash.position = p
        root.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.5, duration: 0.18), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
        let wash = glowSprite(colors[0], size: radius * 4, alpha: 0.22)
        wash.position = p
        root.addChild(wash)
        wash.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
        let ring = Shape.ellipse(CGRect(x: -10, y: -10, width: 20, height: 20), fill: nil, stroke: NSColor.white.withAlphaComponent(0.45), line: 0.8)
        let shock = Bake.sprite(ring, key: "shock")
        shock.color = colors[0]
        shock.colorBlendFactor = 1
        shock.position = p
        root.addChild(shock)
        shock.run(.sequence([.group([.scale(to: radius / 9, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))

        switch shell {
        case .peony, .crackle:
            for i in 0..<95 {
                let a = CGFloat.random(in: 0...(2 * .pi)), sp = speed * sqrt(.random(in: 0.15...1))
                addSpark(at: p, v: CGVector(dx: cos(a) * sp, dy: sin(a) * sp), color: colors[i % colors.count], size: .random(in: 7...12),
                         life: .random(in: 1.3...2.1), gravity: 70, drag: drag, crackle: shell == .crackle)
            }
        case .ring:
            for (k, scale) in [(0, CGFloat(1)), (1, 0.55)] {
                let n = k == 0 ? 56 : 30
                for i in 0..<n {
                    let a = CGFloat(i) / CGFloat(n) * 2 * .pi
                    addSpark(at: p, v: CGVector(dx: cos(a) * speed * scale, dy: sin(a) * speed * scale), color: colors[(i + k) % colors.count],
                             size: 9, life: .random(in: 1.3...1.8), gravity: 60, drag: drag)
                }
            }
        case .willow:                                            // long golden trails that droop down
            for _ in 0..<60 {
                let a = CGFloat.random(in: 0...(2 * .pi)), sp = speed * .random(in: 0.5...0.9)
                addSpark(at: p, v: CGVector(dx: cos(a) * sp, dy: sin(a) * sp + 40), color: rgb(1, 0.78, 0.35), size: .random(in: 6...9),
                         life: .random(in: 2.4...3.2), gravity: 120, drag: 2.6)
            }
        case .crossette:                                         // a few stars that split again
            for i in 0..<6 {
                let a = CGFloat(i) / 6 * 2 * .pi + .random(in: -0.2...0.2)
                let st = glowSprite(colors[i % colors.count], size: 8)
                st.position = p
                root.addChild(st)
                rockets.append(Rocket(node: st, v: CGVector(dx: cos(a) * speed * 0.7, dy: sin(a) * speed * 0.7), fuse: .random(in: 0.4...0.55),
                                      color: [colors[i % colors.count]], small: true))
            }
            for i in 0..<30 {
                let a = CGFloat.random(in: 0...(2 * .pi)), sp = speed * .random(in: 0.2...0.6)
                addSpark(at: p, v: CGVector(dx: cos(a) * sp, dy: sin(a) * sp), color: colors[i % colors.count], size: 7, life: 1.0, gravity: 70, drag: drag)
            }
        }
    }

    private func smallBurst(at p: CGPoint, color: NSColor) {
        for _ in 0..<14 {
            let a = CGFloat.random(in: 0...(2 * .pi)), sp = CGFloat.random(in: 120...200)
            addSpark(at: p, v: CGVector(dx: cos(a) * sp, dy: sin(a) * sp), color: color, size: 7, life: .random(in: 0.7...1.1), gravity: 80, drag: 2.4)
        }
    }

    private func addSpark(at p: CGPoint, v: CGVector, color: NSColor, size: CGFloat, life: CGFloat, gravity: CGFloat, drag: CGFloat = 0.5,
                          additive: Bool = true, crackle: Bool = false) {
        let s = SKSpriteNode(texture: Tex.glow, size: CGSize(width: size, height: size))
        s.color = color
        s.colorBlendFactor = 1
        s.blendMode = additive ? .add : .alpha
        s.position = p
        root.addChild(s)
        sparks.append(Spark(node: s, v: v, life: life, total: life, drag: drag, gravity: gravity, crackle: crackle))
    }

    private func stepSparks(dt: CGFloat) {
        var i = 0
        while i < sparks.count {
            var s = sparks[i]
            s.life -= dt
            if s.life <= 0 {
                s.node.removeFromParent()
                sparks.swapAt(i, sparks.count - 1)
                sparks.removeLast()
                continue
            }
            let k = exp(-s.drag * dt)
            s.v.dx *= k
            s.v.dy = s.v.dy * k - s.gravity * dt
            s.node.position.x += s.v.dx * dt
            s.node.position.y += s.v.dy * dt
            let f = s.life / s.total
            s.node.alpha = f < 0.3 ? f / 0.3 * (0.6 + 0.4 * CGFloat.random(in: 0...1)) : 1
            if s.crackle && f < 0.55 { s.node.alpha = Bool.random() ? 1 : 0.1 }      // glittering strobe at the end
            sparks[i] = s
            i += 1
        }
    }

    // MARK: Holi colours

    private func colourBurst(at p: CGPoint) {
        guard sparks.count < 900 else { return }
        let c = palette().randomElement()!
        for _ in 0..<26 {
            let a = CGFloat.random(in: 0...(2 * .pi)), sp = CGFloat.random(in: 40...220)
            addSpark(at: p, v: CGVector(dx: cos(a) * sp, dy: sin(a) * sp + 40), color: c, size: .random(in: 26...70),
                     life: .random(in: 1.4...2.6), gravity: 40, drag: 2.2, additive: false)
            sparks[sparks.count - 1].node.alpha = 0.55
        }
    }

    // MARK: Ground props

    private func placeAlongGround(_ scene: SnowScene, spacing: CGFloat, make: () -> SKNode) {
        var x = CGFloat.random(in: 60...120)
        while x < scene.size.width - 40 {
            let n = make()
            n.zPosition = 0.5
            root.addChild(n)
            let c = scene.ground.column(forLocalX: x) ?? 0
            let p = Perched(node: n, windowID: nil, localX: x, yOffset: scene.ground.height(at: c))
            p.onDislodge = { [weak p, weak scene] in if let p, let scene { scene.dropToGround(p) } }
            scene.perch(p)
            props.append(p)
            x += spacing * .random(in: 0.7...1.3)
        }
    }

    private func diya() -> SKNode {
        let n = SKNode()
        let glow = glowSprite(rgb(1, 0.65, 0.2), size: 70, alpha: 0.55)
        glow.position.y = 16
        n.addChild(glow)
        flickers.append(glow)
        let bowl = CGMutablePath()
        bowl.move(to: CGPoint(x: -14, y: 8))
        bowl.addQuadCurve(to: CGPoint(x: 14, y: 8), control: CGPoint(x: 0, y: -10))
        bowl.addLine(to: CGPoint(x: 18, y: 10))
        bowl.addLine(to: CGPoint(x: -14, y: 9))
        bowl.closeSubpath()
        let lamp = SKNode()
        lamp.addChild(Shape.node(bowl, fill: rgb(0.72, 0.32, 0.14)))
        lamp.addChild(Shape.rect(CGRect(x: -12, y: 4, width: 24, height: 2), fill: rgb(0.95, 0.75, 0.2)))
        n.addChild(Bake.sprite(lamp, key: "diya"))
        let flame = CGMutablePath()
        flame.move(to: CGPoint(x: 0, y: 10))
        flame.addQuadCurve(to: CGPoint(x: 0, y: 26), control: CGPoint(x: 7, y: 14))
        flame.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: -7, y: 14))
        let f = Bake.sprite(Shape.node(flame, fill: rgb(1, 0.82, 0.3)), key: "diya-flame")
        n.addChild(f)
        flickers.append(f)
        layerInOrder(n)
        return n
    }

    private func pumpkin(size s: CGFloat) -> SKNode {
        let n = SKNode()
        let glow = glowSprite(rgb(1, 0.6, 0.15), size: s * 3, alpha: 0.4)
        glow.position.y = s * 0.5
        n.addChild(glow)
        flickers.append(glow)
        let orange = rgb(0.95, 0.5, 0.1)
        for (dx, wk) in [(-0.35, 0.75), (0.35, 0.75), (0, 0.85)] as [(CGFloat, CGFloat)] {
            n.addChild(Shape.ellipse(CGRect(x: s * dx - s * wk / 2, y: 0, width: s * wk, height: s * 0.82), fill: dx == 0 ? orange : orange.blended(withFraction: 0.15, of: .black)))
        }
        n.addChild(Shape.rect(CGRect(x: -s * 0.06, y: s * 0.76, width: s * 0.12, height: s * 0.2), radius: 1, fill: rgb(0.3, 0.45, 0.15)))
        let lit = rgb(1, 0.9, 0.35)
        for ex in [CGFloat(-0.22), 0.22] {
            n.addChild(Shape.poly([CGPoint(x: s * ex - s * 0.1, y: s * 0.45), CGPoint(x: s * ex + s * 0.1, y: s * 0.45), CGPoint(x: s * ex, y: s * 0.6)], fill: lit))
        }
        n.addChild(Shape.poly([CGPoint(x: -s * 0.3, y: s * 0.3), CGPoint(x: s * 0.3, y: s * 0.3), CGPoint(x: s * 0.15, y: s * 0.17),
                               CGPoint(x: 0, y: s * 0.25), CGPoint(x: -s * 0.15, y: s * 0.17)], fill: lit))
        layerInOrder(n)
        return bakeShapes(n)
    }

    private func egg() -> SKNode {
        let n = SKNode()
        let colors = [rgb(0.55, 0.8, 1), rgb(1, 0.7, 0.8), rgb(0.75, 0.95, 0.6), rgb(1, 0.9, 0.5), rgb(0.8, 0.7, 1)]
        let base = colors.randomElement()!, band = colors.randomElement()!
        let r = CGRect(x: -9, y: 0, width: 18, height: 24)
        let crop = SKCropNode()
        crop.maskNode = Shape.ellipse(r, fill: .white)
        crop.addChild(Shape.rect(r, fill: base))
        for k in 0..<2 { crop.addChild(Shape.rect(CGRect(x: -10, y: 6 + CGFloat(k) * 8, width: 20, height: 3), fill: band.blended(withFraction: 0.2, of: .black))) }
        for _ in 0..<4 { crop.addChild(Shape.ellipse(CGRect(x: .random(in: -7...5), y: .random(in: 2...20), width: 2.5, height: 2.5), fill: .white)) }
        n.addChild(crop)
        let baked = Bake.sprite(n)
        baked.zRotation = .random(in: -0.3...0.3)
        let holder = SKNode()
        holder.addChild(baked)
        return holder
    }

    /// Bakes a prop's vector shapes into one image, leaving its glow sprites live (they flicker).
    private func bakeShapes(_ n: SKNode) -> SKNode {
        let shapes = SKNode()
        for c in n.children where c is SKShapeNode { c.removeFromParent(); shapes.addChild(c) }
        let baked = Bake.sprite(shapes)
        baked.zPosition = 1
        n.addChild(baked)
        return n
    }

    // MARK: Fliers

    private func spawnBat(w: CGFloat, h: CGFloat) {
        let n = SKNode()
        let ink = rgb(0.1, 0.07, 0.12)
        let l = Shape.poly([.zero, CGPoint(x: -16, y: 6), CGPoint(x: -12, y: -2), CGPoint(x: -7, y: 1), CGPoint(x: -4, y: -3)], fill: ink)
        let r = Shape.poly([.zero, CGPoint(x: 16, y: 6), CGPoint(x: 12, y: -2), CGPoint(x: 7, y: 1), CGPoint(x: 4, y: -3)], fill: ink)
        n.addChild(l); n.addChild(r)
        n.addChild(Shape.ellipse(CGRect(x: -3.5, y: -5, width: 7, height: 9), fill: ink))
        for ex in [CGFloat(-1.5), 1.5] { n.addChild(Shape.ellipse(CGRect(x: ex - 0.8, y: 0, width: 1.6, height: 1.6), fill: rgb(1, 0.8, 0.2))) }
        let dir: CGFloat = Bool.random() ? 1 : -1
        n.position = CGPoint(x: dir > 0 ? -30 : w + 30, y: .random(in: (h * 0.4)...(h * 0.9)))
        n.setScale(.random(in: 0.8...1.4))
        root.addChild(n)
        fliers.append(Flier(node: n, v: CGVector(dx: dir * .random(in: 110...190), dy: 0), life: 40, parts: [l, r]))
    }

    private func spawnGhost(w: CGFloat, h: CGFloat) {
        let n = SKNode()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -14, y: 0))
        p.addLine(to: CGPoint(x: -14, y: 18))
        p.addArc(center: CGPoint(x: 0, y: 18), radius: 14, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: 14, y: 0))
        for k in 0..<4 { p.addQuadCurve(to: CGPoint(x: 14 - CGFloat(k + 1) * 7, y: 0), control: CGPoint(x: 14 - CGFloat(k) * 7 - 3.5, y: k % 2 == 0 ? -6 : 5)) }
        p.closeSubpath()
        n.addChild(Shape.node(p, fill: rgb(0.97, 0.97, 1, 0.85)))
        for ex in [CGFloat(-5), 5] { n.addChild(Shape.ellipse(CGRect(x: ex - 2.5, y: 18, width: 5, height: 7), fill: rgb(0.1, 0.1, 0.15))) }
        n.addChild(Shape.ellipse(CGRect(x: -3, y: 9, width: 6, height: 6), fill: rgb(0.1, 0.1, 0.15)))
        let dir: CGFloat = Bool.random() ? 1 : -1
        let ghost = SKNode()
        ghost.addChild(Bake.sprite(n, key: "ghost"))
        ghost.position = CGPoint(x: dir > 0 ? -30 : w + 30, y: .random(in: (h * 0.2)...(h * 0.7)))
        ghost.xScale = dir
        root.addChild(ghost)
        fliers.append(Flier(node: ghost, v: CGVector(dx: dir * .random(in: 35...60), dy: 0), life: 80))
    }

    private func spawnHeart(w: CGFloat) {
        let s = CGFloat.random(in: 8...18)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -s))
        p.addCurve(to: CGPoint(x: 0, y: s * 0.4), control1: CGPoint(x: s * 1.3, y: -s * 0.15), control2: CGPoint(x: s * 0.9, y: s * 1.15))
        p.addCurve(to: CGPoint(x: 0, y: -s), control1: CGPoint(x: -s * 0.9, y: s * 1.15), control2: CGPoint(x: -s * 1.3, y: -s * 0.15))
        let ci = Int.random(in: 0..<palette().count), sz = Int(s)
        let n = SKNode()
        n.addChild(Bake.sprite(Shape.node(p, fill: palette()[ci].withAlphaComponent(0.85)), key: "heart\(ci)-\(sz)"))
        n.position = CGPoint(x: .random(in: 0...w), y: -20)
        root.addChild(n)
        fliers.append(Flier(node: n, v: CGVector(dx: 0, dy: .random(in: 40...80)), life: 30))
    }

    private func spawnBunny(_ scene: SnowScene) {
        let n = SKNode()
        let fur = [rgb(0.95, 0.93, 0.9), rgb(0.7, 0.55, 0.4), rgb(0.55, 0.52, 0.5)].randomElement()!
        n.addChild(Shape.ellipse(CGRect(x: -12, y: 0, width: 22, height: 15), fill: fur))
        n.addChild(Shape.ellipse(CGRect(x: -15, y: 5, width: 7, height: 7), fill: .white))
        n.addChild(Shape.ellipse(CGRect(x: 4, y: 9, width: 12, height: 11), fill: fur))
        for (x, a) in [(CGFloat(7), CGFloat(0.25)), (11, -0.1)] {
            let ear = Shape.ellipse(CGRect(x: -2.5, y: 0, width: 5, height: 14), fill: fur)
            ear.position = CGPoint(x: x, y: 17)
            ear.zRotation = a
            n.addChild(ear)
        }
        n.addChild(Shape.ellipse(CGRect(x: 11, y: 14, width: 2, height: 2), fill: rgb(0.1, 0.1, 0.1)))
        n.addChild(Shape.ellipse(CGRect(x: 14.5, y: 12, width: 2.2, height: 1.8), fill: rgb(1, 0.6, 0.7)))
        layerInOrder(n)
        let bunny = SKNode()
        bunny.addChild(Bake.sprite(n))
        let dir: CGFloat = Bool.random() ? 1 : -1
        bunny.xScale = dir
        bunny.position = CGPoint(x: dir > 0 ? -30 : scene.size.width + 30, y: 0)
        root.addChild(bunny)
        fliers.append(Flier(node: bunny, v: CGVector(dx: dir * 90, dy: 0), life: 60))
    }

    private func stepFliers(dt: CGFloat, tf: CGFloat, scene: SnowScene) {
        let w = scene.size.width, h = scene.size.height
        fliers = fliers.filter { f in
            f.life -= dt
            let p = f.node.position
            switch kind {
            case .halloween where !f.parts.isEmpty:          // bat: erratic flutter
                let a = sin(tf * 22 + f.phase) * 0.7
                f.parts[0].zRotation = -a; f.parts[1].zRotation = a
                f.v.dy += .random(in: -300...300) * dt - (p.y - h * 0.65) * 0.4 * dt
                f.v.dy *= 0.97
            case .halloween:                                  // ghost: bob and fade in and out
                f.v.dy = sin(tf * 1.4 + f.phase) * 18
                f.node.alpha = 0.35 + 0.45 * (0.5 + 0.5 * sin(tf * 0.8 + f.phase))
            case .valentines:
                f.v.dx = sin(tf * 1.6 + f.phase) * 30
                f.node.zRotation = sin(tf * 1.6 + f.phase) * 0.2
                f.node.alpha = max(0, min(1, (h - p.y) / 200))
                if scene.cursorInside && hypot(scene.cursor.x - p.x, scene.cursor.y - p.y) < 24 {
                    for _ in 0..<12 { addSpark(at: p, v: CGVector(dx: .random(in: -120...120), dy: .random(in: -120...120)), color: rgb(1, 0.5, 0.65), size: 5, life: 0.6, gravity: 50) }
                    Sound.shared.play(.pop, volume: 0.3)
                    f.node.removeFromParent()
                    return false
                }
            case .easter:                                      // bunny: hop along the snow
                let ground = scene.ground.height(at: scene.ground.column(forLocalX: min(max(p.x, 0), w - 1)) ?? 0)
                let hop = abs(sin(tf * 5 + f.phase)) * 18
                f.node.position.y = ground + hop
                f.node.zRotation = cos(tf * 5 + f.phase) * 0.15 * (f.v.dx > 0 ? 1 : -1) * (sin(tf * 5 + f.phase) > 0 ? 1 : -1)
            default: break
            }
            f.node.position.x += f.v.dx * dt
            if kind != .easter { f.node.position.y += f.v.dy * dt }
            let out = f.life <= 0 || f.node.position.x < -60 || f.node.position.x > w + 60 || f.node.position.y > h + 40
            if out { f.node.removeFromParent() }
            return !out
        }
    }
}
