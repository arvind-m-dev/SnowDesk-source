import SpriteKit

/// Gives every node in a rig a z order that follows the order parts were added (back to front),
/// because the overlay renders with `ignoresSiblingOrder`.
func layerInOrder(_ node: SKNode, step: CGFloat = 0.01) {
    for (i, c) in node.children.enumerated() {
        c.zPosition = CGFloat(i + 1) * step
        layerInOrder(c, step: step / 30)
    }
}

private func gradientTexture(_ top: NSColor, _ bottom: NSColor) -> SKTexture {
    Tex.make(4, 64) { ctx, r in Tex.linear(ctx, [bottom, top], [0, 1], from: .zero, to: CGPoint(x: 0, y: r.maxY)) }
}

// MARK: - Flight path

/// A smooth random route (Catmull-Rom spline through random waypoints) walked at constant speed.
struct FlightPath {
    private var pts: [CGPoint] = []
    private var cum: [CGFloat] = []
    var length: CGFloat { cum.last ?? 0 }

    init(through controls: [CGPoint]) {
        let c = [controls[0]] + controls + [controls[controls.count - 1]]
        for i in 1..<(c.count - 2) {
            let p0 = c[i - 1], p1 = c[i], p2 = c[i + 1], p3 = c[i + 2]
            for k in 0..<24 {
                let t = CGFloat(k) / 24, t2 = t * t, t3 = t2 * t
                func f(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3)
                }
                pts.append(CGPoint(x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        pts.append(controls[controls.count - 1])
        cum = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
    }

    /// Position and heading at distance d (before the start it continues straight back off-screen).
    func point(at d: CGFloat) -> (CGPoint, CGFloat) {
        if d <= 0 {
            let a = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
            return (CGPoint(x: pts[0].x + cos(a) * d, y: pts[0].y + sin(a) * d), a)
        }
        if d >= length {
            let n = pts.count
            let a = atan2(pts[n - 1].y - pts[n - 2].y, pts[n - 1].x - pts[n - 2].x)
            let e = d - length
            return (CGPoint(x: pts[n - 1].x + cos(a) * e, y: pts[n - 1].y + sin(a) * e), a)
        }
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if cum[m] <= d { lo = m } else { hi = m } }
        let u = (d - cum[lo]) / max(0.0001, cum[hi] - cum[lo])
        let p = CGPoint(x: pts[lo].x + (pts[hi].x - pts[lo].x) * u, y: pts[lo].y + (pts[hi].y - pts[lo].y) * u)
        return (p, atan2(pts[hi].y - pts[lo].y, pts[hi].x - pts[lo].x))
    }

    /// Enters from one side, wanders through random waypoints (sometimes doubling back), leaves the other side.
    static func random(size: CGSize, through drop: CGPoint?) -> FlightPath {
        let w = size.width, h = size.height
        let dir: CGFloat = Bool.random() ? 1 : -1
        func y() -> CGFloat { .random(in: (h * 0.58)...(h * 0.86)) }
        var p: [CGPoint] = [CGPoint(x: dir > 0 ? -200 : w + 200, y: y())]
        let n = Int.random(in: 3...5)
        for k in 1...n {
            let u = CGFloat(k) / CGFloat(n + 1) + .random(in: -0.07...0.07)
            p.append(CGPoint(x: dir > 0 ? w * u : w * (1 - u), y: y()))
            if Int.random(in: 0..<10) < 3 && k < n {          // swing back for a moment
                let last = p[p.count - 1]
                p.append(CGPoint(x: last.x - dir * w * .random(in: 0.12...0.22), y: min(h * 0.92, max(h * 0.45, last.y + .random(in: -0.15...0.15) * h))))
            }
        }
        if let d = drop, let i = (1..<p.count).min(by: { abs(p[$0].x - d.x) < abs(p[$1].x - d.x) }) {
            p[i] = CGPoint(x: d.x, y: min(h * 0.86, max(h * 0.5, d.y + .random(in: 110...200))))
        }
        p.append(CGPoint(x: dir > 0 ? w + 500 : -500, y: y()))
        return FlightPath(through: p)
    }
}

// MARK: - Rigs

/// A reindeer built from jointed parts: torso, neck → head (antlers, ear), tail, and four legs,
/// each with a hip and a knee so it gallops.
final class Reindeer {
    let root = SKNode()
    private let neck = SKNode()
    private let head = SKNode()
    private let tail = SKNode()
    private var legs: [(hip: SKNode, knee: SKNode, offset: CGFloat, front: Bool)] = []
    let chest = CGPoint(x: 15, y: 1)

    private static let coatTex = gradientTexture(rgb(0.62, 0.42, 0.24), rgb(0.40, 0.25, 0.13))

    init(lead: Bool) {
        let coat = rgb(0.52, 0.33, 0.18), far = rgb(0.34, 0.21, 0.11), belly = rgb(0.85, 0.74, 0.58)
        addLeg(x: 12, front: true, color: far, offset: 0.5)
        addLeg(x: -12, front: false, color: far, offset: .pi + 0.5)

        tail.position = CGPoint(x: -17, y: 4)
        tail.addChild(Shape.ellipse(CGRect(x: -7, y: -2, width: 8, height: 5), fill: belly))
        root.addChild(tail)

        let torso = Shape.ellipse(CGRect(x: -19, y: -8, width: 38, height: 16), fill: .white)
        torso.fillTexture = Reindeer.coatTex
        root.addChild(torso)
        root.addChild(Shape.ellipse(CGRect(x: -12, y: -8, width: 24, height: 7), fill: belly.withAlphaComponent(0.8)))

        neck.position = CGPoint(x: 13, y: 3)
        let neckShape = Shape.poly([CGPoint(x: -4, y: -3), CGPoint(x: 4, y: -4), CGPoint(x: 10, y: 13), CGPoint(x: 3, y: 15)], fill: .white)
        neckShape.fillTexture = Reindeer.coatTex
        neck.addChild(neckShape)
        neck.addChild(Shape.rect(CGRect(x: -4, y: -1, width: 9, height: 3.5), radius: 1.5, fill: rgb(0.75, 0.1, 0.12)))   // collar
        neck.addChild(Shape.ellipse(CGRect(x: 0, y: -3.5, width: 3.6, height: 3.6), fill: rgb(1, 0.82, 0.3)))             // bell
        head.position = CGPoint(x: 7, y: 14)
        let antlerColor = rgb(0.86, 0.76, 0.56)
        for (dx, col) in [(-2.0, antlerColor.blended(withFraction: 0.25, of: .black)!), (1.0, antlerColor)] {
            let antler = SKNode()
            antler.position = CGPoint(x: dx, y: 3)
            antler.addChild(Shape.line([CGPoint(x: 0, y: 0), CGPoint(x: -2, y: 8), CGPoint(x: -7, y: 13)], color: col, width: 1.7))
            antler.addChild(Shape.line([CGPoint(x: -1, y: 5), CGPoint(x: 3, y: 10)], color: col, width: 1.4))
            antler.addChild(Shape.line([CGPoint(x: -2, y: 8), CGPoint(x: -1, y: 14)], color: col, width: 1.3))
            antler.addChild(Shape.line([CGPoint(x: -4.5, y: 10.5), CGPoint(x: -8, y: 9)], color: col, width: 1.2))
            head.addChild(antler)
        }
        let skull = Shape.ellipse(CGRect(x: -3, y: -4, width: 14, height: 9), fill: .white)
        skull.fillTexture = Reindeer.coatTex
        head.addChild(skull)
        head.addChild(Shape.ellipse(CGRect(x: 7, y: -4, width: 8, height: 6), fill: rgb(0.68, 0.5, 0.33)))   // muzzle
        let ear = Shape.ellipse(CGRect(x: -2, y: -1.5, width: 7, height: 3), fill: coat)
        ear.position = CGPoint(x: 0, y: 3)
        ear.zRotation = 0.5
        head.addChild(ear)
        head.addChild(Shape.ellipse(CGRect(x: 4, y: 0.5, width: 2.4, height: 2.4), fill: rgb(0.08, 0.06, 0.05)))
        head.addChild(Shape.ellipse(CGRect(x: 4.8, y: 1.6, width: 0.8, height: 0.8), fill: .white))
        if lead {
            let glow = glowSprite(rgb(1, 0.15, 0.1), size: 20)
            glow.position = CGPoint(x: 15, y: -1)
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.45), .fadeAlpha(to: 1, duration: 0.45)])))
            head.addChild(glow)
            head.addChild(Shape.ellipse(CGRect(x: 12.5, y: -3.2, width: 4.6, height: 4.6), fill: rgb(1, 0.18, 0.12)))
        } else {
            head.addChild(Shape.ellipse(CGRect(x: 13, y: -2.5, width: 3, height: 2.5), fill: rgb(0.15, 0.1, 0.08)))
        }
        neck.addChild(head)
        root.addChild(neck)

        addLeg(x: 14, front: true, color: coat, offset: 0)
        addLeg(x: -10, front: false, color: coat, offset: .pi)
        layerInOrder(root)
    }

    private func addLeg(x: CGFloat, front: Bool, color: NSColor, offset: CGFloat) {
        let hip = SKNode()
        hip.position = CGPoint(x: x, y: -3)
        hip.addChild(Shape.rect(CGRect(x: -2.8, y: -11, width: 5.6, height: 13), radius: 2.6, fill: color))
        let knee = SKNode()
        knee.position = CGPoint(x: 0, y: -10)
        knee.addChild(Shape.rect(CGRect(x: -1.6, y: -10, width: 3.2, height: 11), radius: 1.5, fill: color))
        knee.addChild(Shape.rect(CGRect(x: -2.1, y: -12.5, width: 4.2, height: 3), radius: 1, fill: rgb(0.2, 0.13, 0.08)))
        hip.addChild(knee)
        root.addChild(hip)
        legs.append((hip, knee, offset, front))
    }

    /// Gallop pose for phase φ.
    func animate(_ phi: CGFloat) {
        for l in legs {
            let a = phi + l.offset
            l.hip.zRotation = (l.front ? 0.7 : 0.55) * sin(a) + (l.front ? 0.2 : -0.1)
            l.knee.zRotation = l.front ? -1.0 * max(0, sin(a + 0.9)) : 0.85 * max(0, sin(a - 0.7))
        }
        neck.zRotation = 0.12 * sin(phi + 1.2)
        head.zRotation = -0.1 * sin(phi + 1.2)
        tail.zRotation = 0.4 * sin(phi * 2)
    }
}

