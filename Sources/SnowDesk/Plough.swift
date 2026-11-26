import SpriteKit

/// A small 3D snowcat that drives along the bottom of the screen and ploughs the snow.
/// The blade pushes a rolling mound ahead of it, the snow wall in front slumps into the blade,
/// and the excess is thrown off in a spray. `big` is the larger one that digs you out after "Bury my desktop".
final class PloughEffect: SceneEffect {
    private let cat: Snowcat3D
    private let body: SKSpriteNode
    private let frames: [SKTexture]
    private var travelled: CGFloat = 0
    private let shadow: SKSpriteNode
    private let spray = SKEmitterNode()
    private let speed: CGFloat
    private let bladeHeight: CGFloat
    private var x: CGFloat
    private var sprayRate: CGFloat = 0
    private var puffTimer: CGFloat = 0
    private var oldSlope: CGFloat = 1.3
    private(set) var done = false

    init(big: Bool, scene: SnowScene) {
        cat = Snowcat3D(width: big ? 210 : 104)
        speed = big ? 170 : 110
        bladeHeight = big ? 34 : 17
        x = -cat.viewport.width
        oldSlope = scene.ground.maxSlope
        scene.ground.maxSlope = 12          // let the cut walls stand instead of draining into the cleared lane
        frames = cat.frames()
        body = SKSpriteNode(texture: frames[0], size: cat.viewport)
        body.zPosition = 60
        scene.addChild(body)

        shadow = SKSpriteNode(texture: Tex.glow, size: CGSize(width: cat.viewport.width * 0.95, height: cat.viewport.height * 0.18))
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.alpha = 0.35
        shadow.zPosition = 59
        scene.addChild(shadow)

        spray.particleTexture = Tex.glow
        spray.particleBirthRate = 0
        spray.particleLifetime = 1.1
        spray.particleLifetimeRange = 0.4
        spray.particlePositionRange = CGVector(dx: 6, dy: bladeHeight * 0.6)
        spray.emissionAngle = .pi * 0.33
        spray.emissionAngleRange = 0.55
        spray.particleSpeed = big ? 300 : 190
        spray.particleSpeedRange = big ? 120 : 70
        spray.yAcceleration = -900
        spray.particleScale = big ? 0.12 : 0.08
        spray.particleScaleRange = 0.05
        spray.particleAlpha = 0.95
        spray.particleAlphaSpeed = -0.5
        spray.particleColor = .white
        spray.particleColorBlendFactor = 1
        spray.zPosition = 61
        scene.addChild(spray)
        spray.targetNode = scene
    }

    /// Scene x of the blade's front edge.
    private var bladeX: CGFloat { x + cat.viewport.width * (cat.bladeFrontFraction - 0.5) }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        let step = speed * dt
        x += step
        let vp = cat.viewport
        body.position = CGPoint(x: x, y: vp.height * (0.5 - cat.bottomFraction))
        shadow.position = CGPoint(x: x + vp.width * 0.06, y: 2)
        travelled += step
        body.texture = frames[Int(travelled / cat.pointsPerFrame) % frames.count]

        let g = scene.ground!
        let bx = bladeX
        let bh = bladeHeight
        var removed: CGFloat = 0

        // 1. Under and just behind the blade: scraped clean.
        let lo = max(0, Int((bx - vp.width * 0.75) / Pile.colW))
        let hi = min(g.count - 1, Int(bx / Pile.colW))
        if lo <= hi {
            for c in lo...hi {
                let h = g.height(at: c)
                if h > 0.2 { removed += h; g.setHeight(c, 0) }
            }
        }
        // 2. Ahead: the snow wall slumps toward the blade (a slope, not a cliff).
        let ahead = max(0, hi + 1)
        if ahead < g.count {
            for c in ahead..<g.count {
                let d = CGFloat(c) * Pile.colW - bx
                let limit = bh * 0.9 + d * 1.35
                if limit > g.maxHeight { break }
                let h = g.height(at: c)
                if h > limit { removed += h - limit; g.setHeight(c, limit) }
            }
        }
        // 3. Some of it rolls ahead as a mound in front of the blade; the rest is thrown off.
        var keep = removed * 0.5
        var k = ahead
        while keep > 0 && k < min(g.count, ahead + 7) {
            let room = bh * 0.8 * (1 - CGFloat(k - ahead) / 8) - g.height(at: k)
            if room > 0 {
                let add = min(room, keep)
                g.setHeight(k, g.height(at: k) + add)
                keep -= add
            }
            k += 1
        }
        let thrown = removed - (removed * 0.5 - keep)
        let target = min(420, thrown / max(dt, 0.001) * 0.6)
        sprayRate += (target - sprayRate) * min(1, dt * 8)
        spray.particleBirthRate = sprayRate
        spray.position = CGPoint(x: bx + 2, y: bh * 0.9)

        // Exhaust puffs
        puffTimer -= dt
        if puffTimer <= 0 {
            puffTimer = 0.22
            let puff = SKSpriteNode(texture: Tex.glow, size: CGSize(width: vp.width * 0.08, height: vp.width * 0.08))
            puff.color = rgb(0.6, 0.62, 0.68)
            puff.colorBlendFactor = 1
            puff.alpha = 0.45
            puff.position = CGPoint(x: x - vp.width * 0.2, y: vp.height * 0.62)
            puff.zPosition = 59
            scene.addChild(puff)
            puff.run(.sequence([.group([.moveBy(x: -12, y: vp.height * 0.4, duration: 1.4), .scale(to: 2.4, duration: 1.4),
                                        .fadeOut(withDuration: 1.4)]), .removeFromParent()]))
        }

        if x - vp.width / 2 > scene.size.width + 40 {
            body.removeFromParent()
            shadow.removeFromParent()
            scene.ground.maxSlope = oldSlope
            spray.particleBirthRate = 0
            spray.run(.sequence([.wait(forDuration: 1.5), .removeFromParent()]))
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
