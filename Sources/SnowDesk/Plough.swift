import SpriteKit

/// A little snowcat that drives along the bottom of the screen and ploughs the snow away.
/// `big` is the giant version used to dig you out after "Bury my desktop".
final class PloughEffect: SceneEffect {
    private let node: SKNode
    private let scale: CGFloat
    private let speed: CGFloat
    private var x: CGFloat
    private var puffTimer: CGFloat = 0
    private var carried: CGFloat = 0
    private let beacon: SKSpriteNode
    private(set) var done = false

    init(big: Bool, scene: SnowScene) {
        scale = big ? 3.2 : 1
        speed = big ? 240 : 150
        x = -60 * scale
        let n = SKNode()
        let orange = rgb(0.96, 0.55, 0.10), dark = rgb(0.18, 0.18, 0.2)
        n.addChild(Shape.rect(CGRect(x: -40, y: 0, width: 80, height: 16), radius: 8, fill: dark))
        for wx in [-30.0, -10.0, 10.0, 30.0] {
            let wheel = Shape.ellipse(CGRect(x: -5, y: -5, width: 10, height: 10), fill: rgb(0.45, 0.45, 0.48), stroke: rgb(0.3, 0.3, 0.32))
            wheel.position = CGPoint(x: wx, y: 8)
            wheel.addChild(Shape.line([CGPoint(x: -4, y: 0), CGPoint(x: 4, y: 0)], color: rgb(0.3, 0.3, 0.32), width: 1.2))
            wheel.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.8)))
            n.addChild(wheel)
        }
        n.addChild(Shape.rect(CGRect(x: -34, y: 14, width: 60, height: 20), radius: 4, fill: orange))
        n.addChild(Shape.rect(CGRect(x: -28, y: 32, width: 32, height: 22), radius: 4, fill: orange))
        n.addChild(Shape.rect(CGRect(x: -24, y: 36, width: 24, height: 14), radius: 2, fill: rgb(0.70, 0.85, 0.96)))
        n.addChild(Shape.rect(CGRect(x: -36, y: 33, width: 3, height: 14), fill: dark))     // exhaust
        n.addChild(Shape.line([CGPoint(x: 24, y: 16), CGPoint(x: 36, y: 14)], color: dark, width: 3))
        n.addChild(Shape.poly([CGPoint(x: 32, y: -1), CGPoint(x: 46, y: -3), CGPoint(x: 49, y: 30), CGPoint(x: 38, y: 32), CGPoint(x: 33, y: 22)],
                              fill: rgb(0.78, 0.80, 0.84), stroke: rgb(0.5, 0.52, 0.56)))
        n.addChild(Shape.rect(CGRect(x: -16, y: 54, width: 8, height: 4), radius: 1, fill: rgb(1, 0.7, 0.1)))
        beacon = glowSprite(rgb(1, 0.65, 0.1), size: 26)
        beacon.position = CGPoint(x: -12, y: 57)
        beacon.run(.repeatForever(.sequence([.fadeAlpha(to: 1, duration: 0.25), .fadeAlpha(to: 0.15, duration: 0.25)])))
        n.addChild(beacon)
        n.setScale(scale)
        n.zPosition = 60
        node = n
        scene.addChild(n)
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        x += speed * dt
        node.position = CGPoint(x: x, y: 0)

        // Blade: clear the ground in front and throw the snow forward.
        let front = x + 46 * scale
        let ground = scene.ground!
        let lo = Int((front - 12 * scale) / Pile.colW), hi = Int((front + 2) / Pile.colW)
        var spawned = 0
        let perChunk: CGFloat = scale > 1 ? 9 : 2.5
        if lo <= hi {
            for c in max(0, lo)...max(0, min(ground.count - 1, hi)) where c < ground.count {
                let h = ground.height(at: c)
                guard h > 0.3 else { continue }
                carried += h
                ground.setHeight(c, 0)
                while carried > perChunk && spawned < (scale > 1 ? 18 : 8) {
                    carried -= perChunk
                    spawned += 1
                    let p = CGPoint(x: front + .random(in: 0...8), y: .random(in: 0...min(h, 50 * scale)))
                    scene.spawnChunk(at: p, vx: speed * .random(in: 0.6...1.6), vy: -.random(in: 180...420) * (scale > 1 ? 1.4 : 1))
                }
            }
        }
        if carried > perChunk * 20 { carried = perChunk * 20 }

        puffTimer -= dt
        if puffTimer <= 0 {
            puffTimer = 0.18
            let puff = SKSpriteNode(texture: Tex.glow, size: CGSize(width: 10 * scale, height: 10 * scale))
            puff.color = rgb(0.6, 0.6, 0.65)
            puff.colorBlendFactor = 1
            puff.alpha = 0.5
            puff.position = CGPoint(x: x - 35 * scale, y: 48 * scale)
            puff.zPosition = 59
            scene.addChild(puff)
            puff.run(.sequence([.group([.moveBy(x: -20, y: 40 * scale, duration: 1.4), .scale(to: 2.5, duration: 1.4),
                                        .fadeOut(withDuration: 1.4)]), .removeFromParent()]))
        }

        if x > scene.size.width + 80 * scale {
            node.removeFromParent()
            done = true
            return false
        }
        return true
    }
}

/// Heavy snow fills the screen from the bottom up, then a giant plough digs you out.
final class BuryEffect: SceneEffect {
    private enum Phase { case filling, holding, digging }
    private var phase = Phase.filling
    private var timer: CGFloat = 0
    private let originalMax: CGFloat
    private var plough: PloughEffect?
    private let seed = CGFloat.random(in: 0...100)

    init(scene: SnowScene) {
        originalMax = scene.ground.maxHeight
        scene.ground.maxHeight = scene.size.height + 40
        scene.forceSnow = true
        scene.surgeFlakes = 900
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        timer += dt
        let g = scene.ground!
        switch phase {
        case .filling:
            let duration: CGFloat = 16
            let ramp = min(1, timer / 3)
            let rate = (scene.size.height + 40) / (duration - 1.5) * ramp
            // Gentle, slow-moving drifts (low-frequency variation) so it reads as deep snow, not peaks.
            let tf = CGFloat(t)
            for c in 0..<g.count {
                let x = CGFloat(c)
                let n = 0.92 + 0.08 * sin(x * 0.011 + seed) + 0.04 * sin(x * 0.031 + tf * 0.3)
                g.add(c, rate * dt * n)
            }
            _ = g.settle(spillsAtEdges: false)
            if timer > duration {
                phase = .holding
                timer = 0
                scene.surgeFlakes = 0
            }
        case .holding:
            if timer > 2 {
                phase = .digging
                let p = PloughEffect(big: true, scene: scene)
                plough = p
                scene.add(p)
            }
        case .digging:
            if plough?.done ?? true {
                g.maxHeight = originalMax
                scene.forceSnow = false
                return false
            }
        }
        return true
    }
}
