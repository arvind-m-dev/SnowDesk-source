import SpriteKit

/// The screen ices over like a car windshield. Move the pointer to scrape it clear; double-click to thaw.
/// Scraped patches slowly freeze over again.
final class FrostEffect: SceneEffect {
    private let sprite: SKSpriteNode
    private let w: Int, h: Int
    private let cell: CGFloat = 4                    // screen points per frost pixel
    private var base: [UInt8]
    private var threshold: [Float]
    private var scraped: [Float]
    private var out: [UInt8]
    private var progress: Float = 0
    private var thawing = false
    private var dirty = true
    private var lastCursor: CGPoint?
    private var regrowTimer: CGFloat = 0
    private var anyScraped = false

    init(scene: SnowScene) {
        w = max(8, Int(scene.size.width / cell))
        h = max(8, Int(scene.size.height / cell))
        (base, threshold) = FrostEffect.generate(w: w, h: h)
        scraped = Array(repeating: 0, count: w * h)
        out = Array(repeating: 0, count: w * h * 4)
        sprite = SKSpriteNode(color: .clear, size: scene.size)
        sprite.anchorPoint = .zero
        sprite.zPosition = 400
        scene.addChild(sprite)
    }

    func thaw() { thawing = true }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if thawing {
            progress -= Float(dt) / 1.6
            dirty = true
            if progress <= -0.2 {
                sprite.removeFromParent()
                return false
            }
        } else if progress < 1.2 {
            progress = min(1.2, progress + Float(dt) / 5)
            dirty = true
        }

        // Scrape along the pointer's path.
        if scene.cursorInside, progress > 0.2, !thawing {
            let c = scene.cursor
            if let last = lastCursor, hypot(c.x - last.x, c.y - last.y) > 0.5 {
                let steps = max(1, Int(hypot(c.x - last.x, c.y - last.y) / 6))
                for i in 0...steps {
                    let u = CGFloat(i) / CGFloat(steps)
                    stamp(CGPoint(x: last.x + (c.x - last.x) * u, y: last.y + (c.y - last.y) * u))
                }
            }
            lastCursor = c
        } else {
            lastCursor = nil
        }

        // Scraped glass slowly frosts over again.
        regrowTimer += dt
        if anyScraped && regrowTimer > 0.25 {
            let amount = Float(regrowTimer) * 0.02
            regrowTimer = 0
            var still = false
            for i in scraped.indices where scraped[i] > 0 {
                scraped[i] = max(0, scraped[i] - amount)
                if scraped[i] > 0 { still = true }
            }
            anyScraped = still
            dirty = true
        }

