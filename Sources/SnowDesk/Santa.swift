import SpriteKit

/// A sleigh and four reindeer flying across the top of the screen; drops a present on a window.
final class SantaEffect: SceneEffect {
    private let node: SKNode
    private let dir: CGFloat
    private let speed: CGFloat = 250
    private let baseY: CGFloat
    private var x: CGFloat
    private var sparkleTimer: CGFloat = 0
    private var dropX: CGFloat
    private var dropped = false

    init(scene: SnowScene) {
        let w = scene.size.width, h = scene.size.height
        dir = Bool.random() ? 1 : -1
        x = dir > 0 ? -300 : w + 300
        baseY = h * .random(in: 0.72...0.84)
        node = SantaEffect.makeTeam()
        node.xScale = dir
        node.zPosition = 150
        scene.addChild(node)
        // Aim the present at a visible window when there is one.
        let targets = scene.visibleWindows.filter {
            $0.rect.minX > 0 && $0.rect.maxX < w && $0.rect.maxY < h - 30 && $0.rect.width > 160 &&
                $0.pile.exposed.filter { $0 }.count * 2 > $0.pile.count      // top edge mostly visible
        }
        if let t = targets.randomElement() {
            dropX = t.rect.minX + t.rect.width * .random(in: 0.25...0.75) + dir * 60
        } else {
            dropX = .random(in: (w * 0.2)...(w * 0.8))
        }
    }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        x += dir * speed * dt
        let y = baseY + sin(x * 0.007) * 26
        node.position = CGPoint(x: x, y: y)
        node.zRotation = cos(x * 0.007) * 0.18 * dir

        sparkleTimer -= dt
        if sparkleTimer <= 0 {
            sparkleTimer = 0.035
            let s = SKSpriteNode(texture: Tex.spark, size: CGSize(width: 12, height: 12))
            s.color = Bool.random() ? rgb(1, 0.9, 0.5) : .white
            s.colorBlendFactor = 1
            s.blendMode = .add
            s.position = CGPoint(x: x - dir * 55, y: y + .random(in: -4...14))
            s.zPosition = 149
            scene.addChild(s)
            s.run(.sequence([.group([.moveBy(x: .random(in: -10...10), y: -.random(in: 20...60), duration: 1.3),
                                     .fadeOut(withDuration: 1.3), .scale(to: 0.2, duration: 1.3)]), .removeFromParent()]))
        }

        if !dropped && (dir > 0 ? x >= dropX : x <= dropX) {
            dropped = true
            scene.add(PresentEffect(at: CGPoint(x: x - dir * 10, y: y), vx: dir * 60, scene: scene))
        }

