import AppKit
import SpriteKit

/// Fireplace and little pine trees that live on the desktop layer: above the wallpaper (and the cozy room),
/// below desktop icons and behind every app window, so they never cover your apps or dashboards.
final class DesktopDecor {
    private var window: NSWindow?
    private var scene: DecorScene?

    /// Scene x of the fire on the main screen (for melting snow), when it's lit.
    var fireX: CGFloat? { scene?.fireX }

    /// trees: 0 off, 1 a few, 2 a small forest along the bottom.
    func apply(fire: Bool, trees: Int, river: Bool = false, season: Season = .winter) {
        if !fire && trees == 0 && !river {
            Retire.window(window)
            window = nil
            scene = nil
            Sound.shared.stopCrackle()
            return
        }
        if window == nil { show() }
        scene?.season = season
        scene?.setRiver(river)
        scene?.setFire(fire)
        scene?.setTrees(trees)
        // Flames and flowing water need a smooth frame rate; twinkling trees are fine at a low rate (saves CPU).
        (window?.contentView as? SKView)?.preferredFramesPerSecond = fire || river ? 30 : 8
    }

    func setHidden(_ hidden: Bool) {
        if hidden { window?.orderOut(nil) } else { window?.orderFrontRegardless() }
    }

    func setPaused(_ paused: Bool) {
        scene?.isPaused = paused
        (window?.contentView as? SKView)?.isPaused = paused
    }

    func rebuildForScreenChange(fire: Bool, trees: Int, river: Bool = false, season: Season = .winter) {
        Retire.window(window)
        window = nil
        scene = nil
        apply(fire: fire, trees: trees, river: river, season: season)
    }