/// The sleigh with Santa: shaded body and runners, a sack of presents, and Santa with a waving arm and a floppy hat.
final class SleighRig {
    let root = SKNode()
    private let santa = SKNode()
    private let shoulder = SKNode()
    private let elbow = SKNode()
    private let hatTip = SKNode()
    let front = CGPoint(x: 40, y: 18)

    init() {
        let red = rgb(0.80, 0.10, 0.12), gold = rgb(0.95, 0.78, 0.30), skin = rgb(1, 0.83, 0.70)
        // Sack with presents peeking out
        root.addChild(Shape.ellipse(CGRect(x: -44, y: 14, width: 30, height: 32), fill: rgb(0.55, 0.38, 0.22)))
        for (x, y, c) in [(-40.0, 38.0, rgb(0.2, 0.5, 0.3)), (-31.0, 41.0, rgb(0.2, 0.35, 0.75)), (-24.0, 36.0, rgb(0.95, 0.78, 0.25))] {
            let b = Shape.rect(CGRect(x: x, y: y, width: 9, height: 9), radius: 1, fill: c)
            b.zRotation = .random(in: -0.3...0.3)
            root.addChild(b)
        }
        // Santa
        santa.position = CGPoint(x: -4, y: 16)
        let coat = Shape.ellipse(CGRect(x: -13, y: 0, width: 26, height: 28), fill: .white)
        coat.fillTexture = gradientTexture(rgb(0.92, 0.18, 0.18), rgb(0.6, 0.05, 0.08))
        santa.addChild(coat)
        santa.addChild(Shape.rect(CGRect(x: -13, y: 7, width: 26, height: 4), fill: rgb(0.1, 0.08, 0.08)))
        santa.addChild(Shape.rect(CGRect(x: -2.5, y: 6.5, width: 5, height: 5), radius: 1, fill: gold))
        santa.addChild(Shape.ellipse(CGRect(x: -6, y: 23, width: 15, height: 14), fill: skin))
        santa.addChild(Shape.ellipse(CGRect(x: -6, y: 14, width: 17, height: 17), fill: .white))          // beard
        santa.addChild(Shape.ellipse(CGRect(x: 0, y: 25, width: 9, height: 4), fill: rgb(0.95, 0.95, 0.95))) // moustache
        santa.addChild(Shape.ellipse(CGRect(x: 6, y: 28.5, width: 2.2, height: 2.2), fill: .black))
        santa.addChild(Shape.ellipse(CGRect(x: 8, y: 26, width: 4, height: 3.5), fill: rgb(1, 0.6, 0.55)))   // cheek/nose
        let hat = SKNode()
        hat.position = CGPoint(x: 1, y: 35)
        hatTip.position = CGPoint(x: 0, y: 0)
        hatTip.addChild(Shape.poly([CGPoint(x: -8, y: 0), CGPoint(x: 9, y: 0), CGPoint(x: -9, y: 15)], fill: red))
        hatTip.addChild(Shape.ellipse(CGRect(x: -13, y: 12, width: 7, height: 7), fill: .white))
        hat.addChild(hatTip)
        hat.addChild(Shape.rect(CGRect(x: -9, y: -3, width: 19, height: 5), radius: 2.5, fill: .white))
        santa.addChild(hat)
        shoulder.position = CGPoint(x: 5, y: 20)
        shoulder.addChild(Shape.rect(CGRect(x: -3, y: -10, width: 6, height: 11), radius: 3, fill: red))
        elbow.position = CGPoint(x: 0, y: -9)
        elbow.addChild(Shape.rect(CGRect(x: -2.6, y: -9, width: 5.2, height: 10), radius: 2.6, fill: red))
        elbow.addChild(Shape.ellipse(CGRect(x: -3.5, y: -12.5, width: 7, height: 6), fill: rgb(0.1, 0.35, 0.18)))   // mitten
        shoulder.addChild(elbow)
        santa.addChild(shoulder)
        root.addChild(santa)

        // Sleigh body (shaded) with gold trim and a curled front
        let body = Shape.poly([CGPoint(x: -46, y: 2), CGPoint(x: 26, y: 2), CGPoint(x: 38, y: 10), CGPoint(x: 43, y: 22),
                               CGPoint(x: 37, y: 28), CGPoint(x: 32, y: 19), CGPoint(x: -28, y: 21), CGPoint(x: -46, y: 34)],
                              fill: .white, stroke: gold, line: 1.6)
        body.fillTexture = gradientTexture(rgb(0.9, 0.16, 0.16), rgb(0.52, 0.04, 0.06))
        root.addChild(body)
        root.addChild(Shape.line([CGPoint(x: -40, y: 10), CGPoint(x: 24, y: 10)], color: gold.withAlphaComponent(0.8), width: 1.2))
        root.addChild(Shape.ellipse(CGRect(x: 38, y: 21, width: 6, height: 6), fill: gold))
        // Runners
        for (dx, alpha) in [(4.0, 0.55), (0.0, 1.0)] {
            root.addChild(Shape.line([CGPoint(x: -48 + dx, y: -6), CGPoint(x: 34 + dx, y: -6), CGPoint(x: 45 + dx, y: 0), CGPoint(x: 47 + dx, y: 8),
                                      CGPoint(x: 42 + dx, y: 10)], color: gold.withAlphaComponent(alpha), width: 2.6))
        }
        root.addChild(Shape.line([CGPoint(x: -33, y: -6), CGPoint(x: -33, y: 3)], color: gold, width: 2))
        root.addChild(Shape.line([CGPoint(x: 17, y: -6), CGPoint(x: 17, y: 3)], color: gold, width: 2))
        layerInOrder(root)
    }

