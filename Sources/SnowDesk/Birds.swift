import SpriteKit

// MARK: - Bird drawings

/// A small songbird (robin-like) with flapping wings. Faces right; flip with xScale.
final class SongBird {
    let node = SKNode()
    private let wing = SKNode()
    private let farWing = SKNode()
    private let body = SKNode()
    private let tail: SKNode

    init(size s: CGFloat = 1) {
        let palette: [(NSColor, NSColor)] = [
            (rgb(0.42, 0.30, 0.22), rgb(0.93, 0.45, 0.18)),     // robin
            (rgb(0.22, 0.32, 0.55), rgb(0.95, 0.85, 0.75)),     // bluebird
            (rgb(0.35, 0.35, 0.36), rgb(0.85, 0.85, 0.82)),     // sparrow
            (rgb(0.75, 0.12, 0.12), rgb(0.85, 0.2, 0.18)),      // cardinal
            (rgb(0.95, 0.8, 0.15), rgb(0.98, 0.9, 0.35)),       // goldfinch
            (rgb(0.18, 0.18, 0.2), rgb(0.95, 0.95, 0.95)),      // chickadee
        ]
        let kind = Int.random(in: 0..<palette.count)
        let (back, breast) = palette[kind]
        node.setScale(s)
        node.addChild(body)
        // Each part is drawn once per species and shared (see Bake).
        let fw = Shape.ellipse(CGRect(x: -9, y: -2.5, width: 12, height: 5), fill: back.blended(withFraction: 0.4, of: .black))
        farWing.addChild(Bake.sprite(fw, key: "bird\(kind)-farwing"))
        farWing.position = CGPoint(x: 1, y: 7)
        body.addChild(farWing)
        tail = Bake.sprite(Shape.poly([CGPoint(x: -6, y: 3), CGPoint(x: -15, y: 7), CGPoint(x: -14, y: 2)], fill: back.blended(withFraction: 0.25, of: .black)),
                           key: "bird\(kind)-tail")
        body.addChild(tail)
        let torso = SKNode()
        torso.addChild(Shape.ellipse(CGRect(x: -8, y: -1, width: 16, height: 11), fill: back))
        torso.addChild(Shape.ellipse(CGRect(x: -2, y: -1, width: 9, height: 8), fill: breast))
        torso.addChild(Shape.ellipse(CGRect(x: 3, y: 5, width: 9, height: 8), fill: back))                 // head
        torso.addChild(Shape.ellipse(CGRect(x: 8, y: 9, width: 2.2, height: 2.2), fill: rgb(0.05, 0.05, 0.05)))
        torso.addChild(Shape.ellipse(CGRect(x: 8.6, y: 9.9, width: 0.8, height: 0.8), fill: .white))
        torso.addChild(Shape.poly([CGPoint(x: 11.5, y: 8.5), CGPoint(x: 15.5, y: 8), CGPoint(x: 11.5, y: 6.8)], fill: rgb(0.95, 0.75, 0.2)))
        for lx in [CGFloat(-1), 2] {
            torso.addChild(Shape.line([CGPoint(x: lx, y: 0), CGPoint(x: lx, y: -4)], color: rgb(0.35, 0.25, 0.15), width: 1))
        }
        layerInOrder(torso)
        body.addChild(Bake.sprite(torso, key: "bird\(kind)-body"))
        let w = Bake.sprite(Shape.ellipse(CGRect(x: -9, y: -2.5, width: 12, height: 5), fill: back.blended(withFraction: 0.2, of: .black)),
                            key: "bird\(kind)-wing")
        wing.addChild(w)
        wing.position = CGPoint(x: 1, y: 6)
        body.addChild(wing)
        layerInOrder(body)
    }

    /// Wing beat: phase in radians.
    func flap(_ phase: CGFloat) {
        let a = sin(phase)
        wing.zRotation = a * 1.0 + 0.35
        wing.yScale = 0.55 + 0.6 * abs(a)
        farWing.zRotation = a * 0.8 + 0.5
        farWing.isHidden = false
    }