        if (dir > 0 && x > scene.size.width + 320) || (dir < 0 && x < -320) {
            node.removeFromParent()
            return false
        }
        return true
    }

    /// Sleigh, Santa and reindeer drawn with shapes, facing right.
    static func makeTeam() -> SKNode {
        let root = SKNode()
        let red = rgb(0.80, 0.10, 0.12), gold = rgb(0.95, 0.78, 0.30), brown = rgb(0.50, 0.32, 0.17)

        // Harness
        root.addChild(Shape.line([CGPoint(x: 38, y: 18), CGPoint(x: 80, y: 16), CGPoint(x: 124, y: 18), CGPoint(x: 168, y: 20), CGPoint(x: 212, y: 22)],
                                 color: gold, width: 1.2))
        // Reindeer
        for i in 0..<4 {
            let deer = SKNode()
            deer.position = CGPoint(x: 70 + CGFloat(i) * 44, y: 6 + CGFloat(i) * 1.5)
            for (lx, delay) in [(-10.0, 0.0), (-6.0, 0.12), (7.0, 0.06), (11.0, 0.18)] {
                let leg = Shape.rect(CGRect(x: -1, y: -11, width: 2.4, height: 12), radius: 1, fill: brown.blended(withFraction: 0.3, of: .black))
                leg.position = CGPoint(x: lx, y: 3)
                let swing = SKAction.sequence([.rotate(toAngle: 0.6, duration: 0.18), .rotate(toAngle: -0.5, duration: 0.18)])
                leg.run(.sequence([.wait(forDuration: delay), .repeatForever(swing)]))
                deer.addChild(leg)
            }
            deer.addChild(Shape.ellipse(CGRect(x: -15, y: 0, width: 30, height: 13), fill: brown))
            deer.addChild(Shape.ellipse(CGRect(x: -18, y: 6, width: 6, height: 5), fill: rgb(0.95, 0.92, 0.85)))   // tail
            deer.addChild(Shape.line([CGPoint(x: 10, y: 8), CGPoint(x: 16, y: 20)], color: brown, width: 5))
            deer.addChild(Shape.ellipse(CGRect(x: 12, y: 17, width: 13, height: 8), fill: brown))
            deer.addChild(Shape.line([CGPoint(x: 15, y: 24), CGPoint(x: 13, y: 33), CGPoint(x: 9, y: 36)], color: rgb(0.85, 0.75, 0.55), width: 1.3))
            deer.addChild(Shape.line([CGPoint(x: 13, y: 30), CGPoint(x: 17, y: 34)], color: rgb(0.85, 0.75, 0.55), width: 1.3))
            deer.addChild(Shape.ellipse(CGRect(x: 19, y: 22, width: 2, height: 2), fill: .black))
            if i == 3 {
                let nose = glowSprite(rgb(1, 0.15, 0.1), size: 16)
                nose.position = CGPoint(x: 25, y: 20)
                nose.run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
                deer.addChild(nose)
                deer.addChild(Shape.ellipse(CGRect(x: 23, y: 18.5, width: 4, height: 4), fill: rgb(1, 0.2, 0.15)))
            }
            root.addChild(deer)
        }
        // Sack
        root.addChild(Shape.ellipse(CGRect(x: -40, y: 14, width: 26, height: 28), fill: rgb(0.58, 0.40, 0.22)))
        // Santa
        root.addChild(Shape.ellipse(CGRect(x: -16, y: 14, width: 24, height: 26), fill: red))
        root.addChild(Shape.ellipse(CGRect(x: -5, y: 38, width: 14, height: 14), fill: rgb(1, 0.84, 0.72)))
        root.addChild(Shape.ellipse(CGRect(x: -4, y: 29, width: 15, height: 15), fill: .white))
        root.addChild(Shape.poly([CGPoint(x: -6, y: 48), CGPoint(x: 10, y: 48), CGPoint(x: -10, y: 62)], fill: red))
        root.addChild(Shape.rect(CGRect(x: -7, y: 46, width: 18, height: 4), radius: 2, fill: .white))
        root.addChild(Shape.ellipse(CGRect(x: -13, y: 59, width: 6, height: 6), fill: .white))
        // Sleigh body
        let body = Shape.poly([CGPoint(x: -44, y: 2), CGPoint(x: 26, y: 2), CGPoint(x: 38, y: 10), CGPoint(x: 42, y: 22),
                               CGPoint(x: 35, y: 27), CGPoint(x: 31, y: 18), CGPoint(x: -28, y: 20), CGPoint(x: -44, y: 32)],
                              fill: red, stroke: gold, line: 1.5)
        root.addChild(body)
        // Runner
        root.addChild(Shape.line([CGPoint(x: -46, y: -6), CGPoint(x: 34, y: -6), CGPoint(x: 44, y: 0), CGPoint(x: 46, y: 7)], color: gold, width: 2.5))
        root.addChild(Shape.line([CGPoint(x: -32, y: -6), CGPoint(x: -32, y: 2)], color: gold, width: 2))
        root.addChild(Shape.line([CGPoint(x: 18, y: -6), CGPoint(x: 18, y: 2)], color: gold, width: 2))
        root.setScale(1.1)
        return root
    }
}

/// A wrapped present. Falls, rests on a window (riding along with it), and opens when clicked.
final class PresentEffect: SceneEffect {
    private let node = SKNode()
    private let lid = SKNode()
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