    func animate(_ t: CGFloat) {
        // Santa waves for ~2 s every ~6 s, otherwise holds the reins out front.
        let waving = (t.truncatingRemainder(dividingBy: 6)) < 2
        let targetShoulder: CGFloat = waving ? 2.5 + 0.35 * sin(t * 11) : 1.25 + 0.06 * sin(t * 3)
        let targetElbow: CGFloat = waving ? 0.5 + 0.3 * sin(t * 11 + 1) : -0.5
        shoulder.zRotation += (targetShoulder - shoulder.zRotation) * 0.2
        elbow.zRotation += (targetElbow - elbow.zRotation) * 0.2
        santa.position.y = 16 + sin(t * 4) * 0.8
        hatTip.zRotation = -0.15 + 0.18 * sin(t * 5)
    }
}

// MARK: - Santa

/// Santa's team on a random, wandering flight across the sky. Drops a present on a window on the way.
final class SantaEffect: SceneEffect {
    private let path: FlightPath
    private let speed = CGFloat.random(in: 200...250)
    private var s: CGFloat = 0
    private var phi: CGFloat = 0
    private let root = SKNode()
    private var deer: [Reindeer] = []
    private let sleigh = SleighRig()
    private let reins = SKShapeNode()
    private let reinsFar = SKShapeNode()
    private var sparkleTimer: CGFloat = 0
    private let drop: CGPoint?
    private var dropped = false
    private static let spacing: CGFloat = 52
    private static let sleighGap: CGFloat = 66