    /// Wings held out, gliding.
    func glide() { wing.zRotation = 0.25; wing.yScale = 1.1; farWing.zRotation = 0.4; farWing.isHidden = false }

    /// Wings spread wide and tail fanned while braking to land.
    func flare(_ phase: CGFloat) {
        wing.zRotation = 0.9 + sin(phase) * 0.5
        wing.yScale = 1.15
        farWing.zRotation = 1.0 + sin(phase) * 0.4
        tail.zRotation = 0.35
    }

    func fold() { wing.zRotation = 0; wing.yScale = 1; farWing.isHidden = true; tail.zRotation = 0 }

    /// Little head-down peck.
    func peck() {
        body.run(.sequence([.rotate(toAngle: -0.35, duration: 0.07), .rotate(toAngle: 0, duration: 0.1),
                            .rotate(toAngle: -0.3, duration: 0.07), .rotate(toAngle: 0, duration: 0.12)]))
    }

    func tailFlick() {
        tail.run(.sequence([.rotate(toAngle: 0.45, duration: 0.06), .rotate(toAngle: 0, duration: 0.15)]))
    }

    /// Quick wing-shake, like settling its feathers.
    func ruffle() {
        wing.run(.sequence([.rotate(toAngle: 0.4, duration: 0.06), .rotate(toAngle: 0, duration: 0.06),
                            .rotate(toAngle: 0.3, duration: 0.06), .rotate(toAngle: 0, duration: 0.08)]))
    }
}

/// A far-away bird silhouette: two thin wings in a shallow "v".
private final class FlockBird {
    let node = SKNode()
    private let left: SKNode
    private let right: SKNode

    init(size raw: CGFloat, color: NSColor) {
        let size = raw.rounded()                    // whole sizes so the baked parts are shared
        let k = "flock\(Int(size))"
        left = Bake.sprite(Shape.line([.zero, CGPoint(x: -size, y: size * 0.15)], color: color, width: max(1.2, size * 0.16)), key: k + "L")
        right = Bake.sprite(Shape.line([.zero, CGPoint(x: size, y: size * 0.15)], color: color, width: max(1.2, size * 0.16)), key: k + "R")
        node.addChild(left)
        node.addChild(right)
        node.addChild(Bake.sprite(Shape.ellipse(CGRect(x: -size * 0.12, y: -size * 0.1, width: size * 0.24, height: size * 0.2), fill: color), key: k + "B"))
    }

    func wings(_ a: CGFloat) { left.zRotation = -a; right.zRotation = a }
}

/// Smooth random wandering: a few slow sine waves with random phases (cheap value noise).
private struct Wander {
    private let f: [CGFloat] = (0..<3).map { _ in .random(in: 0.15...0.9) }
    private let p: [CGFloat] = (0..<3).map { _ in .random(in: 0...(2 * .pi)) }
    func value(_ t: CGFloat) -> CGFloat { (sin(t * f[0] + p[0]) + 0.6 * sin(t * f[1] * 2.3 + p[1]) + 0.35 * sin(t * f[2] * 4.1 + p[2])) / 1.95 }
}

// MARK: - Birds effect

/// Flocks drifting across the sky and songbirds that fly in on curving paths, land on window tops
/// (and on buttons, rows and dividers when Accessibility is allowed), hop about, and take off when you come near.
final class BirdsEffect: SceneEffect, Finishable {
    private final class Member {
        let bird: FlockBird
        var p: CGPoint
        var v: CGVector
        var phase = CGFloat.random(in: 0...6.28)
        let rate = CGFloat.random(in: 9...12)
        var gliding = false
        var switchAt: CGFloat = .random(in: 0.3...1.2)
        let slot: CGPoint
        init(bird: FlockBird, p: CGPoint, v: CGVector, slot: CGPoint) { self.bird = bird; self.p = p; self.v = v; self.slot = slot }
    }
    private final class Flock {
        let root = SKNode()
        var members: [Member] = []
        var lead: CGPoint
        let dir: CGFloat
        let speed: CGFloat
        let wander = Wander()
        var t: CGFloat = 0
        init(lead: CGPoint, dir: CGFloat, speed: CGFloat) { self.lead = lead; self.dir = dir; self.speed = speed }
    }