        if dirty { redraw() }
        return true
    }

    func click(at p: CGPoint, count: Int, in scene: SnowScene) -> Bool {
        guard count >= 2, !thawing else { return false }
        thawing = true
        return true
    }

    private func stamp(_ p: CGPoint) {
        let cx = Float(p.x / cell), cy = Float(p.y / cell)
        let r: Float = 11
        let x0 = max(0, Int(cx - r)), x1 = min(w - 1, Int(cx + r))
        let y0 = max(0, Int(cy - r)), y1 = min(h - 1, Int(cy + r))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Float(x) - cx, dy = Float(y) - cy
                let d2 = (dx * dx + dy * dy) / (r * r)
                guard d2 < 1 else { continue }
                let i = y * w + x
                let v = min(1, (1 - d2) * 1.6)
                if v > scraped[i] { scraped[i] = v }
            }
        }
        anyScraped = true
        dirty = true
    }

    private func redraw() {
        dirty = false
        let p = progress
        out.withUnsafeMutableBufferPointer { o in
            base.withUnsafeBufferPointer { b in
                for i in 0..<(w * h) {
                    // Image rows are top-down; our arrays are bottom-up.
                    let row = h - 1 - i / w, col = i % w
                    let src = row * w + col
                    let a = max(0, min(1, (p - threshold[src]) * 5)) * (1 - scraped[src])
                    let j = i * 4, k = src * 4
                    o[j] = UInt8(Float(b[k]) * a)
                    o[j + 1] = UInt8(Float(b[k + 1]) * a)
                    o[j + 2] = UInt8(Float(b[k + 2]) * a)
                    o[j + 3] = UInt8(Float(b[k + 3]) * a)
                }
            }
        }
        let data = Data(out) as CFData
        guard let provider = CGDataProvider(data: data),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return }
        sprite.texture = SKTexture(cgImage: img)
        sprite.size = CGSize(width: CGFloat(w) * cell, height: CGFloat(h) * cell)
    }

    // MARK: - Generation

    private static func hash(_ x: Int, _ y: Int) -> Float {
        var v = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        v = (v ^ (v >> 13)) &* 1_274_126_177
        return Float(v & 0xffff) / 65535
    }

    private static func noise(_ x: Float, _ y: Float) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - Float(xi), fy = y - Float(yi)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    /// Returns premultiplied RGBA frost (bottom-up rows) and a freeze-order threshold per pixel (edges first).
    private static func generate(w: Int, h: Int) -> ([UInt8], [Float]) {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var thr = [Float](repeating: 0, count: w * h)
        let half = Float(min(w, h)) / 2
        let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // CGContext memory is top-down; write haze with that in mind.
        for y in 0..<h {
            for x in 0..<w {
                let e = Float(min(x, w - 1 - x, y, h - 1 - y)) / half           // 0 at the edge, 1 in the middle
                let n = noise(Float(x) / 14, Float(y) / 14) * 0.6 + noise(Float(x) / 5, Float(y) / 5) * 0.4
                let edge = 1 - min(1, e / 0.7)
                let a = min(0.85, 0.16 + 0.55 * edge * edge + n * 0.14)
                let memRow = y                     // top-down
                let k = (memRow * w + x) * 4
                buf[k] = UInt8(0.90 * a * 255)
                buf[k + 1] = UInt8(0.95 * a * 255)
                buf[k + 2] = UInt8(1.00 * a * 255)
                buf[k + 3] = UInt8(a * 255)
                let bottomUpRow = h - 1 - y
                thr[bottomUpRow * w + x] = min(1, e) * 0.85 + noise(Float(x) / 9 + 50, Float(y) / 9) * 0.15
            }
        }
        // Fern-like ice crystals.
        ctx.setLineCap(.round)
        func branch(_ p: CGPoint, _ angle: CGFloat, _ len: CGFloat, _ depth: Int) {
            guard depth > 0, len > 2 else { return }
            let end = CGPoint(x: p.x + cos(angle) * len, y: p.y + sin(angle) * len)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18 + 0.1 * CGFloat(depth)).cgColor)
            ctx.setLineWidth(0.35 + 0.25 * CGFloat(depth))
            ctx.move(to: p); ctx.addLine(to: end); ctx.strokePath()
            let n = Int(len / 5)
            guard n > 0 else { return }
            for i in 1...n {
                let u = CGFloat(i) / CGFloat(n + 1)
                let q = CGPoint(x: p.x + cos(angle) * len * u, y: p.y + sin(angle) * len * u)
                let side: CGFloat = i % 2 == 0 ? 1 : -1
                branch(q, angle + side * .random(in: 0.6...1.0), len * (1 - u) * 0.45, depth - 1)
            }
        }
        for _ in 0..<Int(CGFloat(w * h) / 900) {
            // Start near an edge, grow inward.
            let side = Int.random(in: 0..<4)
            var p: CGPoint
            var ang: CGFloat
            switch side {
            case 0: p = CGPoint(x: .random(in: 0...CGFloat(w)), y: .random(in: 0...CGFloat(h) * 0.25)); ang = .pi / 2
            case 1: p = CGPoint(x: .random(in: 0...CGFloat(w)), y: CGFloat(h) - .random(in: 0...CGFloat(h) * 0.25)); ang = -.pi / 2
            case 2: p = CGPoint(x: .random(in: 0...CGFloat(w) * 0.25), y: .random(in: 0...CGFloat(h))); ang = 0
            default: p = CGPoint(x: CGFloat(w) - .random(in: 0...CGFloat(w) * 0.25), y: .random(in: 0...CGFloat(h))); ang = .pi
            }
            branch(p, ang + .random(in: -0.9...0.9), .random(in: 12...40), 3)
        }
        // Copy out as bottom-up rows to match `thr` and scene coordinates.
        var outBuf = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let srcRow = y, dstRow = h - 1 - y
            for x in 0..<(w * 4) { outBuf[dstRow * w * 4 + x] = buf[srcRow * w * 4 + x] }
        }
        return (outBuf, thr)
    }
}
