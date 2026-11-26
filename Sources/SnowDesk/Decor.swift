import AppKit
import SpriteKit

/// Fireplace and little pine trees that live on the desktop layer: above the wallpaper (and the cozy room),
/// below desktop icons and behind every app window, so they never cover your apps or dashboards.
final class DesktopDecor {
    private var window: NSWindow?
    private var scene: DecorScene?

    /// Scene x of the fire on the main screen (for melting snow), when it's lit.
    var fireX: CGFloat? { scene?.fireX }

    func apply(fire: Bool, trees: Bool) {
        if !fire && !trees {
            window?.orderOut(nil)
            window = nil
            scene = nil
            Sound.shared.stopCrackle()
            return
        }
        if window == nil { show() }
        scene?.setFire(fire)
        scene?.setTrees(trees)
    }

    func rebuildForScreenChange(fire: Bool, trees: Bool) {
        window?.orderOut(nil)
        window = nil
        scene = nil
        apply(fire: fire, trees: trees)
    }

    private func show() {
        guard let screen = NSScreen.screens.first else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 2)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        let view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 30
        let s = DecorScene(size: screen.frame.size)
        view.presentScene(s)
        w.contentView = view
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        scene = s
    }

    func snapshot() -> CGImage? {
        guard let view = window?.contentView as? SKView, let s = scene else { return nil }
        return view.texture(from: s, crop: s.frame)?.cgImage()
    }
}

final class DecorScene: SKScene {
    private var fireNode: SKNode?
    private var treesNode: SKNode?
    private(set) var fireX: CGFloat?

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    // MARK: Fireplace (bottom-right corner, small)