    init(scene: SnowScene) {
        let w = scene.size.width, h = scene.size.height
        let targets = scene.visibleWindows.filter {
            $0.rect.minX > 0 && $0.rect.maxX < w && $0.rect.maxY < h * 0.78 && $0.rect.width > 160 &&
                $0.pile.exposed.filter { $0 }.count * 2 > $0.pile.count      // top edge mostly visible
        }
        if let t = targets.randomElement() {
            drop = CGPoint(x: t.rect.minX + t.rect.width * .random(in: 0.25...0.75), y: t.rect.maxY)
        } else {
            drop = CGPoint(x: .random(in: (w * 0.2)...(w * 0.8)), y: 0)
        }
        path = FlightPath.random(size: scene.size, through: drop)

        root.zPosition = 150
        scene.addChild(root)
        reinsFar.strokeColor = rgb(0.6, 0.45, 0.2, 0.8)
        reinsFar.lineWidth = 1
        reinsFar.zPosition = 0.5
        root.addChild(reinsFar)
        for i in 0..<4 {
            let d = Reindeer(lead: i == 0)
            d.root.zPosition = 1 + CGFloat(i) * 0.1
            root.addChild(d.root)
            deer.append(d)
        }
        reins.strokeColor = rgb(0.95, 0.78, 0.3)
        reins.lineWidth = 1.3
        reins.zPosition = 2.5
        root.addChild(reins)
        sleigh.root.zPosition = 3
        root.addChild(sleigh.root)
    }

