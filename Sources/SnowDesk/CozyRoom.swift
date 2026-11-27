import AppKit
import SpriteKit

enum OrnamentKind: String, CaseIterable {
    case red, gold, blue, silver, bell, cane, star, present

    var title: String {
        switch self {
        case .red: return "Red Bauble"
        case .gold: return "Gold Bauble"
        case .blue: return "Blue Bauble"
        case .silver: return "Silver Bauble"
        case .bell: return "Bell"
        case .cane: return "Candy Cane"
        case .star: return "Star (tree top)"
        case .present: return "Present (under tree)"
        }
    }
}

/// A cozy room with a Christmas tree, shown as a live wallpaper (below desktop icons).
/// "Decorate" lets you click ornaments onto the tree; they're saved.
final class CozyRoom: NSObject, NSWindowDelegate {
    static let themes = ["Pine Cabin", "Blue Hour", "Cranberry Parlor"]

    private var window: NSWindow?
    private var scene: RoomScene?
    private var palette: NSPanel?
    var isShown: Bool { window != nil }

    func show() {
        guard window == nil, let screen = Displays.home else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isOpaque = true
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        let view = FirstClickSKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let s = RoomScene(size: screen.frame.size)
        s.theme = Settings.shared.roomTheme
        view.presentScene(s)
        w.contentView = view
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        scene = s
        Settings.shared.roomShown = true
    }

    func hide() {
        stopDecorating()
        Retire.window(window)
        window = nil
        scene = nil
        Settings.shared.roomShown = false
    }

    func snapshot() -> CGImage? {
        guard let view = window?.contentView as? SKView, let s = scene else { return nil }
        return view.texture(from: s)?.cgImage()
    }

    func testDecorate() -> Int {
        scene?.testDecorate()
        return scene?.ornamentCount ?? -1
    }

    func setTheme(_ i: Int) {
        Settings.shared.roomTheme = i
        scene?.theme = i
        scene?.rebuild()
    }

    func rebuildForScreenChange() {
        guard isShown else { return }
        hide()
        show()
    }

    // MARK: - Decorating