    private func show() {
        guard let screen = Displays.home else { return }
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
    private var treeStyle = 0
    private(set) var fireX: CGFloat?
    private var builtSeason: Season?
    var season: Season = .winter {
        didSet {
            guard season != oldValue else { return }
            if treesNode != nil { let st = treeStyle; setTrees(0); setTrees(st) }
            if riverNode != nil { setRiver(false); setRiver(true) }
        }
    }

    // MARK: River (along the very bottom; trees step back behind it)

    private var riverNode: SKNode?
    private var glints: [(node: SKSpriteNode, speed: CGFloat)] = []
    private let riverH: CGFloat = 34
    private var baseY: CGFloat { riverNode == nil ? 0 : riverH - 6 }

    func setRiver(_ on: Bool) {
        guard on != (riverNode != nil) else { return }
        riverNode?.removeFromParent()
        riverNode = nil
        glints.removeAll()
        if on {
            let frozen = season == .winter
            let r = SKNode()
            r.zPosition = 5
            let top = frozen ? rgb(0.78, 0.88, 0.97) : (season == .monsoon ? rgb(0.35, 0.45, 0.5) : rgb(0.3, 0.6, 0.78))
            let deep = frozen ? rgb(0.6, 0.74, 0.9) : (season == .monsoon ? rgb(0.2, 0.28, 0.32) : rgb(0.1, 0.32, 0.5))
            let tex = Tex.make(4, 64) { ctx, rr in
                Tex.linear(ctx, [top, deep], [0, 1], from: CGPoint(x: 0, y: rr.maxY), to: .zero)
            }
            // Wavy far bank
            let path = CGMutablePath()
            path.move(to: .zero)
            var x: CGFloat = 0
            let seed = CGFloat.random(in: 0...100)
            while x <= size.width + 8 {
                path.addLine(to: CGPoint(x: x, y: riverH + 3 * sin(x * 0.01 + seed) + 1.5 * sin(x * 0.033)))
                x += 8
            }
            path.addLine(to: CGPoint(x: size.width, y: 0))
            path.closeSubpath()
            let crop = SKCropNode()
            crop.maskNode = Shape.node(path, fill: .white)
            let water = SKSpriteNode(texture: tex, size: CGSize(width: size.width, height: riverH + 6))
            water.anchorPoint = .zero
            crop.addChild(water)
            r.addChild(crop)
            let bank = Shape.node(path, fill: nil, stroke: bankColor, line: 4)
            r.addChild(bank)
            // Moving glints (slow sparkles on ice)
            for _ in 0..<Int(size.width / 28) {
                let g = SKSpriteNode(texture: Tex.glow, size: CGSize(width: .random(in: 14...40), height: .random(in: 1.5...3)))
                g.color = .white
                g.colorBlendFactor = 1
                g.alpha = frozen ? .random(in: 0.25...0.6) : .random(in: 0.2...0.5)
                g.position = CGPoint(x: .random(in: 0...size.width), y: .random(in: 3...(riverH - 6)))
                g.zPosition = 1
                r.addChild(g)
                glints.append((g, frozen ? .random(in: 2...6) : .random(in: 22...48)))
            }
            r.alpha = 0
            r.run(.fadeIn(withDuration: 0.8))
            addChild(r)
            riverNode = r
        }
        fireNode?.position.y = 4 + baseY
        if treesNode != nil { let st = treeStyle; setTrees(0); setTrees(st) }     // trees step back behind the water
    }

    private var bankColor: NSColor {
        switch season {
        case .winter: return rgb(0.95, 0.97, 1)
        case .spring, .summer: return rgb(0.35, 0.6, 0.3)
        case .autumn: return rgb(0.55, 0.5, 0.25)
        case .monsoon: return rgb(0.2, 0.4, 0.22)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard !glints.isEmpty else { return }
        let dt: CGFloat = 1.0 / CGFloat(max(1, view?.preferredFramesPerSecond ?? 30))
        for (g, sp) in glints {
            g.position.x += sp * dt
            if g.position.x - g.size.width > size.width { g.position.x = -g.size.width; g.position.y = .random(in: 3...(riverH - 6)) }
            g.alpha = max(0.1, min(0.7, g.alpha + .random(in: -0.04...0.04)))
        }
    }

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

            root.position = CGPoint(x: size.width - fp.size.width / 2 - 24, y: 4 + baseY)
            root.zPosition = 10          // always in front of the forest
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
        if treesNode != nil { let st = treeStyle; setTrees(0); setTrees(st) }     // re-space trees around the fireplace
    }

    // MARK: Trees

    func setTrees(_ style: Int) {
        guard style != treeStyle || (style > 0) != (treesNode != nil) || builtSeason != season else { return }
        treesNode?.removeFromParent()
        treesNode = nil
        treeStyle = style
        builtSeason = season
        guard style > 0 else { return }
        let lights = SKNode()
        let built = style == 2 ? makeForest(lights: lights) : makeFewTrees(lights: lights)
        let root = flatten(built, lights: lights)
        root.alpha = 0
        root.run(.fadeIn(withDuration: 0.8))
        addChild(root)
        treesNode = root
    }

    private var fireSpan: ClosedRange<CGFloat>? {
        guard let fx = fireX else { return nil }
        return (fx - 75 - 10)...(fx + 75 + 10)
    }

    /// The trees never move, so draw them once into a single texture; only the twinkles stay live.
    private func flatten(_ built: SKNode, lights: SKNode) -> SKNode {
        let out = SKNode()
        let band = CGRect(x: 0, y: 0, width: size.width, height: 210)
        if let view, let tex = view.texture(from: built, crop: band) {
            let sprite = SKSpriteNode(texture: tex, size: band.size)
            sprite.anchorPoint = .zero
            out.addChild(sprite)
        } else {
            out.addChild(built)
        }
        lights.zPosition = 1
        out.addChild(lights)
        return out
    }

    private func tree(_ variant: Int, height h: CGFloat, at x: CGFloat, y: CGFloat, tint: CGFloat, z: CGFloat, into root: SKNode, lights: SKNode) {
        let winter = season == .winter
        // Outside winter, about half the trees are leafy ones dressed for the season.
        let leafy = !winter && variant != 1 && Int.random(in: 0..<2) == 0
        let a = leafy ? Models3D.broadleafAspect : Models3D.pineAspect(variant)
        let tex = leafy ? Models3D.broadleaf(season: season, variant: Int.random(in: 0..<3), height: 120)
                        : Models3D.pine(variant: winter ? variant : (variant == 1 ? 0 : variant), height: 120, snowy: winter)
        let t = SKSpriteNode(texture: tex, size: CGSize(width: h * (leafy ? a * 1.05 : a), height: leafy ? h * 0.95 : h))
        t.anchorPoint = CGPoint(x: 0.5, y: 0.02)
        t.position = CGPoint(x: x, y: y)
        t.zPosition = z
        if tint > 0 {                       // distant trees fade into the cold air
            t.color = rgb(0.55, 0.64, 0.82)
            t.colorBlendFactor = tint
        }
        root.addChild(t)
        if variant == 1 && tint < 0.3 && winter {     // a faint twinkle on the lit trees
            for _ in 0..<4 {
                let g = glowSprite([rgb(1, 0.75, 0.3), rgb(1, 0.35, 0.3), rgb(0.5, 0.8, 1)].randomElement()!, size: max(5, h * 0.08))
                g.position = CGPoint(x: x + .random(in: -h * 0.17...h * 0.17), y: y + .random(in: h * 0.2...h * 0.8))
                g.zPosition = z + 0.0005
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: .random(in: 0.6...1.4)), .fadeAlpha(to: 0.9, duration: .random(in: 0.6...1.4))])))
                lights.addChild(g)
            }
        }
    }

    /// Two little groves in the bottom corners.
    private func makeFewTrees(lights: SKNode) -> SKNode {
        let root = SKNode()
        let w = size.width
        let right = (fireSpan?.lowerBound ?? w - 16)
        let spots: [(CGFloat, CGFloat, Int)] = [
            (28, 70, 2), (62, 96, 1), (100, 62, 0), (132, 80, 3),
            (right - 24, 84, 1), (right - 58, 60, 0),
        ]
        for (i, s) in spots.enumerated() {
            let z = CGFloat(i) * 0.01
            tree(s.2, height: s.1, at: s.0, y: 4 + baseY, tint: 0, z: z, into: root, lights: lights)
            let drift = Shape.ellipse(CGRect(x: -s.1 * 0.32, y: -4, width: s.1 * 0.64, height: 10), fill: groundColors[2])
            drift.position = CGPoint(x: s.0, y: 4 + baseY)
            drift.zPosition = z + 0.001
            root.addChild(drift)
        }
        return root
    }

    /// Far, middle and near ground colours for the season.
    private var groundColors: [NSColor] {
        switch season {
        case .winter: return [rgb(0.80, 0.85, 0.94), rgb(0.88, 0.91, 0.97), rgb(0.95, 0.97, 1)]
        case .spring: return [rgb(0.45, 0.62, 0.45), rgb(0.42, 0.66, 0.38), rgb(0.45, 0.72, 0.36)]
        case .summer: return [rgb(0.36, 0.55, 0.36), rgb(0.32, 0.58, 0.3), rgb(0.36, 0.64, 0.28)]
        case .autumn: return [rgb(0.55, 0.5, 0.38), rgb(0.62, 0.52, 0.3), rgb(0.7, 0.55, 0.28)]
        case .monsoon: return [rgb(0.25, 0.42, 0.3), rgb(0.22, 0.46, 0.27), rgb(0.24, 0.5, 0.25)]
        }
    }

    /// A small snowy forest along the whole bottom edge: three rows, the far ones smaller and paler.
    private func makeForest(lights: SKNode) -> SKNode {
        let root = SKNode()
        let w = size.width
        func pick(front: Bool) -> Int {
            let r = Int.random(in: 0..<12)
            if front && r == 0 { return 1 }           // an occasional lit tree up front
            return r < 5 ? 0 : (r < 9 ? 2 : 3)
        }
        func ground(height: CGFloat, color: NSColor, z: CGFloat) {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 0))
            let seed = CGFloat.random(in: 0...100)
            var x: CGFloat = 0
            while x <= w + 8 {
                p.addLine(to: CGPoint(x: x, y: height + 5 * sin(x * 0.012 + seed) + 3 * sin(x * 0.037 + seed * 2)))
                x += 8
            }
            p.addLine(to: CGPoint(x: w, y: 0))
            p.closeSubpath()
            let n = Shape.node(p, fill: color)
            n.zPosition = z
            root.addChild(n)
        }
        // (base y, height range, spacing, tint, z)
        let rows: [(CGFloat, ClosedRange<CGFloat>, ClosedRange<CGFloat>, CGFloat, CGFloat)] = [
            (30, 34...50, 12...22, 0.5, 0.0),
            (16, 46...68, 18...32, 0.25, 0.2),
            (2, 62...100, 30...58, 0.0, 0.4),
        ]
        for (r, row) in rows.enumerated() {
            var x = CGFloat.random(in: -12...8)
            var k = 0
            while x < w + 20 {
                let h = CGFloat.random(in: row.1)
                if r > 0, let span = fireSpan, span.contains(x) { x = span.upperBound + 4; continue }
                tree(pick(front: r == 2), height: h, at: x, y: row.0 + baseY + .random(in: -2...2), tint: row.3,
                     z: row.4 + CGFloat(k % 50) * 0.002, into: root, lights: lights)
                x += CGFloat.random(in: row.2)
                k += 1
            }
            // snowy ground in front of each row's trunks
            ground(height: row.0 + baseY + 6, color: groundColors[r],
                   z: row.4 + 0.15)
        }
        return root
    }
}
