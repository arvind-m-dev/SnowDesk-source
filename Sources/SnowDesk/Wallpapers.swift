import AppKit

/// Procedurally painted winter wallpapers, rendered at each screen's full pixel size.
enum Wallpapers {
    static let names = ["Snowy Cabin", "Northern Lights", "Lantern Trail", "Quiet Village"]

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SnowDesk/Wallpapers", isDirectory: true)
    }

    static func apply(_ index: Int, completion: @escaping (Error?) -> Void) {
        let targets = NSScreen.screens.map { s in
            (s, Int(s.frame.width * s.backingScaleFactor), Int(s.frame.height * s.backingScaleFactor))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [(NSScreen, URL)] = []
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for (screen, w, h) in targets {
                    let url = folder.appendingPathComponent("\(names[index].replacingOccurrences(of: " ", with: "-"))-\(w)x\(h).png")
                    if !FileManager.default.fileExists(atPath: url.path) {
                        guard let img = render(index, w: w, h: h),
                              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                            throw NSError(domain: "SnowDesk", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't draw the wallpaper."])
                        }
                        CGImageDestinationAddImage(dest, img, nil)
                        CGImageDestinationFinalize(dest)
                    }
                    results.append((screen, url))
                }
            } catch {
                DispatchQueue.main.async { completion(error) }
                return
            }
            DispatchQueue.main.async {
                do {
                    for (screen, url) in results {
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    }
                    completion(nil)
                } catch {
                    completion(error)
                }
            }
        }
    }

    // MARK: - Painting

    static func render(_ index: Int, w: Int, h: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let P = Painter(ctx: ctx, W: CGFloat(w), H: CGFloat(h))
        switch index {
        case 1: P.northernLights()
        case 2: P.lanternTrail()
        case 3: P.village()
        default: P.cabin()
        }
        return ctx.makeImage()
    }
}

private struct Painter {
    let ctx: CGContext
    let W: CGFloat
    let H: CGFloat
    var s: CGFloat { H / 1080 }