    private enum Mode { case flying, landing, perched, leaving }
    private final class Visitor {
        let bird: SongBird
        var mode: Mode = .flying
        var p: CGPoint
        var v: CGVector
        var waypoints: [CGPoint] = []
        var landing: Ledge?
        var perch: Perched?
        var phase: CGFloat = 0
        var flapping = true
        var cycleLeft: CGFloat = .random(in: 0.4...1.0)
        let maxSpeed = CGFloat.random(in: 170...260)
        let wander = Wander()
        var t: CGFloat = 0
        var stayUntil: TimeInterval = 0
        var nextAct: TimeInterval = 0
        var facing: CGFloat = 1
        init(bird: SongBird, p: CGPoint, v: CGVector) { self.bird = bird; self.p = p; self.v = v }
    }

    private let root = SKNode()
    private var flocks: [Flock] = []
    private var visitors: [Visitor] = []
    private var nextFlock: TimeInterval = 0
    private var nextVisitor: TimeInterval = 0
    private var finishing = false
    var isFinishing: Bool { finishing }

    init(scene: SnowScene) {
        root.zPosition = 90
        scene.addChild(root)
    }

    func finish() {
        finishing = true
        for v in visitors { takeOff(v, leave: true, scene: root.scene as? SnowScene) }
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        guard dt > 0 else { return true }
        let w = scene.size.width, h = scene.size.height
        if !finishing {
            if nextFlock == 0 { nextFlock = t + .random(in: 3...8) }
            if t > nextFlock {
                nextFlock = t + .random(in: 20...55)
                spawnFlock(w: w, h: h)
            }
            if nextVisitor == 0 { nextVisitor = t + .random(in: 2...6) }
            if t > nextVisitor {
                nextVisitor = t + .random(in: 8...26)
                if visitors.count < 6 { spawnVisitor(scene: scene, t: t) }
            }
        }
        flocks = flocks.filter { stepFlock($0, dt: dt, w: w, h: h) }
        visitors = visitors.filter { step($0, dt: dt, t: t, scene: scene) }
        if finishing && flocks.isEmpty && visitors.isEmpty { root.removeFromParent(); return false }
        return true
    }

    // MARK: Flocks (loose, boids-like)

    private func spawnFlock(w: CGFloat, h: CGFloat) {
        let dir: CGFloat = Bool.random() ? 1 : -1
        let size = CGFloat.random(in: 6...11)
        let f = Flock(lead: CGPoint(x: dir > 0 ? -120 : w + 120, y: .random(in: (h * 0.5)...(h * 0.88))), dir: dir, speed: .random(in: 70...130))
        let color = rgb(0.12, 0.13, 0.17, 0.85)
        for i in 0..<Int.random(in: 4...12) {
            let row = CGFloat((i + 1) / 2), side: CGFloat = i % 2 == 0 ? 1 : -1
            let slot = CGPoint(x: -dir * row * size * .random(in: 2.2...3.4), y: i == 0 ? 0 : side * row * size * .random(in: 1.1...2))
            let b = FlockBird(size: size * .random(in: 0.85...1.15), color: color)
            let m = Member(bird: b, p: CGPoint(x: f.lead.x + slot.x + .random(in: -20...20), y: f.lead.y + slot.y + .random(in: -20...20)),
                           v: CGVector(dx: dir * f.speed, dy: 0), slot: slot)
            f.root.addChild(b.node)
            f.members.append(m)
        }
        root.addChild(f.root)
        flocks.append(f)
    }