    func startDecorating() {
        show()
        window?.ignoresMouseEvents = false
        // Finder's desktop icons sit above the room and would swallow the clicks, so lift the room while decorating.
        window?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        if palette == nil { palette = makePalette() }
        palette?.center()
        palette?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func stopDecorating() {
        window?.ignoresMouseEvents = true
        window?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        palette?.orderOut(nil)
    }

    private func makePalette() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 360),
                        styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Decorate the Tree"
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.hidesOnDeactivate = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let hint = NSTextField(wrappingLabelWithString: "Pick an ornament, then click on the tree in your desktop.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        for (i, k) in OrnamentKind.allCases.enumerated() {
            let b = NSButton(radioButtonWithTitle: k.title, target: self, action: #selector(pick(_:)))
            b.tag = i
            b.state = i == 0 ? .on : .off
            stack.addArrangedSubview(b)
        }
        let row = NSStackView(views: [
            NSButton(title: "Undo", target: self, action: #selector(undo)),
            NSButton(title: "Clear", target: self, action: #selector(clearAll)),
            NSButton(title: "Done", target: self, action: #selector(stopDecorating)),
        ])
        row.spacing = 6
        stack.addArrangedSubview(row)
        p.contentView = stack
        return p
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSPanel) === palette { stopDecorating() }
    }

    @objc private func pick(_ sender: NSButton) {
        scene?.selected = OrnamentKind.allCases[sender.tag]
    }

    @objc private func undo() { scene?.undo() }

    @objc private func clearAll() { scene?.clearOrnaments() }
}

private final class FirstClickSKView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class RoomScene: SKScene {
    var theme = 0
    var selected: OrnamentKind = .red
    private let ornamentLayer = SKNode()
    private var tiers: [[CGPoint]] = []      // triangles for hit-testing
    private var treeTop = CGPoint.zero
    private var treeX: CGFloat = 0
    private var floorTop: CGFloat = 0
    private var treeHalfWidth: CGFloat = 0

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        rebuild()
    }

    func rebuild() {
        removeAllChildren()
        ornamentLayer.removeAllChildren()
        let w = size.width, h = size.height
        let pal: (wallTop: NSColor, wallBottom: NSColor, wainscot: NSColor, floor: NSColor, rug: NSColor)
        switch theme {
        case 1: pal = (rgb(0.17, 0.23, 0.38), rgb(0.11, 0.15, 0.27), rgb(0.09, 0.12, 0.2), rgb(0.24, 0.17, 0.12), rgb(0.62, 0.56, 0.46))
        case 2: pal = (rgb(0.50, 0.13, 0.17), rgb(0.36, 0.08, 0.11), rgb(0.24, 0.07, 0.08), rgb(0.30, 0.20, 0.12), rgb(0.14, 0.34, 0.24))
        default: pal = (rgb(0.40, 0.25, 0.15), rgb(0.27, 0.16, 0.10), rgb(0.20, 0.12, 0.07), rgb(0.23, 0.14, 0.08), rgb(0.55, 0.12, 0.12))
        }
        backgroundColor = pal.wallBottom

        // Wall
        let wall = SKSpriteNode(texture: Tex.make(4, 256) { ctx, r in
            Tex.linear(ctx, [pal.wallBottom, pal.wallTop], [0, 1], from: .zero, to: CGPoint(x: 0, y: r.maxY))
        }, size: CGSize(width: w, height: h))
        wall.anchorPoint = .zero
        addChild(wall)
        let stripes = CGMutablePath()
        var sx: CGFloat = 0
        while sx < w { stripes.addRect(CGRect(x: sx, y: h * 0.36, width: theme == 0 ? 2 : 18, height: h * 0.64)); sx += theme == 0 ? 64 : 72 }
        addChild(Shape.node(stripes, fill: NSColor.black.withAlphaComponent(theme == 0 ? 0.25 : 0.06)))

        floorTop = h * 0.24
        addChild(Shape.rect(CGRect(x: 0, y: floorTop, width: w, height: h * 0.12), fill: pal.wainscot))
        addChild(Shape.rect(CGRect(x: 0, y: h * 0.355, width: w, height: h * 0.012), fill: pal.wainscot.blended(withFraction: 0.3, of: .white)))
        addChild(Shape.rect(CGRect(x: 0, y: 0, width: w, height: floorTop), fill: pal.floor))
        let planks = CGMutablePath()
        var py: CGFloat = floorTop - 22
        while py > 0 { planks.move(to: CGPoint(x: 0, y: py)); planks.addLine(to: CGPoint(x: w, y: py)); py -= 24 + (floorTop - py) * 0.12 }
        let pl = SKShapeNode(path: planks)
        pl.strokeColor = NSColor.black.withAlphaComponent(0.25)
        addChild(pl)

        // Window with snowy night outside
        let win = CGRect(x: w * 0.10, y: h * 0.44, width: w * 0.26, height: h * 0.42)
        let glass = SKSpriteNode(texture: Tex.make(4, 256) { ctx, r in
            Tex.linear(ctx, [rgb(0.16, 0.22, 0.40), rgb(0.04, 0.06, 0.16)], [0, 1], from: .zero, to: CGPoint(x: 0, y: r.maxY))
        }, size: win.size)
        glass.anchorPoint = .zero
        glass.position = win.origin
        addChild(glass)
        for _ in 0..<40 {
            let st = SKSpriteNode(color: .white, size: CGSize(width: 1.5, height: 1.5))
            st.alpha = .random(in: 0.3...0.9)
            st.position = CGPoint(x: .random(in: win.minX...win.maxX), y: .random(in: (win.midY)...win.maxY))
            addChild(st)
        }
        let moon = glowSprite(rgb(1, 0.97, 0.85), size: win.width * 0.35, alpha: 0.6)
        moon.position = CGPoint(x: win.maxX - win.width * 0.25, y: win.maxY - win.height * 0.2)
        addChild(moon)
        addChild(Shape.ellipse(CGRect(x: moon.position.x - 14, y: moon.position.y - 14, width: 28, height: 28), fill: rgb(1, 0.97, 0.88)))
        let crop = SKCropNode()
        crop.maskNode = SKSpriteNode(color: .white, size: win.size)
        crop.maskNode?.position = CGPoint(x: win.midX, y: win.midY)
        let snow = SKEmitterNode()
        snow.particleTexture = Tex.glow
        snow.particleBirthRate = 40
        snow.particleLifetime = 12
        snow.particlePositionRange = CGVector(dx: win.width * 1.2, dy: 0)
        snow.emissionAngle = -.pi / 2
        snow.emissionAngleRange = 0.3
        snow.particleSpeed = 35
        snow.particleSpeedRange = 15
        snow.particleScale = 0.08
        snow.particleScaleRange = 0.05
        snow.position = CGPoint(x: win.midX, y: win.maxY + 10)
        snow.advanceSimulationTime(12)
        crop.addChild(snow)
        addChild(crop)
        addChild(Shape.rect(CGRect(x: win.minX, y: win.minY, width: win.width, height: 14), fill: .white))   // snow on the sill outside
        let frame = rgb(0.95, 0.93, 0.88)
        addChild(Shape.rect(win.insetBy(dx: -10, dy: -10), fill: nil, stroke: frame, line: 14))
        addChild(Shape.line([CGPoint(x: win.midX, y: win.minY), CGPoint(x: win.midX, y: win.maxY)], color: frame, width: 7))
        addChild(Shape.line([CGPoint(x: win.minX, y: win.midY), CGPoint(x: win.maxX, y: win.midY)], color: frame, width: 7))
        addChild(Shape.rect(CGRect(x: win.minX - 24, y: win.minY - 26, width: win.width + 48, height: 14), radius: 3, fill: frame))

        // Rug + lamp glow
        addChild(Shape.ellipse(CGRect(x: w * 0.38, y: h * 0.03, width: w * 0.52, height: h * 0.14), fill: pal.rug, stroke: pal.rug.blended(withFraction: 0.3, of: .white), line: 4))
        let lamp = glowSprite(rgb(1, 0.7, 0.35), size: h * 1.1, alpha: 0.12)
        lamp.position = CGPoint(x: w * 0.66, y: h * 0.45)
        addChild(lamp)

        buildTree()
        addChild(ornamentLayer)
        loadOrnaments()
    }

    private func buildTree() {
        let w = size.width, h = size.height
        treeX = w * 0.66
        let base = h * 0.17
        let height = h * 0.6
        treeHalfWidth = height * 0.32
        // Pot and trunk
        addChild(Shape.rect(CGRect(x: treeX - h * 0.018, y: base + h * 0.03, width: h * 0.036, height: h * 0.06), fill: rgb(0.35, 0.22, 0.12)))
        addChild(Shape.poly([CGPoint(x: treeX - h * 0.06, y: base + h * 0.06), CGPoint(x: treeX + h * 0.06, y: base + h * 0.06),
                             CGPoint(x: treeX + h * 0.045, y: base - h * 0.01), CGPoint(x: treeX - h * 0.045, y: base - h * 0.01)],
                            fill: rgb(0.72, 0.16, 0.16)))
        addChild(Shape.rect(CGRect(x: treeX - h * 0.063, y: base + h * 0.05, width: h * 0.126, height: h * 0.015), radius: 2, fill: rgb(0.85, 0.7, 0.3)))
        tiers = []
        let n = 5
        for k in 0..<n {
            let bottom = base + h * 0.075 + CGFloat(k) * height * 0.16
            let top = bottom + height * 0.30
            let half = treeHalfWidth * (1 - CGFloat(k) * 0.17)
            var pts: [CGPoint] = []
            let segs = 8
            for i in 0...segs {
                let u = CGFloat(i) / CGFloat(segs)
                pts.append(CGPoint(x: treeX - half + 2 * half * u, y: bottom + (i % 2 == 0 ? 0 : 7)))
            }
            pts.append(CGPoint(x: treeX, y: top))
            addChild(Shape.poly(pts, fill: rgb(0.09, 0.33, 0.19)))
            addChild(Shape.poly([CGPoint(x: treeX - half, y: bottom), CGPoint(x: treeX, y: bottom + 6), CGPoint(x: treeX, y: top)],
                                fill: rgb(0.16, 0.45, 0.26, 0.55)))
            tiers.append([CGPoint(x: treeX - half, y: bottom), CGPoint(x: treeX + half, y: bottom), CGPoint(x: treeX, y: top)])
            if k == n - 1 { treeTop = CGPoint(x: treeX, y: top) }
        }
        // Garland of gold beads
        for g in 0..<3 {
            let y0 = base + h * 0.13 + CGFloat(g) * height * 0.22
            var x = -1.0 as CGFloat
            while x <= 1 {
                let half = widthAt(y: y0 + x * 18) * 0.92
                let p = CGPoint(x: treeX + x * half, y: y0 + x * 18 - (1 - x * x) * 16)
                let bead = SKShapeNode(circleOfRadius: 2.2)
                bead.fillColor = rgb(0.96, 0.8, 0.35)
                bead.strokeColor = .clear
                bead.position = p
                addChild(bead)
                x += 0.045
            }
        }
        // Little twinkling lights
        for _ in 0..<45 {
            let y = CGFloat.random(in: (base + h * 0.09)...(treeTop.y - 20))
            let half = widthAt(y: y) * 0.85
            guard half > 4 else { continue }
            let l = glowSprite([rgb(1, 0.3, 0.25), rgb(1, 0.85, 0.4), rgb(0.4, 0.7, 1), rgb(0.5, 1, 0.5)].randomElement()!, size: 14)
            l.position = CGPoint(x: treeX + .random(in: -half...half), y: y)
            l.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: .random(in: 0.6...1.6)), .fadeAlpha(to: 1, duration: .random(in: 0.6...1.6))])))
            addChild(l)
        }
    }

    private func widthAt(y: CGFloat) -> CGFloat {
        var best: CGFloat = 0
        for t in tiers {
            let b = t[0].y, top = t[2].y
            guard y >= b, y <= top else { continue }
            best = max(best, (t[1].x - t[0].x) / 2 * (1 - (y - b) / (top - b)))
        }
        return best
    }

    private func onTree(_ p: CGPoint) -> Bool { abs(p.x - treeX) < widthAt(y: p.y) - 6 }

    override func mouseDown(with event: NSEvent) {
        placeSelected(at: event.location(in: self))
    }

    /// Test hook: hang one of every ornament at valid spots.
    func testDecorate() {
        for (i, k) in OrnamentKind.allCases.enumerated() {
            selected = k
            let y = treeTop.y - 60 - CGFloat(i) * (treeTop.y - floorTop) / 10
            placeSelected(at: k == .present ? CGPoint(x: treeX + 40, y: floorTop - 30) : CGPoint(x: treeX + (i % 2 == 0 ? -20 : 20), y: y))
        }
    }

    var ornamentCount: Int { ornamentLayer.children.count }

    private func placeSelected(at p: CGPoint) {
        var spot = p
        switch selected {
        case .star:
            spot = treeTop
            ornamentLayer.children.filter { $0.name == OrnamentKind.star.rawValue }.forEach { $0.removeFromParent() }
            var list = Settings.shared.ornaments
            list.removeAll { ($0["k"] as? String) == OrnamentKind.star.rawValue }
            Settings.shared.ornaments = list
        case .present:
            guard p.y < floorTop, abs(p.x - treeX) < treeHalfWidth * 1.4 else { return }
        default:
            guard onTree(p) else { return }
        }
        place(selected, at: spot, animated: true)
        var list = Settings.shared.ornaments
        // Saved relative to the tree (in screen heights) so ornaments stay on it on any screen shape.
        list.append(["k": selected.rawValue, "dx": (spot.x - treeX) / size.height, "y": spot.y / size.height, "v": 2])
        Settings.shared.ornaments = list
    }

    func undo() {
        var list = Settings.shared.ornaments
        guard !list.isEmpty else { return }
        list.removeLast()
        Settings.shared.ornaments = list
        ornamentLayer.children.last?.removeFromParent()
    }

    func clearOrnaments() {
        Settings.shared.ornaments = []
        ornamentLayer.removeAllChildren()
    }

    private func loadOrnaments() {
        for o in Settings.shared.ornaments {
            guard let k = OrnamentKind(rawValue: o["k"] as? String ?? ""),
                  let y = o["y"] as? Double else { continue }
            let x: CGFloat
            if let dx = o["dx"] as? Double { x = treeX + CGFloat(dx) * size.height }
            else if let fx = o["x"] as? Double { x = CGFloat(fx) * size.width }          // saved by older versions
            else { continue }
            place(k, at: CGPoint(x: x, y: CGFloat(y) * size.height), animated: false)
        }
    }

    private func place(_ k: OrnamentKind, at p: CGPoint, animated: Bool) {
        let n = SKNode()
        n.name = k.rawValue
        n.position = p
        let s = size.height / 1080
        switch k {
        case .red, .gold, .blue, .silver:
            let c: NSColor = [.red: rgb(0.85, 0.12, 0.15), .gold: rgb(0.95, 0.75, 0.25), .blue: rgb(0.2, 0.4, 0.9), .silver: rgb(0.85, 0.87, 0.9)][k]!
            let r = 13 * s
            n.addChild(Shape.line([CGPoint(x: 0, y: r), CGPoint(x: 0, y: r + 8 * s)], color: rgb(0.8, 0.7, 0.4), width: 1))
            n.addChild(Shape.rect(CGRect(x: -3.5 * s, y: r - 2 * s, width: 7 * s, height: 5 * s), radius: 1, fill: rgb(0.85, 0.72, 0.35)))
            let ball = SKSpriteNode(texture: Tex.ball, size: CGSize(width: r * 2, height: r * 2))
            ball.color = c
            ball.colorBlendFactor = 0.85
            n.addChild(ball)
            let shine = Shape.ellipse(CGRect(x: -r * 0.55, y: r * 0.15, width: r * 0.45, height: r * 0.3), fill: NSColor.white.withAlphaComponent(0.6))
            n.addChild(shine)
            n.run(.repeatForever(.sequence([.rotate(toAngle: 0.08, duration: 1.6), .rotate(toAngle: -0.08, duration: 1.6)])))
        case .bell:
            let b = 16 * s
            n.addChild(Shape.poly([CGPoint(x: -b, y: -b * 0.6), CGPoint(x: b, y: -b * 0.6), CGPoint(x: b * 0.55, y: b * 0.1),
                                   CGPoint(x: b * 0.4, y: b * 0.7), CGPoint(x: -b * 0.4, y: b * 0.7), CGPoint(x: -b * 0.55, y: b * 0.1)],
                                  fill: rgb(0.95, 0.78, 0.3), stroke: rgb(0.7, 0.5, 0.15)))
            n.addChild(Shape.ellipse(CGRect(x: -b * 0.2, y: -b * 0.85, width: b * 0.4, height: b * 0.4), fill: rgb(0.7, 0.5, 0.15)))
            n.addChild(Shape.ellipse(CGRect(x: -b * 0.35, y: b * 0.55, width: b * 0.7, height: b * 0.35), fill: rgb(0.8, 0.1, 0.15)))
            n.run(.repeatForever(.sequence([.rotate(toAngle: 0.15, duration: 0.9), .rotate(toAngle: -0.15, duration: 0.9)])))
        case .cane:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -22 * s))
            path.addLine(to: CGPoint(x: 0, y: 8 * s))
            path.addArc(center: CGPoint(x: 7 * s, y: 8 * s), radius: 7 * s, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: 14 * s, y: 3 * s))
            let white = Shape.node(path, fill: nil, stroke: .white, line: 5 * s)
            white.lineCap = .round
            let red = Shape.node(path.copy(dashingWithPhase: 0, lengths: [5 * s, 5 * s]), fill: nil, stroke: rgb(0.85, 0.1, 0.15), line: 5 * s)
            n.addChild(white)
            n.addChild(red)
        case .star:
            let glow = glowSprite(rgb(1, 0.9, 0.5), size: 110 * s, alpha: 0.7)
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 1.2), .fadeAlpha(to: 0.8, duration: 1.2)])))
            n.addChild(glow)
            n.addChild(Shape.node(Shape.star(center: .zero, outer: 30 * s, inner: 13 * s), fill: rgb(1, 0.85, 0.3), stroke: rgb(0.85, 0.6, 0.15), line: 1.5))
            n.position.y += 18 * s
        case .present:
            let colors = [(rgb(0.8, 0.12, 0.15), rgb(0.98, 0.85, 0.35)), (rgb(0.12, 0.5, 0.28), .white), (rgb(0.2, 0.35, 0.75), rgb(0.95, 0.75, 0.3))]
            let (box, rib) = colors.randomElement()!
            let bw = CGFloat.random(in: 40...64) * s, bh = CGFloat.random(in: 32...50) * s
            n.addChild(Shape.rect(CGRect(x: -bw / 2, y: 0, width: bw, height: bh), radius: 2, fill: box))
            n.addChild(Shape.rect(CGRect(x: -4 * s, y: 0, width: 8 * s, height: bh), fill: rib))
            n.addChild(Shape.rect(CGRect(x: -bw / 2, y: bh * 0.45, width: bw, height: 7 * s), fill: rib))
            n.addChild(Shape.ellipse(CGRect(x: -14 * s, y: bh - 2, width: 14 * s, height: 11 * s), fill: rib))
            n.addChild(Shape.ellipse(CGRect(x: 0, y: bh - 2, width: 14 * s, height: 11 * s), fill: rib))
        }
        ornamentLayer.addChild(n)
        if animated {
            n.setScale(0.2)
            n.run(.sequence([.scale(to: 1.15, duration: 0.15), .scale(to: 1, duration: 0.1)]))
            Sound.shared.play(.chime, volume: 0.35)
        }
    }
}
