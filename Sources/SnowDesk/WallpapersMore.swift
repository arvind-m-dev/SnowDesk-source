import AppKit

/// Season, nature and festival wallpapers (all painted in code).
extension Painter {
    // MARK: Helpers

    func sun(_ p: CGPoint, _ r: CGFloat, _ color: CGColor, halo: CGFloat = 6) {
        glow(p, r * halo, color.copy(alpha: 0.35)!)
        glow(p, r * 2.2, color.copy(alpha: 0.6)!)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    func clouds(_ n: Int, from y0: CGFloat, to y1: CGFloat, color: CGColor) {
        for _ in 0..<n {
            let cx = CGFloat.random(in: -100...(W + 100)), cy = CGFloat.random(in: y0...y1)
            let w = CGFloat.random(in: 180...420) * s
            for _ in 0..<9 {
                let r = CGFloat.random(in: 0.18...0.32) * w
                glow(CGPoint(x: cx + .random(in: -w / 2...w / 2), y: cy + .random(in: -r * 0.3...r * 0.4)), r, color)
            }
        }
    }

    /// Round leafy tree.
    func leafTree(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, _ colors: [CGColor]) {
        ctx.setFillColor(c(0.3, 0.2, 0.12))
        ctx.fill(CGRect(x: x - h * 0.035, y: y, width: h * 0.07, height: h * 0.5))
        for k in 0..<10 {
            let r = h * .random(in: 0.16...0.26)
            let px = x + .random(in: -h * 0.24...h * 0.24), py = y + h * 0.55 + .random(in: -h * 0.12...h * 0.25)
            ctx.setFillColor(colors[k % colors.count])
            ctx.fillEllipse(in: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 1.8))
        }
    }

    func bareTree(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineCap(.round)
        func branch(_ p: CGPoint, _ a: CGFloat, _ len: CGFloat, _ wdt: CGFloat, _ depth: Int) {
            guard depth > 0 else { return }
            let q = CGPoint(x: p.x + cos(a) * len, y: p.y + sin(a) * len)
            ctx.setLineWidth(wdt)
            ctx.move(to: p); ctx.addLine(to: q); ctx.strokePath()
            branch(q, a + .random(in: 0.25...0.6), len * 0.72, wdt * 0.65, depth - 1)
            branch(q, a - .random(in: 0.25...0.6), len * 0.72, wdt * 0.65, depth - 1)
        }
        branch(CGPoint(x: x, y: y), .pi / 2, h * 0.38, h * 0.06, 6)
    }

    func flowers(_ n: Int, from y0: CGFloat, to y1: CGFloat, colors: [CGColor]) {
        for _ in 0..<n {
            let p = CGPoint(x: .random(in: 0...W), y: .random(in: y0...y1))
            let r = CGFloat.random(in: 2...5) * s * (1.4 - (p.y - y0) / max(1, y1 - y0))
            ctx.setFillColor(colors.randomElement()!)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    /// Flat water band with a gradient and drifting highlights.
    func water(top: CGFloat, bottom: CGFloat, _ colors: [CGColor], glints: Int, glint: CGColor) {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: bottom, width: W, height: top - bottom))
        gradient(colors, from: top, to: bottom)
        ctx.restoreGState()
        for _ in 0..<glints {
            let y = CGFloat.random(in: bottom...top)
            let w = CGFloat.random(in: 20...140) * s * (0.4 + (top - y) / max(1, top - bottom))
            ctx.setFillColor(glint.copy(alpha: .random(in: 0.15...0.5))!)
            ctx.fill(CGRect(x: .random(in: 0...W), y: y, width: w, height: 1.6 * s))
        }
    }