    private func stepFlock(_ f: Flock, dt: CGFloat, w: CGFloat, h: CGFloat) -> Bool {
        f.t += dt
        // The leader drifts along a wandering line: gentle climbs, dips and speed changes.
        let sp = f.speed * (1 + 0.25 * f.wander.value(f.t * 0.7))
        f.lead.x += f.dir * sp * dt
        f.lead.y += f.wander.value(f.t * 0.5 + 10) * 40 * dt
        f.lead.y = min(max(f.lead.y, h * 0.4), h * 0.92)
        let center = f.members.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.p.x, y: $0.y + $1.p.y) }
        let n = CGFloat(max(1, f.members.count))
        for m in f.members {
            // Stretchy slots: the formation breathes and reshapes.
            let breathe = 1 + 0.25 * sin(f.t * 0.6 + m.slot.y * 0.1)
            let goal = CGPoint(x: f.lead.x + m.slot.x * breathe, y: f.lead.y + m.slot.y * breathe + sin(f.t * 1.1 + m.phase) * 6)
            var ax = (goal.x - m.p.x) * 1.6 + (center.x / n - m.p.x) * 0.05
            var ay = (goal.y - m.p.y) * 1.6 + (center.y / n - m.p.y) * 0.05
            for o in f.members where o !== m {        // keep a little space
                let dx = m.p.x - o.p.x, dy = m.p.y - o.p.y, d2 = dx * dx + dy * dy
                if d2 < 220 && d2 > 0.01 { ax += dx / d2 * 900; ay += dy / d2 * 900 }
            }
            ax += .random(in: -40...40); ay += .random(in: -40...40)
            m.v.dx += ax * dt; m.v.dy += ay * dt
            m.v.dx *= (1 - 0.9 * dt); m.v.dy *= (1 - 0.9 * dt)
            m.p.x += m.v.dx * dt; m.p.y += m.v.dy * dt
            m.bird.node.position = m.p
            // Flap a while, glide a while; flap harder when climbing.
            m.switchAt -= dt
            if m.switchAt <= 0 {
                m.gliding.toggle()
                m.switchAt = m.gliding ? .random(in: 0.3...1.1) : .random(in: 0.5...1.6)
            }
            if m.gliding && m.v.dy < 25 {
                m.bird.wings(0.12)
            } else {
                m.phase += dt * m.rate * (m.v.dy > 20 ? 1.3 : 1)
                m.bird.wings(sin(m.phase) * 0.6)
            }
        }
        let gone = f.dir > 0 ? f.members.allSatisfy { $0.p.x > w + 60 } : f.members.allSatisfy { $0.p.x < -60 }
        if gone { f.root.removeFromParent() }
        return !gone
    }

    // MARK: Songbirds

    private func spawnVisitor(scene: SnowScene, t: TimeInterval) {
        guard let l = scene.randomLedge(hang: false) else { return }
        let b = SongBird(size: .random(in: 0.9...1.3))
        let fromLeft = Bool.random()
        let w = scene.size.width, h = scene.size.height
        let start = CGPoint(x: fromLeft ? -40 : w + 40, y: h * .random(in: 0.45...0.95))
        let v = Visitor(bird: b, p: start, v: CGVector(dx: (fromLeft ? 1 : -1) * 150, dy: .random(in: -30...30)))
        v.landing = l
        // A curving route: one or two random waypoints before heading in.
        for _ in 0..<Int.random(in: 1...2) {
            v.waypoints.append(CGPoint(x: .random(in: (w * 0.1)...(w * 0.9)), y: .random(in: (h * 0.35)...(h * 0.9))))
        }
        b.node.position = start
        root.addChild(b.node)
        visitors.append(v)
    }

    /// Steering flight: seek the next waypoint (or the landing), wander a little, flap and glide in bursts.
    private func fly(_ v: Visitor, toward goal: CGPoint, arriving: Bool, dt: CGFloat) -> CGFloat {
        v.t += dt
        let d = CGVector(dx: goal.x - v.p.x, dy: goal.y - v.p.y)
        let dist = max(0.001, hypot(d.dx, d.dy))
        var speed = v.maxSpeed * (1 + 0.2 * v.wander.value(v.t))
        if arriving { speed = min(speed, max(40, dist * 2.2)) }
        var want = CGVector(dx: d.dx / dist * speed, dy: d.dy / dist * speed)
        if !arriving || dist > 140 {               // meander
            let a = v.wander.value(v.t * 1.3 + 5) * 0.9
            want = CGVector(dx: want.dx * cos(a) - want.dy * sin(a), dy: want.dx * sin(a) + want.dy * cos(a))
        }
        let k: CGFloat = arriving && dist < 140 ? 6 : 2.4
        v.v.dx += (want.dx - v.v.dx) * min(1, k * dt)
        v.v.dy += (want.dy - v.v.dy) * min(1, k * dt)
        // Flap-glide rhythm (gliding sinks a little).
        v.cycleLeft -= dt
        if v.cycleLeft <= 0 {
            v.flapping.toggle()
            v.cycleLeft = v.flapping ? .random(in: 0.4...1.2) : .random(in: 0.25...0.7)
        }
        let near = arriving && dist < 90
        if near {
            v.phase += dt * 30
            v.bird.flare(v.phase)
        } else if v.flapping || v.v.dy > 40 {
            v.phase += dt * 24
            v.bird.flap(v.phase)
        } else {
            v.v.dy -= 35 * dt
            v.bird.glide()
        }
        v.p.x += v.v.dx * dt
        v.p.y += v.v.dy * dt + (v.flapping ? sin(v.phase) * 0.35 : 0)
        // Face the way it's going (with a little hysteresis), tilt with climb/dive.
        if abs(v.v.dx) > 12 { v.facing = v.v.dx > 0 ? 1 : -1 }
        let n = v.bird.node
        n.position = v.p
        n.xScale = v.facing * abs(n.xScale)
        n.zRotation = max(-0.45, min(0.45, atan2(v.v.dy, abs(v.v.dx)) * 0.6)) * v.facing * (near ? -0.5 : 1)
        return dist
    }

    private func step(_ v: Visitor, dt: CGFloat, t: TimeInterval, scene: SnowScene) -> Bool {
        let n = v.bird.node
        switch v.mode {
        case .flying, .landing:
            guard let l = v.landing, let target = scene.point(of: l) else {
                // Ledge vanished: try another, or wander off.
                if !finishing, let l = scene.randomLedge(hang: false) { v.landing = l } else { takeOff(v, leave: true, scene: scene) }
                return true
            }
            let goal = v.waypoints.first ?? CGPoint(x: target.x, y: target.y + 4)
            let dist = fly(v, toward: goal, arriving: v.waypoints.isEmpty, dt: dt)
            if !v.waypoints.isEmpty {
                if dist < 60 { v.waypoints.removeFirst() }
            } else if dist < 3.5 {
                land(v, on: l, at: target, scene: scene, t: t)
            }
        case .perched:
            guard let p = v.perch else { return true }
            let near = scene.cursorInside && hypot(scene.cursor.x - n.position.x, scene.cursor.y - n.position.y) < 95
            let ledgeGone = v.landing.flatMap { scene.point(of: $0) } == nil
            if near || ledgeGone || n.isHidden || t > v.stayUntil {
                takeOff(v, leave: near ? Bool.random() : Int.random(in: 0..<3) == 0, scene: scene)
                return true
            }
            if t > v.nextAct, var l = v.landing {
                v.nextAct = t + .random(in: 0.6...2.8)
                switch Int.random(in: 0..<10) {
                case 0...2: v.bird.peck()
                case 3: v.bird.tailFlick()
                case 4: v.bird.ruffle()
                case 5, 6:                                   // turn around
                    v.facing *= -1
                    n.xScale = v.facing * abs(n.xScale)
                default:                                     // hop along the ledge
                    let dx = CGFloat.random(in: 5...16) * (Bool.random() ? 1 : -1)
                    let nx = min(max(l.localX + dx, l.minLocalX), l.maxLocalX)
                    v.facing = nx >= l.localX ? 1 : -1
                    n.xScale = v.facing * abs(n.xScale)
                    l.localX = nx
                    v.landing = l
                    p.localX = nx
                    n.run(.sequence([.moveBy(x: 0, y: 5, duration: 0.07), .moveBy(x: 0, y: -5, duration: 0.07)]))
                }
                if let pt = scene.point(of: l), let wid = l.windowID, let w = scene.visibleWindows.first(where: { $0.id == wid }) {
                    p.yOffset = pt.y + 4 - w.rect.maxY
                } else if let pt = scene.point(of: l), l.windowID == nil {
                    p.yOffset = pt.y + 4
                }
            }
        case .leaving:
            let w = scene.size.width, h = scene.size.height
            let goal = v.waypoints.first ?? CGPoint(x: v.facing > 0 ? w + 80 : -80, y: h + 40)
            let dist = fly(v, toward: goal, arriving: false, dt: dt)
            if !v.waypoints.isEmpty && dist < 60 { v.waypoints.removeFirst() }
            if v.p.x < -70 || v.p.x > w + 70 || v.p.y > h + 70 {
                n.removeFromParent()
                return false
            }
        }
        return true
    }

    private func land(_ v: Visitor, on l: Ledge, at target: CGPoint, scene: SnowScene, t: TimeInterval) {
        let n = v.bird.node
        v.bird.fold()
        n.zRotation = 0
        let yOff: CGFloat
        if let wid = l.windowID, let w = scene.visibleWindows.first(where: { $0.id == wid }) { yOff = target.y + 4 - w.rect.maxY } else { yOff = target.y + 4 }
        let p = Perched(node: n, windowID: l.windowID, localX: l.localX, yOffset: yOff)
        p.draggable = false
        p.onDislodge = { [weak self, weak v, weak scene] in if let v { self?.takeOff(v, leave: true, scene: scene) } }
        scene.perch(p)
        v.perch = p
        v.mode = .perched
        v.v = .zero
        v.stayUntil = t + .random(in: 12...55)
        v.nextAct = t + .random(in: 0.3...1.2)
        n.run(.sequence([.scaleX(to: n.xScale * 1.08, y: n.yScale * 0.9, duration: 0.06), .scaleX(to: n.xScale, y: n.yScale, duration: 0.1)]))
    }

    /// Off the perch: either to another ledge (a short hop-flight) or away off screen.
    private func takeOff(_ v: Visitor, leave: Bool, scene: SnowScene?) {
        if case .leaving = v.mode { return }
        if let p = v.perch { scene?.unperch(p) }
        v.perch = nil
        let n = v.bird.node
        n.isHidden = false
        n.removeAllActions()
        v.p = n.position
        v.v = CGVector(dx: v.facing * .random(in: 60...120), dy: .random(in: 120...200))   // spring up
        v.flapping = true
        v.cycleLeft = .random(in: 0.5...1)
        v.waypoints = []
        if !leave && !finishing, let scene, let l = scene.randomLedge(hang: false) {
            v.landing = l
            v.mode = .flying
            if Bool.random() {
                v.waypoints = [CGPoint(x: v.p.x + .random(in: -200...200), y: min(scene.size.height - 40, v.p.y + .random(in: 60...220)))]
            }
        } else {
            v.landing = nil
            v.mode = .leaving
            if let scene {
                v.waypoints = [CGPoint(x: v.p.x + v.facing * .random(in: 150...400), y: min(scene.size.height * 0.95, v.p.y + .random(in: 100...300)))]
            }
        }
    }
}

