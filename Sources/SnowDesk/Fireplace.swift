import SpriteKit

/// A stone fireplace by the Dock with flames, rising embers and crackle. Its warmth melts nearby snow.
final class FireplaceEffect: SceneEffect {
    private let root = SKNode()
    private let fire = SKEmitterNode()
    private let embers = SKEmitterNode()
    private let roomGlow: SKSpriteNode
    private let innerGlow: SKSpriteNode
    private var out = false
    private var outTimer: CGFloat = 0
    private var flicker: CGFloat = 0

    init(scene: SnowScene) {
        let stone = rgb(0.42, 0.30, 0.24), mortar = rgb(0.28, 0.20, 0.15), wood = rgb(0.45, 0.26, 0.12)
        roomGlow = glowSprite(rgb(1, 0.55, 0.2), size: 760, alpha: 0.16)
        roomGlow.position = CGPoint(x: 0, y: 80)
        roomGlow.zPosition = -1
        root.addChild(roomGlow)

        root.addChild(Shape.rect(CGRect(x: -115, y: 0, width: 230, height: 180), radius: 6, fill: stone, stroke: mortar, line: 2))
        // Stone courses
        let bricks = CGMutablePath()
        for (row, y) in stride(from: 18.0, to: 180.0, by: 18.0).enumerated() {
            bricks.move(to: CGPoint(x: -113, y: y)); bricks.addLine(to: CGPoint(x: 113, y: y))
            var x = -113.0 + (row % 2 == 0 ? 19 : 0)
            while x < 113 {
                bricks.move(to: CGPoint(x: x, y: y - 18)); bricks.addLine(to: CGPoint(x: x, y: y))
                x += 38
            }
        }
        let b = SKShapeNode(path: bricks)
        b.strokeColor = mortar.withAlphaComponent(0.8)
        b.lineWidth = 1.4
        root.addChild(b)

        // Firebox opening
        let arch = CGMutablePath()
        arch.move(to: CGPoint(x: -76, y: 14))
        arch.addLine(to: CGPoint(x: -76, y: 96))
        arch.addQuadCurve(to: CGPoint(x: 76, y: 96), control: CGPoint(x: 0, y: 165))
        arch.addLine(to: CGPoint(x: 76, y: 14))
        arch.closeSubpath()
        root.addChild(Shape.node(arch, fill: rgb(0.07, 0.04, 0.04), stroke: mortar, line: 3))
        innerGlow = glowSprite(rgb(1, 0.5, 0.15), size: 240, alpha: 0.55)
        innerGlow.position = CGPoint(x: 0, y: 40)
        root.addChild(innerGlow)

        // Logs
        let log1 = Shape.rect(CGRect(x: -55, y: -7, width: 110, height: 14), radius: 7, fill: rgb(0.36, 0.22, 0.12))
        log1.position = CGPoint(x: 0, y: 22)
        log1.zRotation = 0.08
        let log2 = Shape.rect(CGRect(x: -50, y: -6, width: 100, height: 12), radius: 6, fill: rgb(0.30, 0.18, 0.10))
        log2.position = CGPoint(x: 4, y: 30)
        log2.zRotation = -0.12
        root.addChild(log1)
        root.addChild(log2)

        // Flames
        fire.particleTexture = Tex.glow
        fire.particleBirthRate = 120
        fire.particleLifetime = 0.9
        fire.particleLifetimeRange = 0.4
        fire.particlePositionRange = CGVector(dx: 90, dy: 6)
        fire.emissionAngle = .pi / 2
        fire.emissionAngleRange = 0.35
        fire.particleSpeed = 70
        fire.particleSpeedRange = 35
        fire.yAcceleration = 45
        fire.particleScale = 0.5
        fire.particleScaleRange = 0.2
        fire.particleScaleSpeed = -0.55
        fire.particleAlpha = 0.7
        fire.particleAlphaSpeed = -0.9
        fire.particleColorBlendFactor = 1
        fire.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [rgb(1, 0.8, 0.4), rgb(1, 0.5, 0.1), rgb(0.85, 0.18, 0.04), rgb(0.3, 0.04, 0.02)],
            times: [0, 0.25, 0.6, 1])
        fire.particleBlendMode = .add
        fire.position = CGPoint(x: 0, y: 34)
        root.addChild(fire)

