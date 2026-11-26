import SpriteKit

/// Procedurally drawn textures (no image assets).
enum Tex {
    static func make(_ w: CGFloat, _ h: CGFloat, _ draw: @escaping (CGContext, CGRect) -> Void) -> SKTexture {
        let image = NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, r)
            return true
        }
        return SKTexture(image: image)
    }

    static func radial(_ ctx: CGContext, _ r: CGRect, _ colors: [NSColor], _ locs: [CGFloat]) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: colors.map(\.cgColor) as CFArray, locations: locs)!
        let c = CGPoint(x: r.midX, y: r.midY)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: min(r.width, r.height) / 2, options: [])
    }

    static func linear(_ ctx: CGContext, _ colors: [NSColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: colors.map(\.cgColor) as CFArray, locations: locs)!
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Soft round glow, white → transparent. Tint with sprite.color.
    static let glow = make(64, 64) { ctx, r in
        radial(ctx, r, [.white, NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)], [0, 0.35, 1])
    }

    /// Rain streak, transparent at the top.
    static let streak = make(4, 48) { ctx, r in
        linear(ctx, [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.9)], [0, 1],
               from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: 0))
    }

    /// Shaded snowball.
    static let ball = make(64, 64) { ctx, r in
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [NSColor.white.cgColor,
                                                     NSColor(calibratedRed: 0.9, green: 0.93, blue: 0.98, alpha: 1).cgColor,
                                                     NSColor(calibratedRed: 0.68, green: 0.75, blue: 0.86, alpha: 1).cgColor] as CFArray,
                           locations: [0, 0.55, 1])!
        ctx.addEllipse(in: r.insetBy(dx: 1, dy: 1))
        ctx.clip()
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: r.midX - 10, y: r.midY + 12), startRadius: 2,
                               endCenter: CGPoint(x: r.midX, y: r.midY), endRadius: r.width / 2, options: [.drawsAfterEndLocation])
    }

    static let leaves: [SKTexture] = [
        NSColor(calibratedRed: 0.85, green: 0.38, blue: 0.10, alpha: 1),
        NSColor(calibratedRed: 0.75, green: 0.18, blue: 0.10, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.65, blue: 0.15, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.12, alpha: 1),
    ].map { color in
        make(40, 40) { ctx, r in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 20, y: 2))
            p.addCurve(to: CGPoint(x: 20, y: 38), control1: CGPoint(x: 42, y: 10), control2: CGPoint(x: 34, y: 34))
            p.addCurve(to: CGPoint(x: 20, y: 2), control1: CGPoint(x: 6, y: 34), control2: CGPoint(x: -2, y: 10))
            ctx.addPath(p)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            ctx.setStrokeColor(color.blended(withFraction: 0.4, of: .black)!.cgColor)
            ctx.setLineWidth(1.2)
            ctx.move(to: CGPoint(x: 20, y: 0)); ctx.addLine(to: CGPoint(x: 20, y: 34))
            for y in stride(from: 10, through: 28, by: 6) {
                ctx.move(to: CGPoint(x: 20, y: CGFloat(y))); ctx.addLine(to: CGPoint(x: 29, y: CGFloat(y) + 6))
                ctx.move(to: CGPoint(x: 20, y: CGFloat(y))); ctx.addLine(to: CGPoint(x: 11, y: CGFloat(y) + 6))
            }
            ctx.strokePath()
        }
    }

    static let petal = make(24, 32) { ctx, r in
        ctx.addEllipse(in: r.insetBy(dx: 2, dy: 1))
        ctx.clip()
        linear(ctx, [NSColor(calibratedRed: 1, green: 0.86, blue: 0.9, alpha: 1),
                     NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.74, alpha: 1)], [0, 1],
               from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: 0))
    }

    static let cloud = make(512, 220) { ctx, r in
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<26 {
            let rad = CGFloat.random(in: 40...95, using: &rng)
            let x = CGFloat.random(in: (rad + 10)...(r.width - rad - 10), using: &rng)
            let y = CGFloat.random(in: (rad * 0.6)...(r.height - rad * 0.8), using: &rng)
            let cr = CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)
            radial(ctx, cr, [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0)], [0.3, 1])
        }
    }

    /// Four-point sparkle.
    static let spark = make(32, 32) { ctx, r in
        radial(ctx, r.insetBy(dx: 8, dy: 8), [.white, NSColor.white.withAlphaComponent(0)], [0, 1])
        ctx.setFillColor(NSColor.white.cgColor)
        let c = CGPoint(x: 16, y: 16)
        for a in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 2) {
            let p = CGMutablePath()
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + cos(a + 0.18) * 4, y: c.y + sin(a + 0.18) * 4))
            p.addLine(to: CGPoint(x: c.x + cos(a) * 16, y: c.y + sin(a) * 16))
            p.addLine(to: CGPoint(x: c.x + cos(a - 0.18) * 4, y: c.y + sin(a - 0.18) * 4))
            p.closeSubpath()
            ctx.addPath(p)
        }
        ctx.fillPath()
    }
}

/// Small helpers for building vector nodes.
enum Shape {
    static func node(_ path: CGPath, fill: NSColor?, stroke: NSColor? = nil, line: CGFloat = 1) -> SKShapeNode {
        let n = SKShapeNode(path: path)
        n.fillColor = fill ?? .clear
        n.strokeColor = stroke ?? .clear
        n.lineWidth = stroke == nil ? 0 : line
        n.isAntialiased = true
        return n
    }

    static func rect(_ r: CGRect, radius: CGFloat = 0, fill: NSColor?, stroke: NSColor? = nil, line: CGFloat = 1) -> SKShapeNode {
        node(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil), fill: fill, stroke: stroke, line: line)
    }

    static func ellipse(_ r: CGRect, fill: NSColor?, stroke: NSColor? = nil, line: CGFloat = 1) -> SKShapeNode {
        node(CGPath(ellipseIn: r, transform: nil), fill: fill, stroke: stroke, line: line)
    }

    static func poly(_ pts: [CGPoint], fill: NSColor?, stroke: NSColor? = nil, line: CGFloat = 1) -> SKShapeNode {
        let p = CGMutablePath()
        p.addLines(between: pts)
        p.closeSubpath()
        return node(p, fill: fill, stroke: stroke, line: line)
    }

    static func line(_ pts: [CGPoint], color: NSColor, width: CGFloat) -> SKShapeNode {
        let p = CGMutablePath()
        p.addLines(between: pts)
        let n = node(p, fill: nil, stroke: color, line: width)
        n.lineCap = .round
        return n
    }

    static func star(center c: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<10 {
            let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

/// Sprite with a glow texture, additive, tinted.
func glowSprite(_ color: NSColor, size: CGFloat, alpha: CGFloat = 1) -> SKSpriteNode {
    let s = SKSpriteNode(texture: Tex.glow, size: CGSize(width: size, height: size))
    s.color = color
    s.colorBlendFactor = 1
    s.blendMode = .add
    s.alpha = alpha
    return s
}