    /// Faces the part along `angle`, mirrored when flying left so it never ends up upside down.
    private func pose(_ n: SKNode, at p: CGPoint, angle a: CGFloat) {
        n.position = p
        let left = cos(a) < 0
        n.xScale = left ? -1 : 1
        var r = left ? a - .pi : a
        while r > .pi { r -= 2 * .pi }
        while r < -.pi { r += 2 * .pi }
        n.zRotation = max(-0.85, min(0.85, r))
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        s += speed * dt
        phi += dt * 9
        let tf = CGFloat(t)

        var chests: [CGPoint] = []
        for (i, d) in deer.enumerated() {
            let (p, a) = path.point(at: s - CGFloat(i) * SantaEffect.spacing)
            let bob = sin(phi + CGFloat(i) * 0.9) * 2.5
            pose(d.root, at: CGPoint(x: p.x, y: p.y + bob), angle: a)
            d.animate(phi + CGFloat(i) * 0.9)
            chests.append(d.root.convert(d.chest, to: root))
        }
        let sd = s - CGFloat(deer.count - 1) * SantaEffect.spacing - SantaEffect.sleighGap
        let (sp, sa) = path.point(at: sd)
        pose(sleigh.root, at: CGPoint(x: sp.x, y: sp.y + sin(tf * 2.2) * 2), angle: sa)
        sleigh.animate(tf)

        // Reins from the sleigh's front through each reindeer's collar.
        let start = sleigh.root.convert(sleigh.front, to: root)
        let line = CGMutablePath()
        line.move(to: start)
        for c in chests.reversed() { line.addLine(to: c) }
        reins.path = line
        reinsFar.path = line.copy(using: [CGAffineTransform(translationX: -2, y: 3)])

        // Sparkle trail
        sparkleTimer -= dt
        if sparkleTimer <= 0 {
            sparkleTimer = 0.03
            let back = sleigh.root.convert(CGPoint(x: -50, y: 8), to: scene)
            let st = SKSpriteNode(texture: Tex.spark, size: CGSize(width: 12, height: 12))
            st.color = Bool.random() ? rgb(1, 0.9, 0.5) : .white
            st.colorBlendFactor = 1
            st.blendMode = .add
            st.position = CGPoint(x: back.x + .random(in: -4...4), y: back.y + .random(in: -6...6))
            st.zPosition = 149
            scene.addChild(st)
            st.run(.sequence([.group([.moveBy(x: .random(in: -10...10), y: -.random(in: 20...60), duration: 1.3),
                                      .fadeOut(withDuration: 1.3), .scale(to: 0.2, duration: 1.3)]), .removeFromParent()]))
        }

        // Drop the present as the sleigh passes over the chosen window.
        if !dropped, let d = drop, abs(sp.x - d.x) < 14, sp.y > d.y + 20 {
            dropped = true
            let vx = cos(sa) * speed * 0.25
            scene.add(PresentEffect(at: CGPoint(x: sp.x, y: sp.y + 4), vx: vx, scene: scene))
        }

        if sd > path.length + 300 {
            root.removeFromParent()
            return false
        }
        return true
    }
}