        // Embers drift up into the room.
        embers.particleTexture = Tex.glow
        embers.particleBirthRate = 9
        embers.particleLifetime = 3
        embers.particleLifetimeRange = 1.2
        embers.particlePositionRange = CGVector(dx: 70, dy: 4)
        embers.emissionAngle = .pi / 2
        embers.emissionAngleRange = 0.6
        embers.particleSpeed = 80
        embers.particleSpeedRange = 40
        embers.xAcceleration = 6
        embers.particleScale = 0.09
        embers.particleScaleRange = 0.05
        embers.particleAlphaSpeed = -0.3
        embers.particleColor = rgb(1, 0.6, 0.2)
        embers.particleColorBlendFactor = 1
        embers.particleBlendMode = .add
        embers.position = CGPoint(x: 0, y: 60)
        root.addChild(embers)

        // Grate
        for gx in stride(from: -60.0, through: 60.0, by: 20.0) {
            root.addChild(Shape.line([CGPoint(x: gx, y: 14), CGPoint(x: gx, y: 42)], color: rgb(0.12, 0.1, 0.1), width: 3))
        }
        root.addChild(Shape.line([CGPoint(x: -64, y: 40), CGPoint(x: 64, y: 40)], color: rgb(0.12, 0.1, 0.1), width: 3))

        // Hearth and mantel
        root.addChild(Shape.rect(CGRect(x: -125, y: 0, width: 250, height: 14), radius: 3, fill: rgb(0.52, 0.50, 0.48)))
        root.addChild(Shape.rect(CGRect(x: -132, y: 178, width: 264, height: 16), radius: 3, fill: wood, stroke: wood.blended(withFraction: 0.4, of: .black)))
        // Stockings
        for (sx, c) in [(-62.0, rgb(0.8, 0.12, 0.15)), (62.0, rgb(0.12, 0.5, 0.28))] {
            let st = Shape.poly([CGPoint(x: sx - 9, y: 178), CGPoint(x: sx + 9, y: 178), CGPoint(x: sx + 9, y: 146),
                                 CGPoint(x: sx + 20, y: 140), CGPoint(x: sx + 16, y: 130), CGPoint(x: sx - 9, y: 136)], fill: c)
            root.addChild(st)
            root.addChild(Shape.rect(CGRect(x: sx - 11, y: 168, width: 22, height: 10), radius: 3, fill: .white))
        }
        // Candles
        for cx in [-100.0, 100.0] {
            root.addChild(Shape.rect(CGRect(x: cx - 4, y: 194, width: 8, height: 20), radius: 2, fill: rgb(0.96, 0.93, 0.84)))
            let flame = glowSprite(rgb(1, 0.75, 0.3), size: 22)
            flame.position = CGPoint(x: cx, y: 218)
            flame.run(.repeatForever(.sequence([.scale(to: 0.85, duration: 0.15), .scale(to: 1.05, duration: 0.2)])))
            root.addChild(flame)
        }

        root.position = CGPoint(x: scene.size.width - 190, y: 0)
        root.zPosition = 55
        root.alpha = 0
        root.run(.fadeIn(withDuration: 1))
        scene.addChild(root)
        embers.targetNode = scene
        Sound.shared.startCrackle()
    }

    var fireX: CGFloat { root.position.x }

    var isOut: Bool { out }

    func extinguish() {
        guard !out else { return }
        out = true
        fire.particleBirthRate = 0
        embers.particleBirthRate = 0
        Sound.shared.stopCrackle()
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if out {
            outTimer += dt
            root.alpha = max(0, 1 - outTimer / 2)
            if outTimer > 2 { root.removeFromParent(); return false }
            return true
        }
        flicker += (CGFloat.random(in: -1...1) - flicker) * min(1, dt * 12)
        innerGlow.alpha = 0.5 + flicker * 0.12
        roomGlow.alpha = 0.15 + flicker * 0.04
        innerGlow.setScale(1 + flicker * 0.05)

        // Warmth: snow melts, faster the closer it is to the fire.
        let fx = fireX
        for s in scene.visibleWindows {
            let d = hypot(s.rect.midX - fx, s.rect.maxY - 100)
            s.pile.melt(by: (0.25 + 1.8 * max(0, 1 - d / 1100)) * dt)
        }
        scene.ground.melt(by: 0.15 * dt)
        scene.ground.melt(by: 7 * dt, fromX: fx - 210, toX: fx + 210)
        return true
    }
}