    func palm(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, lean: CGFloat) {
        let top = CGPoint(x: x + lean * h * 0.35, y: y + h)
        ctx.setStrokeColor(c(0.4, 0.28, 0.16))
        ctx.setLineWidth(h * 0.05)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addQuadCurve(to: top, control: CGPoint(x: x + lean * h * 0.05, y: y + h * 0.6))
        ctx.strokePath()
        for k in 0..<7 {
            let a = CGFloat(k) / 7 * .pi * 1.2 - .pi * 0.1
            let end = CGPoint(x: top.x + cos(a) * h * 0.45, y: top.y + sin(a) * h * 0.18 - h * 0.12)
            ctx.setStrokeColor(c(0.12, 0.42, 0.2))
            ctx.setLineWidth(h * 0.04)
            ctx.move(to: top)
            ctx.addQuadCurve(to: end, control: CGPoint(x: (top.x + end.x) / 2, y: top.y + h * 0.12))
            ctx.strokePath()
        }
    }

    func firework(_ p: CGPoint, _ r: CGFloat, _ color: CGColor) {
        glow(p, r * 1.4, color.copy(alpha: 0.25)!)
        let n = Int.random(in: 28...44)
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi
            let len = r * .random(in: 0.75...1)
            ctx.setStrokeColor(color.copy(alpha: 0.85)!)
            ctx.setLineWidth(1.6 * s)
            ctx.move(to: CGPoint(x: p.x + cos(a) * len * 0.25, y: p.y + sin(a) * len * 0.25))
            ctx.addLine(to: CGPoint(x: p.x + cos(a) * len, y: p.y + sin(a) * len - len * 0.08))
            ctx.strokePath()
            ctx.setFillColor(c(1, 1, 1, 0.9))
            ctx.fillEllipse(in: CGRect(x: p.x + cos(a) * len - 2 * s, y: p.y + sin(a) * len - len * 0.08 - 2 * s, width: 4 * s, height: 4 * s))
        }
    }

    func skyline(base: CGFloat, color: CGColor, lit: CGColor, maxH: CGFloat) {
        var x: CGFloat = 0
        while x < W {
            let bw = CGFloat.random(in: 40...110) * s, bh = CGFloat.random(in: 0.25...1) * maxH
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: x, y: base, width: bw, height: bh))
            var wy = base + 10 * s
            while wy < base + bh - 12 * s {
                var wx = x + 6 * s
                while wx < x + bw - 10 * s {
                    if Int.random(in: 0..<3) == 0 {
                        ctx.setFillColor(lit.copy(alpha: .random(in: 0.5...1))!)
                        ctx.fill(CGRect(x: wx, y: wy, width: 5 * s, height: 7 * s))
                    }
                    wx += 12 * s
                }
                wy += 16 * s
            }
            x += bw + .random(in: 0...6) * s
        }
    }

    func heart(_ p: CGPoint, _ size: CGFloat, _ color: CGColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p.x, y: p.y - size))
        path.addCurve(to: CGPoint(x: p.x, y: p.y + size * 0.4), control1: CGPoint(x: p.x + size * 1.3, y: p.y - size * 0.15), control2: CGPoint(x: p.x + size * 0.9, y: p.y + size * 1.15))
        path.addCurve(to: CGPoint(x: p.x, y: p.y - size), control1: CGPoint(x: p.x - size * 0.9, y: p.y + size * 1.15), control2: CGPoint(x: p.x - size * 1.3, y: p.y - size * 0.15))
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    func birds(_ n: Int, around p: CGPoint, color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(2 * s)
        for _ in 0..<n {
            let q = CGPoint(x: p.x + .random(in: -160...160) * s, y: p.y + .random(in: -60...60) * s)
            let w = CGFloat.random(in: 8...16) * s
            ctx.move(to: CGPoint(x: q.x - w, y: q.y + w * 0.3))
            ctx.addQuadCurve(to: q, control: CGPoint(x: q.x - w * 0.5, y: q.y + w * 0.5))
            ctx.addQuadCurve(to: CGPoint(x: q.x + w, y: q.y + w * 0.3), control: CGPoint(x: q.x + w * 0.5, y: q.y + w * 0.5))
            ctx.strokePath()
        }
    }

    func rainStreaks(_ n: Int, color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(1.2 * s)
        for _ in 0..<n {
            let x = CGFloat.random(in: 0...W), y = CGFloat.random(in: 0...H), l = CGFloat.random(in: 14...30) * s
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x - l * 0.2, y: y - l))
        }
        ctx.strokePath()
    }

    // MARK: Seasons and nature

    func springMeadow() {
        gradient([c(0.55, 0.78, 0.98), c(0.9, 0.95, 1)], from: H, to: H * 0.4)
        sun(CGPoint(x: W * 0.78, y: H * 0.82), 46 * s, c(1, 0.97, 0.8))
        clouds(6, from: H * 0.65, to: H * 0.9, color: c(1, 1, 1, 0.35))
        ridge(base: H * 0.45, amp: H * 0.06, color: c(0.55, 0.72, 0.6), freq: 3)
        ridge(base: H * 0.36, amp: H * 0.05, color: c(0.45, 0.7, 0.4), freq: 4)
        ridge(base: H * 0.25, amp: H * 0.03, color: c(0.42, 0.72, 0.32), freq: 5)
        let blossom = [c(0.98, 0.76, 0.84), c(1, 0.88, 0.92), c(0.95, 0.66, 0.78)]
        for _ in 0..<9 { leafTree(.random(in: 0...W), .random(in: (H * 0.24)...(H * 0.34)), .random(in: 160...260) * s, blossom) }
        flowers(900, from: 0, to: H * 0.25, colors: [c(1, 1, 1), c(1, 0.85, 0.2), c(0.95, 0.4, 0.55), c(0.6, 0.5, 0.95)])
        birds(5, around: CGPoint(x: W * 0.3, y: H * 0.75), color: c(0.2, 0.25, 0.3, 0.7))
    }

    func summerBeach() {
        gradient([c(0.25, 0.55, 0.92), c(0.72, 0.88, 1)], from: H, to: H * 0.4)
        sun(CGPoint(x: W * 0.25, y: H * 0.8), 50 * s, c(1, 0.98, 0.85))
        clouds(4, from: H * 0.6, to: H * 0.85, color: c(1, 1, 1, 0.4))
        water(top: H * 0.42, bottom: H * 0.18, [c(0.15, 0.55, 0.75), c(0.3, 0.78, 0.85)], glints: 260, glint: c(1, 1, 1))
        // Sand with a foamy wave edge
        let path = CGMutablePath()
        path.move(to: .zero)
        var x: CGFloat = 0
        while x <= W + 10 { path.addLine(to: CGPoint(x: x, y: H * 0.2 + 12 * s * sin(x / W * 9))); x += 8 * s }
        path.addLine(to: CGPoint(x: W, y: 0)); path.closeSubpath()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        gradient([c(0.98, 0.9, 0.72), c(0.92, 0.8, 0.58)], from: H * 0.2, to: 0)
        ctx.restoreGState()
        ctx.setStrokeColor(c(1, 1, 1, 0.8)); ctx.setLineWidth(4 * s); ctx.addPath(path); ctx.strokePath()
        palm(W * 0.85, H * 0.05, 380 * s, lean: -0.5)
        palm(W * 0.93, H * 0.02, 300 * s, lean: -0.3)
        palm(W * 0.08, H * 0.03, 330 * s, lean: 0.4)
        birds(4, around: CGPoint(x: W * 0.6, y: H * 0.7), color: c(1, 1, 1, 0.8))
    }

    func autumnForest() {
        gradient([c(0.98, 0.72, 0.45), c(1, 0.9, 0.75)], from: H, to: H * 0.35)
        sun(CGPoint(x: W * 0.5, y: H * 0.5), 60 * s, c(1, 0.85, 0.55))
        ridge(base: H * 0.42, amp: H * 0.06, color: c(0.72, 0.5, 0.38), freq: 3)
        ridge(base: H * 0.33, amp: H * 0.04, color: c(0.62, 0.42, 0.28), freq: 4)
        let leaves = [c(0.92, 0.45, 0.1), c(0.85, 0.25, 0.1), c(0.95, 0.7, 0.18), c(0.7, 0.35, 0.12)]
        for _ in 0..<16 { leafTree(.random(in: 0...W), .random(in: (H * 0.26)...(H * 0.34)), .random(in: 140...220) * s, leaves) }
        ridge(base: H * 0.22, amp: H * 0.02, color: c(0.6, 0.42, 0.2), freq: 5)
        for _ in 0..<8 { leafTree(.random(in: 0...W), .random(in: 0...(H * 0.12)), .random(in: 300...420) * s, leaves) }
        flowers(700, from: 0, to: H * 0.22, colors: leaves)
    }

    func monsoonRiver() {
        gradient([c(0.42, 0.47, 0.52), c(0.66, 0.7, 0.72)], from: H, to: H * 0.45)
        clouds(10, from: H * 0.7, to: H, color: c(0.3, 0.33, 0.38, 0.45))
        ridge(base: H * 0.5, amp: H * 0.07, color: c(0.3, 0.42, 0.36), freq: 3)
        ridge(base: H * 0.4, amp: H * 0.05, color: c(0.2, 0.42, 0.25), freq: 4)
        ridge(base: H * 0.3, amp: H * 0.03, color: c(0.18, 0.46, 0.22), freq: 5)
        // Winding river from the horizon to the front
        let river = CGMutablePath()
        river.move(to: CGPoint(x: W * 0.46, y: H * 0.36))
        river.addCurve(to: CGPoint(x: W * 0.2, y: 0), control1: CGPoint(x: W * 0.7, y: H * 0.25), control2: CGPoint(x: W * 0.05, y: H * 0.15))
        river.addLine(to: CGPoint(x: W * 0.75, y: 0))
        river.addCurve(to: CGPoint(x: W * 0.5, y: H * 0.36), control1: CGPoint(x: W * 0.5, y: H * 0.15), control2: CGPoint(x: W * 0.85, y: H * 0.25))
        river.closeSubpath()
        ctx.saveGState(); ctx.addPath(river); ctx.clip()
        gradient([c(0.55, 0.62, 0.66), c(0.32, 0.4, 0.44)], from: H * 0.36, to: 0)
        ctx.restoreGState()
        let lush = [c(0.1, 0.42, 0.18), c(0.14, 0.5, 0.2), c(0.08, 0.36, 0.15)]
        for _ in 0..<10 { leafTree(.random(in: 0...(W * 0.18)), .random(in: 0...(H * 0.3)), .random(in: 200...340) * s, lush) }
        for _ in 0..<10 { leafTree(.random(in: (W * 0.8)...W), .random(in: 0...(H * 0.3)), .random(in: 200...340) * s, lush) }
        glow(CGPoint(x: W * 0.5, y: H * 0.35), W * 0.4, c(0.85, 0.88, 0.9, 0.18))
        rainStreaks(1400, color: c(0.85, 0.9, 0.95, 0.35))
    }

    func mountainLake() {
        gradient([c(0.36, 0.45, 0.75), c(0.98, 0.78, 0.62)], from: H, to: H * 0.45)
        sun(CGPoint(x: W * 0.62, y: H * 0.5), 34 * s, c(1, 0.9, 0.7), halo: 9)
        ridge(base: H * 0.55, amp: H * 0.2, color: c(0.45, 0.5, 0.65), freq: 2.5, snowCap: true)
        ridge(base: H * 0.47, amp: H * 0.1, color: c(0.32, 0.38, 0.5), freq: 4, snowCap: true)
        water(top: H * 0.42, bottom: 0, [c(0.6, 0.55, 0.65), c(0.2, 0.28, 0.42)], glints: 320, glint: c(1, 0.9, 0.75))
        // Reflected sun path
        for _ in 0..<70 {
            let y = CGFloat.random(in: (H * 0.05)...(H * 0.41))
            ctx.setFillColor(c(1, 0.88, 0.65, .random(in: 0.2...0.6)))
            ctx.fill(CGRect(x: W * 0.62 + .random(in: -60...60) * s * (1.5 - y / H), y: y, width: .random(in: 20...80) * s, height: 2 * s))
        }
        for _ in 0..<12 { pine(.random(in: 0...(W * 0.2)), .random(in: (H * 0.38)...(H * 0.43)), .random(in: 120...220) * s, dark: 0.6) }
        for _ in 0..<12 { pine(.random(in: (W * 0.82)...W), .random(in: (H * 0.38)...(H * 0.43)), .random(in: 120...220) * s, dark: 0.6) }
    }

    func forestStream() {
        gradient([c(0.55, 0.75, 0.6), c(0.85, 0.95, 0.8)], from: H, to: H * 0.4)
        let greens = [c(0.16, 0.42, 0.2), c(0.22, 0.52, 0.24), c(0.12, 0.36, 0.18), c(0.3, 0.6, 0.28)]
        for _ in 0..<26 { leafTree(.random(in: 0...W), .random(in: (H * 0.35)...(H * 0.5)), .random(in: 200...320) * s, greens) }
        ridge(base: H * 0.34, amp: H * 0.02, color: c(0.3, 0.52, 0.25), freq: 5)
        // Light beams through the canopy
        for k in 0..<6 {
            let x = W * (0.15 + CGFloat(k) * 0.14)
            ctx.setFillColor(c(1, 1, 0.85, 0.07))
            ctx.move(to: CGPoint(x: x, y: H)); ctx.addLine(to: CGPoint(x: x + 60 * s, y: H))
            ctx.addLine(to: CGPoint(x: x + 260 * s, y: 0)); ctx.addLine(to: CGPoint(x: x + 120 * s, y: 0)); ctx.fillPath()
        }
        let stream = CGMutablePath()
        stream.move(to: CGPoint(x: W * 0.48, y: H * 0.34))
        stream.addCurve(to: CGPoint(x: W * 0.3, y: 0), control1: CGPoint(x: W * 0.6, y: H * 0.22), control2: CGPoint(x: W * 0.2, y: H * 0.12))
        stream.addLine(to: CGPoint(x: W * 0.62, y: 0))
        stream.addCurve(to: CGPoint(x: W * 0.52, y: H * 0.34), control1: CGPoint(x: W * 0.45, y: H * 0.12), control2: CGPoint(x: W * 0.72, y: H * 0.22))
        stream.closeSubpath()
        ctx.saveGState(); ctx.addPath(stream); ctx.clip()
        gradient([c(0.6, 0.8, 0.85), c(0.25, 0.5, 0.6)], from: H * 0.34, to: 0)
        for _ in 0..<200 {
            ctx.setFillColor(c(1, 1, 1, .random(in: 0.2...0.6)))
            ctx.fill(CGRect(x: .random(in: (W * 0.2)...(W * 0.7)), y: .random(in: 0...(H * 0.34)), width: .random(in: 8...40) * s, height: 1.5 * s))
        }
        ctx.restoreGState()
        for _ in 0..<14 {   // mossy rocks
            let p = CGPoint(x: .random(in: (W * 0.15)...(W * 0.75)), y: .random(in: 0...(H * 0.2)))
            let r = CGFloat.random(in: 14...40) * s
            ctx.setFillColor(c(0.45, 0.45, 0.42)); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.5, width: r * 2, height: r * 1.2))
            ctx.setFillColor(c(0.35, 0.55, 0.25, 0.8)); ctx.fillEllipse(in: CGRect(x: p.x - r * 0.8, y: p.y + r * 0.2, width: r * 1.6, height: r * 0.5))
        }
        flowers(500, from: 0, to: H * 0.3, colors: [c(0.25, 0.55, 0.22), c(0.95, 0.9, 0.4), c(1, 1, 1)])
    }

    // MARK: Festivals

    func halloweenNight() {
        gradient([c(0.12, 0.05, 0.2), c(0.55, 0.22, 0.25)], from: H, to: H * 0.2)
        stars(260, above: H * 0.5)
        sun(CGPoint(x: W * 0.72, y: H * 0.7), 110 * s, c(1, 0.68, 0.25), halo: 4)
        ridge(base: H * 0.25, amp: H * 0.06, color: c(0.1, 0.05, 0.12), freq: 3)
        // Haunted house on the hill
        house(W * 0.18, H * 0.28, 260 * s, wall: c(0.08, 0.05, 0.1), steeple: true, roof: c(0.12, 0.06, 0.14))
        for _ in 0..<5 { bareTree(.random(in: 0...W), .random(in: (H * 0.05)...(H * 0.2)), .random(in: 220...380) * s, color: c(0.06, 0.03, 0.08)) }
        ridge(base: H * 0.08, amp: H * 0.02, color: c(0.07, 0.03, 0.09), freq: 6)
        for _ in 0..<7 {
            let p = CGPoint(x: .random(in: 0...W), y: .random(in: (H * 0.02)...(H * 0.08)))
            let r = CGFloat.random(in: 26...46) * s
            glow(p, r * 3, c(1, 0.55, 0.1, 0.25))
            ctx.setFillColor(c(0.92, 0.48, 0.1)); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.8, width: r * 2, height: r * 1.6))
            ctx.setFillColor(c(1, 0.88, 0.35))
            for ex in [CGFloat(-0.4), 0.4] {
                ctx.move(to: CGPoint(x: p.x + ex * r - r * 0.18, y: p.y + r * 0.1)); ctx.addLine(to: CGPoint(x: p.x + ex * r + r * 0.18, y: p.y + r * 0.1))
                ctx.addLine(to: CGPoint(x: p.x + ex * r, y: p.y + r * 0.4)); ctx.fillPath()
            }
            ctx.fill(CGRect(x: p.x - r * 0.45, y: p.y - r * 0.35, width: r * 0.9, height: r * 0.18))
        }
        birds(9, around: CGPoint(x: W * 0.7, y: H * 0.72), color: c(0.05, 0.02, 0.06))
    }

    func diwaliNight() {
        gradient([c(0.04, 0.05, 0.2), c(0.2, 0.1, 0.32)], from: H, to: H * 0.2)
        stars(300, above: H * 0.4)
        let colors = [c(1, 0.75, 0.2), c(1, 0.4, 0.5), c(0.5, 0.85, 1), c(0.75, 1, 0.5), c(1, 0.55, 0.15)]
        for _ in 0..<7 { firework(CGPoint(x: .random(in: (W * 0.1)...(W * 0.9)), y: .random(in: (H * 0.55)...(H * 0.9))), .random(in: 80...160) * s, colors.randomElement()!) }
        // Homes strung with lamps
        for k in 0..<6 {
            let x = W * CGFloat(k) / 6 + 20 * s, w = CGFloat.random(in: 200...280) * s
            house(x, H * 0.12, w, wall: c(0.22, 0.12, 0.2), roof: c(0.45, 0.18, 0.15))
            for j in 0..<14 {
                let p = CGPoint(x: x + w * CGFloat(j) / 13, y: H * 0.12 + w * 0.65 - 4 * s - 10 * s * sin(CGFloat(j) / 13 * .pi))
                glow(p, 10 * s, c(1, 0.8, 0.3, 0.8))
            }
        }
        ctx.setFillColor(c(0.15, 0.08, 0.12)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H * 0.12))
        // Row of diyas
        var x = 30 * s
        while x < W {
            glow(CGPoint(x: x, y: H * 0.06), 34 * s, c(1, 0.65, 0.2, 0.55))
            ctx.setFillColor(c(0.75, 0.33, 0.14)); ctx.fillEllipse(in: CGRect(x: x - 16 * s, y: H * 0.035, width: 32 * s, height: 14 * s))
            ctx.setFillColor(c(1, 0.85, 0.35)); ctx.fillEllipse(in: CGRect(x: x - 4 * s, y: H * 0.05, width: 8 * s, height: 16 * s))
            x += 90 * s
        }
        // Rangoli
        let rc = CGPoint(x: W * 0.5, y: H * 0.06)
        for (i, col) in [c(0.95, 0.25, 0.4), c(1, 0.7, 0.1), c(0.2, 0.7, 0.4), c(0.3, 0.5, 1)].enumerated() {
            let r = (70 - CGFloat(i) * 15) * s
            for k in 0..<12 {
                let a = CGFloat(k) / 12 * 2 * .pi
                ctx.setFillColor(col)
                ctx.fillEllipse(in: CGRect(x: rc.x + cos(a) * r - 9 * s, y: rc.y + sin(a) * r * 0.35 - 5 * s, width: 18 * s, height: 10 * s))
            }
        }
    }

    func newYearFireworks() {
        gradient([c(0.02, 0.03, 0.12), c(0.12, 0.12, 0.3)], from: H, to: H * 0.3)
        stars(200, above: H * 0.5)
        let colors = [c(1, 0.85, 0.3), c(0.4, 0.8, 1), c(1, 0.4, 0.6), c(0.6, 1, 0.5), c(0.85, 0.55, 1)]
        for _ in 0..<11 { firework(CGPoint(x: .random(in: (W * 0.05)...(W * 0.95)), y: .random(in: (H * 0.5)...(H * 0.92))), .random(in: 70...170) * s, colors.randomElement()!) }
        skyline(base: H * 0.22, color: c(0.05, 0.06, 0.12), lit: c(1, 0.85, 0.5), maxH: H * 0.3)
        water(top: H * 0.22, bottom: 0, [c(0.08, 0.09, 0.22), c(0.02, 0.03, 0.1)], glints: 500, glint: c(1, 0.85, 0.55))
        for _ in 0..<40 {   // firework colours in the water
            ctx.setFillColor(colors.randomElement()!.copy(alpha: 0.35)!)
            ctx.fill(CGRect(x: .random(in: 0...W), y: .random(in: 0...(H * 0.2)), width: .random(in: 20...90) * s, height: 2 * s))
        }
    }

    func valentineSunset() {
        gradient([c(0.55, 0.3, 0.6), c(1, 0.55, 0.55), c(1, 0.8, 0.6)], from: H, to: H * 0.35)
        sun(CGPoint(x: W * 0.5, y: H * 0.42), 80 * s, c(1, 0.55, 0.4), halo: 5)
        water(top: H * 0.35, bottom: 0, [c(0.85, 0.5, 0.55), c(0.35, 0.2, 0.4)], glints: 300, glint: c(1, 0.85, 0.7))
        for _ in 0..<60 {
            ctx.setFillColor(c(1, 0.8, 0.65, .random(in: 0.2...0.6)))
            ctx.fill(CGRect(x: W * 0.5 + .random(in: -90...60) * s, y: .random(in: (H * 0.05)...(H * 0.34)), width: .random(in: 20...70) * s, height: 2 * s))
        }
        for _ in 0..<22 {
            heart(CGPoint(x: .random(in: 0...W), y: .random(in: (H * 0.45)...(H * 0.95))), .random(in: 8...30) * s,
                  [c(1, 0.4, 0.55, 0.6), c(1, 0.7, 0.8, 0.5), c(0.95, 0.25, 0.4, 0.55)].randomElement()!)
        }
        palm(W * 0.9, 0, 360 * s, lean: -0.4)
    }
}