    func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    func gradient(_ colors: [CGColor], from y0: CGFloat, to y1: CGFloat) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    func glow(_ p: CGPoint, _ r: CGFloat, _ color: CGColor) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
    }

    func stars(_ n: Int, above y: CGFloat) {
        for _ in 0..<n {
            let r = CGFloat.random(in: 0.5...1.6) * s
            ctx.setFillColor(c(1, 1, 1, .random(in: 0.3...0.95)))
            ctx.fillEllipse(in: CGRect(x: .random(in: 0...W), y: .random(in: y...H), width: r * 2, height: r * 2))
        }
    }

    func moon(_ p: CGPoint, _ r: CGFloat) {
        glow(p, r * 5, c(0.85, 0.9, 1, 0.25))
        ctx.setFillColor(c(1, 0.98, 0.9))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// A ridge line filled down to y = 0.
    func ridge(base: CGFloat, amp: CGFloat, color: CGColor, freq: CGFloat, snowCap: Bool = false) {
        let seed = CGFloat.random(in: 0...100)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        var pts: [CGPoint] = []
        var x: CGFloat = 0
        while x <= W + 10 {
            let u = x / W * freq
            let y = base + amp * (0.55 * sin(u * 2.1 + seed) + 0.3 * sin(u * 5.3 + seed * 2) + 0.15 * sin(u * 11.7 + seed * 3))
            pts.append(CGPoint(x: x, y: y))
            x += 6 * s
        }
        path.addLines(between: [CGPoint(x: 0, y: 0)] + pts + [CGPoint(x: W, y: 0)])
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        if snowCap {
            ctx.setStrokeColor(c(0.9, 0.93, 1, 0.5))
            ctx.setLineWidth(3 * s)
            ctx.addLines(between: pts)
            ctx.strokePath()
        }
    }

    func snowGround(top: CGFloat) {
        let path = CGMutablePath()
        path.move(to: .zero)
        var x: CGFloat = 0
        let seed = CGFloat.random(in: 0...100)
        while x <= W + 10 {
            path.addLine(to: CGPoint(x: x, y: top + 22 * s * sin(x / W * 5 + seed) + 10 * s * sin(x / W * 13 + seed)))
            x += 8 * s
        }
        path.addLine(to: CGPoint(x: W, y: 0))
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        gradient([c(0.62, 0.68, 0.82), c(0.86, 0.9, 0.97)], from: 0, to: top)
        ctx.restoreGState()
    }

    func pine(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, dark: CGFloat = 1) {
        ctx.setFillColor(c(0.2, 0.13, 0.08))
        ctx.fill(CGRect(x: x - h * 0.03, y: y, width: h * 0.06, height: h * 0.15))
        for k in 0..<4 {
            let b = y + h * (0.1 + CGFloat(k) * 0.2)
            let half = h * (0.32 - CGFloat(k) * 0.065)
            let t = b + h * 0.35
            ctx.setFillColor(c(0.06 * dark, 0.2 * dark, 0.15 * dark))
            ctx.move(to: CGPoint(x: x - half, y: b)); ctx.addLine(to: CGPoint(x: x + half, y: b)); ctx.addLine(to: CGPoint(x: x, y: t))
            ctx.fillPath()
            ctx.setFillColor(c(0.92, 0.95, 1, 0.9))
            ctx.move(to: CGPoint(x: x - half * 0.45, y: t - h * 0.2)); ctx.addLine(to: CGPoint(x: x + half * 0.35, y: t - h * 0.22))
            ctx.addLine(to: CGPoint(x: x, y: t))
            ctx.fillPath()
        }
    }

    func house(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, wall: CGColor, steeple: Bool = false) {
        let h = w * 0.65
        ctx.setFillColor(wall)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
        // Roof with snow
        ctx.setFillColor(c(0.25, 0.14, 0.12))
        ctx.move(to: CGPoint(x: x - w * 0.08, y: y + h)); ctx.addLine(to: CGPoint(x: x + w * 1.08, y: y + h)); ctx.addLine(to: CGPoint(x: x + w / 2, y: y + h + w * 0.45))
        ctx.fillPath()
        ctx.setFillColor(c(0.93, 0.95, 1))
        ctx.move(to: CGPoint(x: x - w * 0.1, y: y + h - 2 * s)); ctx.addLine(to: CGPoint(x: x + w * 1.1, y: y + h - 2 * s))
        ctx.addLine(to: CGPoint(x: x + w / 2, y: y + h + w * 0.47)); ctx.fillPath()
        if steeple {
            ctx.setFillColor(wall)
            ctx.fill(CGRect(x: x + w * 0.38, y: y + h + w * 0.2, width: w * 0.24, height: w * 0.6))
            ctx.setFillColor(c(0.25, 0.14, 0.12))
            ctx.move(to: CGPoint(x: x + w * 0.34, y: y + h + w * 0.8)); ctx.addLine(to: CGPoint(x: x + w * 0.66, y: y + h + w * 0.8))
            ctx.addLine(to: CGPoint(x: x + w * 0.5, y: y + h + w * 1.25)); ctx.fillPath()
        }
        // Lit windows
        for wx in [0.18, 0.62] {
            let r = CGRect(x: x + w * CGFloat(wx), y: y + h * 0.35, width: w * 0.2, height: h * 0.3)
            glow(CGPoint(x: r.midX, y: r.midY), w * 0.35, c(1, 0.7, 0.3, 0.35))
            ctx.setFillColor(c(1, 0.82, 0.45))
            ctx.fill(r)
            ctx.setStrokeColor(c(0.25, 0.15, 0.1)); ctx.setLineWidth(1.5 * s)
            ctx.stroke(r)
        }
    }

    func cabinHouse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        house(x, y, w, wall: c(0.36, 0.2, 0.11))
        // Chimney with smoke
        ctx.setFillColor(c(0.3, 0.2, 0.17))
        ctx.fill(CGRect(x: x + w * 0.72, y: y + w * 0.75, width: w * 0.1, height: w * 0.3))
        for k in 0..<7 {
            let k = CGFloat(k)
            glow(CGPoint(x: x + w * 0.77 + k * 12 * s, y: y + w * 1.12 + k * 26 * s), (14 + k * 7) * s, c(0.8, 0.82, 0.9, 0.12))
        }
        ctx.setFillColor(c(0.2, 0.1, 0.06))
        ctx.fill(CGRect(x: x + w * 0.42, y: y, width: w * 0.16, height: w * 0.32))
    }

    func fallingSnow(_ n: Int) {
        for _ in 0..<n {
            let r = CGFloat.random(in: 0.8...3) * s
            ctx.setFillColor(c(1, 1, 1, .random(in: 0.35...0.9)))
            ctx.fillEllipse(in: CGRect(x: .random(in: 0...W), y: .random(in: 0...H), width: r * 2, height: r * 2))
        }
    }

    // MARK: Scenes

    func cabin() {
        gradient([c(0.17, 0.21, 0.40), c(0.04, 0.06, 0.16)], from: H * 0.3, to: H)
        stars(500, above: H * 0.4)
        moon(CGPoint(x: W * 0.8, y: H * 0.8), 34 * s)
        ridge(base: H * 0.42, amp: H * 0.1, color: c(0.22, 0.27, 0.42), freq: 3, snowCap: true)
        ridge(base: H * 0.34, amp: H * 0.05, color: c(0.16, 0.2, 0.32), freq: 5)
        snowGround(top: H * 0.3)
        for _ in 0..<14 { pine(.random(in: 0...(W * 0.28)), .random(in: (H * 0.2)...(H * 0.3)), .random(in: 140...260) * s) }
        for _ in 0..<14 { pine(.random(in: (W * 0.6)...W), .random(in: (H * 0.18)...(H * 0.3)), .random(in: 140...280) * s) }
        glow(CGPoint(x: W * 0.43, y: H * 0.26), 380 * s, c(1, 0.6, 0.25, 0.18))
        cabinHouse(W * 0.36, H * 0.22, 260 * s)
        for _ in 0..<6 { pine(.random(in: 0...W), .random(in: 0...(H * 0.1)), .random(in: 280...420) * s, dark: 0.7) }
        fallingSnow(700)
    }

    func northernLights() {
        gradient([c(0.06, 0.14, 0.22), c(0.01, 0.03, 0.09)], from: H * 0.3, to: H)
        stars(650, above: H * 0.35)
        // Aurora curtains
        for (hue, yBase, phase) in [((0.3, 1.0, 0.6), 0.62, 0.0), ((0.65, 0.4, 1.0), 0.72, 2.0)] {
            var x: CGFloat = 0
            while x < W {
                let u = x / W
                let y = H * CGFloat(yBase) + H * 0.07 * sin(u * 7 + CGFloat(phase)) + H * 0.03 * sin(u * 19)
                let a = 0.12 + 0.12 * sin(u * 23 + CGFloat(phase)) * sin(u * 5)
                let len = H * (0.16 + 0.08 * sin(u * 11))
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   colors: [c(CGFloat(hue.0), CGFloat(hue.1), CGFloat(hue.2), max(0.02, a)), c(CGFloat(hue.0), CGFloat(hue.1), CGFloat(hue.2), 0)] as CFArray,
                                   locations: [0, 1])!
                ctx.saveGState()
                ctx.clip(to: CGRect(x: x, y: y, width: 3 * s, height: len))
                ctx.drawLinearGradient(g, start: CGPoint(x: x, y: y), end: CGPoint(x: x, y: y + len), options: [])
                ctx.restoreGState()
                x += 2 * s
            }
        }
        ridge(base: H * 0.33, amp: H * 0.06, color: c(0.05, 0.07, 0.12), freq: 4)
        // Lake with a soft reflection
        ctx.setFillColor(c(0.03, 0.07, 0.13))
        ctx.fill(CGRect(x: 0, y: H * 0.16, width: W, height: H * 0.14))
        for _ in 0..<160 {
            ctx.setFillColor(c(0.3, 0.9, 0.6, .random(in: 0.03...0.1)))
            ctx.fill(CGRect(x: .random(in: 0...W), y: .random(in: (H * 0.17)...(H * 0.29)), width: .random(in: 30...160) * s, height: 1.5 * s))
        }
        for _ in 0..<30 { pine(.random(in: 0...W), H * 0.28, .random(in: 60...110) * s, dark: 0.4) }
        snowGround(top: H * 0.16)
        for _ in 0..<5 { pine(.random(in: 0...W), .random(in: 0...(H * 0.08)), .random(in: 260...380) * s, dark: 0.5) }
        fallingSnow(250)
    }

    func lanternTrail() {
        gradient([c(0.50, 0.38, 0.52), c(0.12, 0.10, 0.26)], from: H * 0.38, to: H)
        stars(220, above: H * 0.6)
        ridge(base: H * 0.5, amp: H * 0.08, color: c(0.32, 0.28, 0.44), freq: 3, snowCap: true)
        snowGround(top: H * 0.42)
        // Winding path
        let path = CGMutablePath()
        path.move(to: CGPoint(x: W * 0.38, y: 0))
        path.addCurve(to: CGPoint(x: W * 0.52, y: H * 0.42), control1: CGPoint(x: W * 0.3, y: H * 0.18), control2: CGPoint(x: W * 0.6, y: H * 0.28))
        path.addLine(to: CGPoint(x: W * 0.535, y: H * 0.42))
        path.addCurve(to: CGPoint(x: W * 0.66, y: 0), control1: CGPoint(x: W * 0.64, y: H * 0.28), control2: CGPoint(x: W * 0.42, y: H * 0.18))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(c(0.78, 0.76, 0.86))
        ctx.fillPath()
        // Lanterns along both sides
        for k in 0..<7 {
            let u = CGFloat(k) / 7
            let sc = 1 - u * 0.75
            let y = H * 0.02 + u * H * 0.38
            let mid = W * 0.52 + sin(u * 3.4) * W * 0.06 * (1 - u)
            for side in [-1.0, 1.0] {
                let x = mid + CGFloat(side) * (W * 0.17 * (1 - u) + 30 * s)
                ctx.setFillColor(c(0.12, 0.1, 0.12))
                ctx.fill(CGRect(x: x - 3 * s * sc, y: y, width: 6 * s * sc, height: 120 * s * sc))
                let lp = CGPoint(x: x, y: y + 130 * s * sc)
                glow(lp, 160 * s * sc, c(1, 0.62, 0.25, 0.35))
                ctx.setFillColor(c(1, 0.82, 0.45))
                ctx.fill(CGRect(x: lp.x - 9 * s * sc, y: lp.y - 12 * s * sc, width: 18 * s * sc, height: 24 * s * sc))
            }
        }
        for _ in 0..<16 { pine(.random(in: 0...(W * 0.25)), .random(in: (H * 0.15)...(H * 0.42)), .random(in: 160...300) * s) }
        for _ in 0..<16 { pine(.random(in: (W * 0.78)...W), .random(in: (H * 0.15)...(H * 0.42)), .random(in: 160...300) * s) }
        fallingSnow(600)
    }

    func village() {
        gradient([c(0.15, 0.2, 0.38), c(0.03, 0.05, 0.14)], from: H * 0.35, to: H)
        stars(450, above: H * 0.45)
        moon(CGPoint(x: W * 0.18, y: H * 0.82), 30 * s)
        ridge(base: H * 0.45, amp: H * 0.07, color: c(0.2, 0.25, 0.4), freq: 3, snowCap: true)
        snowGround(top: H * 0.38)
        let walls = [c(0.55, 0.2, 0.18), c(0.3, 0.35, 0.5), c(0.6, 0.5, 0.35), c(0.35, 0.22, 0.14), c(0.45, 0.45, 0.42)]
        var placed: [CGFloat] = []
        for row in 0..<3 {
            let y = H * (0.32 - CGFloat(row) * 0.1)
            let size = (90 + CGFloat(row) * 50) * s
            var x = CGFloat.random(in: 0...(W * 0.1))
            while x < W - size {
                if row == 0 && placed.isEmpty {
                    house(W * 0.55, y, size * 1.2, wall: c(0.85, 0.82, 0.76), steeple: true)
                    placed.append(W * 0.55)
                }
                if abs(x - W * 0.55) > size * 1.6 {
                    house(x, y + .random(in: -10...10) * s, size * .random(in: 0.85...1.15), wall: walls.randomElement()!)
                }
                if Bool.random() { pine(x + size * 1.35, y - 6 * s, size * 1.4) }
                x += size * .random(in: 1.9...2.8)
            }
        }
        fallingSnow(650)
    }
}