/// A wrapped present. Falls, rests on a window (riding along with it), and opens when clicked.
final class PresentEffect: SceneEffect {
    private let node = SKNode()
    private let lid = SKNode()
    var position: CGPoint { node.position }
    var isOpened: Bool { opened }
    var isPerched: Bool { perch != nil }
    private var vel: CGVector
    private var perch: Perched?
    private var opened = false
    private var finished = false
    private var age: CGFloat = 0

    private static let messages = [
        "You're on the nice list!", "Warm wishes for a cozy season", "Ho ho ho!",
        "A mug of cocoa is waiting for you", "Take a break, you've earned it",
        "Something wonderful is on its way", "Merry everything!", "Let it snow, let it snow",
    ]

    init(at p: CGPoint, vx: CGFloat, scene: SnowScene) {
        vel = CGVector(dx: vx, dy: 0)
        let palette: [(NSColor, NSColor)] = [(rgb(0.8, 0.12, 0.15), rgb(0.98, 0.85, 0.35)),
                                             (rgb(0.12, 0.5, 0.28), rgb(0.95, 0.2, 0.2)),
                                             (rgb(0.18, 0.35, 0.75), .white),
                                             (rgb(0.95, 0.78, 0.25), rgb(0.75, 0.1, 0.15))]
        let (box, ribbon) = palette.randomElement()!
        node.addChild(Shape.rect(CGRect(x: -13, y: 0, width: 26, height: 20), radius: 2, fill: box))
        node.addChild(Shape.rect(CGRect(x: -2.5, y: 0, width: 5, height: 20), fill: ribbon))
        lid.addChild(Shape.rect(CGRect(x: -15, y: 19, width: 30, height: 7), radius: 2, fill: box.blended(withFraction: 0.15, of: .black)))
        lid.addChild(Shape.rect(CGRect(x: -2.5, y: 19, width: 5, height: 7), fill: ribbon))
        lid.addChild(Shape.ellipse(CGRect(x: -9, y: 25, width: 9, height: 7), fill: ribbon))
        lid.addChild(Shape.ellipse(CGRect(x: 0, y: 25, width: 9, height: 7), fill: ribbon))
        node.addChild(lid)
        node.position = p
        node.zPosition = 60
        scene.addChild(node)
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if finished { return false }
        age += dt
        if perch == nil && !opened {
            vel.dy -= 700 * dt
            vel.dx *= 1 - 0.8 * dt
            let p = node.position
            let np = CGPoint(x: p.x + vel.dx * dt, y: p.y + vel.dy * dt)
            node.zRotation = sin(age * 5) * 0.15
            let s = scene.surface(under: np.x, atOrBelow: p.y)
            if np.y <= s.top {
                node.zRotation = 0
                let perched = Perched(node: node, windowID: s.windowID, localX: np.x - s.ledgeX, yOffset: s.top - s.baseY)
                perched.onDislodge = { [weak self, weak scene] in
                    guard let self, let scene, let pp = self.perch else { return }
                    scene.unperch(pp)
                    self.perch = nil
                    self.vel = CGVector(dx: .random(in: -80...80), dy: 120)
                }
                perch = perched
                scene.perch(perched)
            } else if np.y < -40 {
                node.removeFromParent()
                return false
            } else {
                node.position = np
            }
        }
        if age > 15 * 60 && !opened {     // nobody opened it: quietly vanish
            if let p = perch { scene.unperch(p) }
            node.run(.sequence([.fadeOut(withDuration: 1), .removeFromParent()]))
            return false
        }
        return true
    }