    func setFire(_ on: Bool) {
        if on, fireNode == nil {
            let fp = Models3D.fireplace(width: 150)
            let root = SKNode()
            let sprite = SKSpriteNode(texture: fp.texture, size: fp.size)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            root.addChild(sprite)
            func local(_ f: CGPoint) -> CGPoint { CGPoint(x: (f.x - 0.5) * fp.size.width, y: f.y * fp.size.height) }
            let o = fp.opening
            let base = local(CGPoint(x: o.midX, y: o.minY))
            let ow = o.width * fp.size.width, oh = o.height * fp.size.height

            let glow = glowSprite(rgb(1, 0.55, 0.2), size: fp.size.width * 1.4, alpha: 0.12)
            glow.position = CGPoint(x: base.x, y: base.y + oh * 0.4)
            glow.zPosition = -1
            root.addChild(glow)
            let inner = glowSprite(rgb(1, 0.5, 0.15), size: ow * 0.9, alpha: 0.35)
            inner.position = CGPoint(x: base.x, y: base.y + oh * 0.3)
            inner.zPosition = 1
            root.addChild(inner)

            let fire = SKEmitterNode()
            fire.particleTexture = Tex.glow
            fire.particleBirthRate = 55
            fire.particleLifetime = 0.7
            fire.particleLifetimeRange = 0.3
            fire.particlePositionRange = CGVector(dx: ow * 0.6, dy: 2)
            fire.emissionAngle = .pi / 2
            fire.emissionAngleRange = 0.3
            fire.particleSpeed = oh * 0.75
            fire.particleSpeedRange = oh * 0.3
            fire.particleScale = ow / 64 * 0.32
            fire.particleScaleRange = ow / 64 * 0.1
            fire.particleScaleSpeed = -ow / 64 * 0.4
            fire.particleAlpha = 0.6
            fire.particleAlphaSpeed = -1.0
            fire.particleColorBlendFactor = 1
            fire.particleColorSequence = SKKeyframeSequence(
                keyframeValues: [rgb(1, 0.85, 0.45), rgb(1, 0.5, 0.1), rgb(0.85, 0.18, 0.04), rgb(0.3, 0.04, 0.02)],
                times: [0, 0.25, 0.6, 1])
            fire.particleBlendMode = .add
            fire.position = CGPoint(x: base.x, y: base.y + oh * 0.18)
            fire.zPosition = 2
            root.addChild(fire)

            let embers = SKEmitterNode()
            embers.particleTexture = Tex.glow
            embers.particleBirthRate = 3
            embers.particleLifetime = 2.2
            embers.particlePositionRange = CGVector(dx: ow * 0.5, dy: 2)
            embers.emissionAngle = .pi / 2
            embers.emissionAngleRange = 0.5
            embers.particleSpeed = 45
            embers.particleSpeedRange = 20
            embers.particleScale = 0.05
            embers.particleScaleRange = 0.025
            embers.particleAlphaSpeed = -0.4
            embers.particleColor = rgb(1, 0.6, 0.2)
            embers.particleColorBlendFactor = 1
            embers.particleBlendMode = .add
            embers.position = CGPoint(x: base.x, y: base.y + oh * 0.4)
            embers.zPosition = 3
            root.addChild(embers)

            for c in fp.candles {
                let flame = glowSprite(rgb(1, 0.75, 0.3), size: 12)
                flame.position = local(c)
                flame.zPosition = 2
                flame.run(.repeatForever(.sequence([.scale(to: 0.8, duration: .random(in: 0.12...0.2)), .scale(to: 1.1, duration: .random(in: 0.15...0.25))])))
                root.addChild(flame)
            }
            // Gentle flicker of the glow
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.08, duration: 0.3), .fadeAlpha(to: 0.13, duration: 0.25)])))
            inner.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.18), .fadeAlpha(to: 0.4, duration: 0.22)])))

            root.position = CGPoint(x: size.width - fp.size.width / 2 - 24, y: 4)
            root.alpha = 0
            root.run(.fadeIn(withDuration: 0.8))
            addChild(root)
            embers.targetNode = self
            fireNode = root
            fireX = root.position.x
            Sound.shared.startCrackle()
        } else if !on, let n = fireNode {
            fireNode = nil
            fireX = nil
            n.run(.sequence([.fadeOut(withDuration: 1), .removeFromParent()]))
            Sound.shared.stopCrackle()
        }
        if treesNode != nil { setTrees(false); setTrees(true) }     // re-space trees around the fireplace
    }

    // MARK: Small trees (two little groves in the bottom corners)

    func setTrees(_ on: Bool) {
        if on, treesNode == nil {
            let root = SKNode()
            let w = size.width
            let fireLeft = fireNode != nil ? w - 24 - 150 - 8 : w - 16
            // (x, height, variant) — left corner grove and a pair beside the fireplace
            let spots: [(CGFloat, CGFloat, Int)] = [
                (28, 70, 2), (62, 96, 1), (100, 62, 0), (132, 80, 0),
                (fireLeft - 24, 84, 1), (fireLeft - 58, 60, 0),
            ]
            for (i, s) in spots.enumerated() {
                let tex = Models3D.pine(variant: s.2, height: s.1)
                let t = SKSpriteNode(texture: tex, size: CGSize(width: s.1 * 0.62, height: s.1))
                t.anchorPoint = CGPoint(x: 0.5, y: 0.02)
                t.position = CGPoint(x: s.0, y: 4)
                t.zPosition = CGFloat(10 - i) * 0.01 + (s.1 < 70 ? 0.1 : 0)
                root.addChild(t)
                if s.2 == 1 {                                   // a faint twinkle on the lit trees
                    for _ in 0..<5 {
                        let g = glowSprite([rgb(1, 0.75, 0.3), rgb(1, 0.35, 0.3), rgb(0.5, 0.8, 1)].randomElement()!, size: 7)
                        g.position = CGPoint(x: s.0 + .random(in: -s.1 * 0.18...s.1 * 0.18), y: 4 + .random(in: s.1 * 0.2...s.1 * 0.8))
                        g.zPosition = t.zPosition + 0.005
                        g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: .random(in: 0.6...1.4)), .fadeAlpha(to: 0.9, duration: .random(in: 0.6...1.4))])))
                        root.addChild(g)
                    }
                }
                // a little drift of snow at the foot
                let drift = Shape.ellipse(CGRect(x: -s.1 * 0.32, y: -4, width: s.1 * 0.64, height: 10), fill: rgb(0.94, 0.96, 1))
                drift.position = CGPoint(x: s.0, y: 4)
                drift.zPosition = t.zPosition + 0.006
                root.addChild(drift)
            }
            root.alpha = 0
            root.run(.fadeIn(withDuration: 0.8))
            addChild(root)
            treesNode = root
        } else if !on, let n = treesNode {
            treesNode = nil
            n.removeFromParent()
        }
    }
}