// MARK: - Butterflies

final class ButterfliesEffect: SceneEffect, Finishable {
    private final class Fly {
        let node = SKNode()
        let left: SKNode, right: SKNode
        var vel = CGVector.zero
        let phase = CGFloat.random(in: 0...6.28)
        init(color: NSColor, key: Int) {
            func wing(_ side: CGFloat) -> SKNode {
                let n = SKNode()
                n.addChild(Shape.ellipse(CGRect(x: side > 0 ? 0 : -10, y: -1, width: 10, height: 9), fill: color))
                n.addChild(Shape.ellipse(CGRect(x: side > 0 ? 0 : -7, y: -7, width: 7, height: 7), fill: color.blended(withFraction: 0.25, of: .white)))
                n.addChild(Shape.ellipse(CGRect(x: side > 0 ? 4 : -7, y: 3, width: 3, height: 3), fill: rgb(0.1, 0.1, 0.1, 0.6)))
                let holder = SKNode()
                holder.addChild(Bake.sprite(n, key: "butterfly\(key)\(side)"))
                return holder
            }
            left = wing(-1); right = wing(1)
            node.addChild(left); node.addChild(right)
            node.addChild(Bake.sprite(Shape.rect(CGRect(x: -1, y: -6, width: 2, height: 12), radius: 1, fill: rgb(0.15, 0.12, 0.1)), key: "butterfly-body"))
        }
    }