    func click(at p: CGPoint, count: Int, in scene: SnowScene) -> Bool {
        guard !opened, !node.isHidden, node.calculateAccumulatedFrame().insetBy(dx: -8, dy: -8).contains(p) else { return false }
        open(in: scene)
        return true
    }

    private func open(in scene: SnowScene) {
        opened = true
        Sound.shared.play(.pop)
        lid.run(.group([.moveBy(x: 14, y: 45, duration: 0.5), .rotate(byAngle: -1.2, duration: 0.5), .fadeOut(withDuration: 0.7)]))
        let colors = [rgb(1, 0.3, 0.3), rgb(1, 0.85, 0.3), rgb(0.4, 0.9, 0.5), rgb(0.5, 0.7, 1), .white]
        for _ in 0..<40 {
            let s = SKSpriteNode(texture: Tex.spark, size: CGSize(width: 10, height: 10))
            s.color = colors.randomElement()!
            s.colorBlendFactor = 1
            s.position = CGPoint(x: 0, y: 22)
            node.addChild(s)
            let a = CGFloat.random(in: 0.3...(CGFloat.pi - 0.3)), d = CGFloat.random(in: 40...120)
            let up = SKAction.moveBy(x: cos(a) * d, y: sin(a) * d, duration: 0.6)
            up.timingMode = .easeOut
            s.run(.sequence([up, .group([.moveBy(x: 0, y: -50, duration: 1), .fadeOut(withDuration: 1)]), .removeFromParent()]))
        }
        let label = SKLabelNode(text: PresentEffect.messages.randomElement()!)
        label.fontName = "Avenir Next Demi Bold"
        label.fontSize = 15
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        let bw = label.frame.width + 24
        let bubble = Shape.rect(CGRect(x: -bw / 2, y: -14, width: bw, height: 28), radius: 14,
                                fill: rgb(0.1, 0.12, 0.2, 0.85), stroke: rgb(1, 1, 1, 0.3))
        bubble.addChild(label)
        // Keep the bubble on screen.
        let worldX = node.position.x
        let shift = min(0, scene.size.width - 10 - (worldX + bw / 2)) + max(0, 10 - (worldX - bw / 2))
        bubble.position = CGPoint(x: shift, y: 62)
        bubble.setScale(0.2)
        bubble.alpha = 0
        node.addChild(bubble)
        bubble.run(.group([.scale(to: 1, duration: 0.25), .fadeIn(withDuration: 0.25)]))
        node.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 0.8), .run { [weak self, weak scene] in
            guard let self else { return }
            if let p = self.perch { scene?.unperch(p) }
            self.node.removeFromParent()
            self.finished = true
        }]))
    }
}