    private let root = SKNode()
    private var flies: [Fly] = []
    private var finishing = false
    var isFinishing: Bool { finishing }

    init(scene: SnowScene) {
        root.zPosition = 92
        scene.addChild(root)
        let colors = [rgb(0.98, 0.65, 0.15), rgb(0.35, 0.6, 1), rgb(1, 0.95, 0.4), rgb(0.95, 0.45, 0.75), rgb(1, 1, 1)]
        for _ in 0..<Int.random(in: 4...7) {
            let ci = Int.random(in: 0..<colors.count)
            let f = Fly(color: colors[ci], key: ci)
            f.node.position = CGPoint(x: .random(in: 0...scene.size.width), y: .random(in: 40...(scene.size.height * 0.5)))
            f.node.setScale(.random(in: 0.8...1.3))
            f.node.alpha = 0
            f.node.run(.fadeIn(withDuration: 1))
            root.addChild(f.node)
            flies.append(f)
        }
    }

    func finish() {
        finishing = true
        root.run(.sequence([.fadeOut(withDuration: 1), .removeFromParent()]))
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if finishing { return root.parent != nil }
        let tf = CGFloat(t), w = scene.size.width, h = scene.size.height
        for f in flies {
            let beat = abs(sin(tf * 14 + f.phase))
            f.left.xScale = 0.25 + beat * 0.75
            f.right.xScale = 0.25 + beat * 0.75
            f.vel.dx += .random(in: -90...90) * dt + sin(tf * 0.5 + f.phase) * 10 * dt
            f.vel.dy += .random(in: -90...90) * dt
            let p = f.node.position
            if scene.cursorInside {
                let dx = p.x - scene.cursor.x, dy = p.y - scene.cursor.y, d = max(1, hypot(dx, dy))
                if d < 120 { f.vel.dx += dx / d * 160 * dt; f.vel.dy += dy / d * 160 * dt }
            }
            if p.y > h * 0.6 { f.vel.dy -= 30 * dt }
            if p.y < 30 { f.vel.dy += 30 * dt }
            if p.x < 20 { f.vel.dx += 30 * dt }
            if p.x > w - 20 { f.vel.dx -= 30 * dt }
            let sp = hypot(f.vel.dx, f.vel.dy)
            if sp > 70 { f.vel.dx *= 70 / sp; f.vel.dy *= 70 / sp }
            f.node.position = CGPoint(x: p.x + f.vel.dx * dt, y: p.y + f.vel.dy * dt + sin(tf * 6 + f.phase) * 0.5)
            f.node.zRotation = -f.vel.dx / 250
        }
        return true
    }
}
