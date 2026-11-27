import SpriteKit
import SceneKit

/// Small 3D props (SceneKit, physically based) rendered once offscreen into sprite textures.
enum Models3D {
    private static func pbr(_ c: NSColor, rough: CGFloat, metal: CGFloat = 0, emit: NSColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = metal
        if let e = emit { m.emission.contents = e }
        return m
    }

    private static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ cr: CGFloat, _ m: SCNMaterial, at p: SCNVector3) -> SCNNode {
        let n = SCNNode(geometry: SCNBox(width: w, height: h, length: d, chamferRadius: cr))
        n.geometry?.firstMaterial = m
        n.position = p
        return n
    }

    private static func render(_ scene: SCNScene, camera: SCNNode, size: CGSize) -> SKTexture {
        scene.background.contents = NSColor.clear
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = scene
        r.pointOfView = camera
        let img = r.snapshot(atTime: 0, with: CGSize(width: size.width * 2, height: size.height * 2), antialiasingMode: .multisampling4X)
        return SKTexture(image: img)
    }

    private static func light(_ type: SCNLight.LightType, _ intensity: CGFloat, color: NSColor = .white) -> SCNNode {
        let n = SCNNode()
        n.light = SCNLight()
        n.light?.type = type
        n.light?.intensity = intensity
        n.light?.color = color
        return n
    }

    // MARK: - Fireplace

    struct Fireplace {
        let texture: SKTexture
        let size: CGSize
        /// Opening (where the fire burns) and the two candle wicks, as fractions of the image (origin bottom-left).
        let opening: CGRect
        let candles: [CGPoint]
    }

    private static var fireplaceCache: Fireplace?

    /// A brick fireplace with a wooden mantel, garland, stockings, candles and logs, lit warmly from inside.
    static func fireplace(width: CGFloat) -> Fireplace {
        if let f = fireplaceCache, f.size.width == width { return f }
        let scene = SCNScene()
        scene.lightingEnvironment.contents = NSColor(calibratedWhite: 0.35, alpha: 1)
        scene.lightingEnvironment.intensity = 0.6
        let model = SCNNode()
        scene.rootNode.addChildNode(model)

        // Mortar backing
        model.addChildNode(box(2.04, 2.16, 0.5, 0.02, pbr(rgb(0.30, 0.25, 0.22), rough: 0.95), at: SCNVector3(0, 1.08, -0.05)))
        // Bricks, skipping the arched opening
        func inOpening(_ x: CGFloat, _ y: CGFloat) -> Bool {
            if abs(x) < 0.62 && y < 0.82 { return true }
            let dx = x / 0.62, dy = (y - 0.82) / 0.32
            return dx * dx + dy * dy < 1
        }
        var rng = SystemRandomNumberGenerator()
        for row in 0..<14 {
            let y = 0.08 + CGFloat(row) * 0.152
            let shift: CGFloat = row % 2 == 0 ? 0 : 0.165
            var x = -1.0 + 0.16 + shift
            while x < 1.0 - 0.1 {
                let bw: CGFloat = min(0.3, 1.0 - 0.02 - x + 0.15)
                if !inOpening(x, y) && bw > 0.1 {
                    let tone = CGFloat.random(in: -0.07...0.07, using: &rng)
                    let m = pbr(rgb(0.56 + tone, 0.28 + tone * 0.6, 0.20 + tone * 0.4), rough: 0.85)
                    model.addChildNode(box(bw, 0.135, 0.28, 0.02, m, at: SCNVector3(x, y, 0.08)))
                }
                x += 0.33
            }
        }
        // Firebox recess and back wall
        model.addChildNode(box(1.2, 1.12, 0.05, 0, pbr(rgb(0.05, 0.03, 0.03), rough: 1), at: SCNVector3(0, 0.56, -0.12)))
        model.addChildNode(box(1.22, 0.05, 0.4, 0, pbr(rgb(0.08, 0.06, 0.05), rough: 1), at: SCNVector3(0, 0.03, 0.02)))
        // Logs and grate
        let bark = pbr(rgb(0.33, 0.2, 0.11), rough: 0.9)
        for (y, rot, z) in [(0.12, 0.08, 0.02), (0.22, -0.12, -0.02)] as [(CGFloat, CGFloat, CGFloat)] {
            let log = SCNNode(geometry: SCNCylinder(radius: 0.085, height: 0.9))
            log.geometry?.firstMaterial = bark
            log.eulerAngles = SCNVector3(0, rot, CGFloat.pi / 2)
            log.position = SCNVector3(0, y, z)
            model.addChildNode(log)
        }
        let iron = pbr(rgb(0.12, 0.12, 0.13), rough: 0.5, metal: 0.8)
        for gx in stride(from: -0.45, through: 0.45, by: 0.15) {
            model.addChildNode(box(0.03, 0.3, 0.03, 0.01, iron, at: SCNVector3(gx, 0.17, 0.2)))
        }
        model.addChildNode(box(1.0, 0.03, 0.03, 0.01, iron, at: SCNVector3(0, 0.31, 0.2)))
        // Hearth and mantel
        model.addChildNode(box(2.4, 0.1, 0.8, 0.03, pbr(rgb(0.55, 0.54, 0.52), rough: 0.7), at: SCNVector3(0, -0.05, 0.15)))
        let wood = pbr(rgb(0.42, 0.24, 0.11), rough: 0.55)
        model.addChildNode(box(2.5, 0.14, 0.5, 0.03, wood, at: SCNVector3(0, 2.2, 0.12)))
        model.addChildNode(box(2.3, 0.08, 0.38, 0.02, wood, at: SCNVector3(0, 2.1, 0.08)))
        // Garland with berries
        let leaf = pbr(rgb(0.1, 0.36, 0.18), rough: 0.8)
        let berry = pbr(rgb(0.8, 0.08, 0.1), rough: 0.4)
        var gx: CGFloat = -1.15
        while gx <= 1.15 {
            let sag = 0.06 * (1 - pow(gx / 1.15, 2))
            let n = SCNNode(geometry: SCNSphere(radius: 0.055))
            n.geometry?.firstMaterial = leaf
            n.position = SCNVector3(gx, 2.13 - sag, 0.38)
            model.addChildNode(n)
            if Int(gx * 20) % 4 == 0 {
                let b = SCNNode(geometry: SCNSphere(radius: 0.028))
                b.geometry?.firstMaterial = berry
                b.position = SCNVector3(gx + 0.02, 2.1 - sag, 0.43)
                model.addChildNode(b)
            }
            gx += 0.06
        }
        // Stockings
        for (sx, color) in [(-0.6, rgb(0.78, 0.1, 0.12)), (0.6, rgb(0.1, 0.45, 0.25))] as [(CGFloat, NSColor)] {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: -0.11, y: 0))
            p.line(to: NSPoint(x: 0.11, y: 0))
            p.line(to: NSPoint(x: 0.11, y: -0.32))
            p.curve(to: NSPoint(x: 0.25, y: -0.47), controlPoint1: NSPoint(x: 0.2, y: -0.36), controlPoint2: NSPoint(x: 0.28, y: -0.4))
            p.curve(to: NSPoint(x: -0.11, y: -0.42), controlPoint1: NSPoint(x: 0.2, y: -0.56), controlPoint2: NSPoint(x: -0.06, y: -0.52))
            p.close()
            p.flatness = 0.01
            let shape = SCNShape(path: p, extrusionDepth: 0.08)
            shape.chamferRadius = 0.02
            shape.firstMaterial = pbr(color, rough: 0.9)
            let st = SCNNode(geometry: shape)
            st.position = SCNVector3(sx, 2.02, 0.4)
            model.addChildNode(st)
            model.addChildNode(box(0.26, 0.09, 0.1, 0.03, pbr(.white, rough: 1), at: SCNVector3(sx, 2.0, 0.41)))
        }
        // Candles (flames are drawn live in 2D)
        var candleTops: [SCNVector3] = []
        for cx in [-1.0, 1.0] as [CGFloat] {
            let c = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.24))
            c.geometry?.firstMaterial = pbr(rgb(0.96, 0.93, 0.84), rough: 0.6)
            c.position = SCNVector3(cx, 2.39, 0.15)
            model.addChildNode(c)
            candleTops.append(SCNVector3(cx, 2.55, 0.15))
        }

        // Turn it a little so the side shows (it sits in the bottom-right corner, seen from the left).
        let yaw: CGFloat = 0.32
        model.eulerAngles.y = yaw

        // Lights: soft key, warm firelight from the opening, low ambient
        let key = light(.directional, 520)
        key.eulerAngles = SCNVector3(-0.7, -0.5, 0)
        scene.rootNode.addChildNode(key)
        let fire = light(.omni, 420, color: rgb(1, 0.5, 0.18))
        fire.light?.attenuationStartDistance = 0.1
        fire.light?.attenuationEndDistance = 1.1
        fire.position = SCNVector3(0, 0.35, -0.02)
        scene.rootNode.addChildNode(fire)
        scene.rootNode.addChildNode(light(.ambient, 180))

        // Orthographic camera so 3D points map straight to image fractions.
        let half: CGFloat = 1.42
        let aspect: CGFloat = 1.05
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.usesOrthographicProjection = true
        cam.camera?.orthographicScale = Double(half)
        cam.position = SCNVector3(0, 1.18, 10)
        scene.rootNode.addChildNode(cam)

        let size = CGSize(width: width, height: width / aspect)
        func project(_ p: SCNVector3) -> CGPoint {
            let wx = p.x * cos(yaw) + p.z * sin(yaw)
            return CGPoint(x: (wx - cam.position.x) / (2 * half * aspect) + 0.5, y: (p.y - cam.position.y) / (2 * half) + 0.5)
        }
        let a = project(SCNVector3(-0.55, 0.1, 0.1)), b = project(SCNVector3(0.55, 0.95, 0.1))
        let fp = Fireplace(texture: render(scene, camera: cam, size: size), size: size,
                           opening: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y),
                           candles: candleTops.map(project))
        fireplaceCache = fp
        return fp
    }

    // MARK: - Pine trees

    private static var treeCache: [Int: SKTexture] = [:]

    /// Width ÷ height of each tree texture.
    static func pineAspect(_ variant: Int) -> CGFloat { variant == 3 ? 0.74 : 0.62 }

    /// Snow-dusted pine. Variant 0: plain, 1: with tiny warm lights, 2: tall and slim, 3: short round fir.
    static func pine(variant: Int, height: CGFloat, snowy: Bool = true) -> SKTexture {
        let key = variant * 10_000 + Int(height) + (snowy ? 0 : 500_000)
        if let t = treeCache[key] { return t }
        let scene = SCNScene()
        scene.lightingEnvironment.contents = NSColor(calibratedWhite: 0.6, alpha: 1)
        scene.lightingEnvironment.intensity = 0.5
        let tree = SCNNode()
        scene.rootNode.addChildNode(tree)
        let slim: CGFloat = variant == 2 ? 0.75 : (variant == 3 ? 1.2 : 1)
        let needles = pbr(snowy ? rgb(0.09, 0.30, 0.17) : rgb(0.11, 0.36, 0.19), rough: 0.85)
        let snow = pbr(rgb(0.95, 0.97, 1), rough: 0.6)
        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 0.4))
        trunk.geometry?.firstMaterial = pbr(rgb(0.32, 0.2, 0.11), rough: 0.9)
        trunk.position = SCNVector3(0, 0.2, 0)
        tree.addChildNode(trunk)
        let tiers: [(CGFloat, CGFloat, CGFloat)] = variant == 3
            ? [(0.62, 0.8, 0.25), (0.5, 0.7, 0.62), (0.36, 0.6, 0.96)]
            : [(0.62, 0.9, 0.3), (0.5, 0.8, 0.75), (0.38, 0.7, 1.15), (0.25, 0.55, 1.5)]
        var lights: [SCNVector3] = []
        for (r, h, y) in tiers {
            let cone = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: r * slim, height: h))
            cone.geometry?.firstMaterial = needles
            cone.position = SCNVector3(0, y + h / 2, 0)
            tree.addChildNode(cone)
            if snowy {
                let cap = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: r * slim * 0.72, height: h * 0.55))
                cap.geometry?.firstMaterial = snow
                cap.position = SCNVector3(0, y + h - h * 0.55 / 2 + 0.01, 0)
                tree.addChildNode(cap)
            }
            for k in 0..<5 {
                let a = CGFloat(k) / 5 * .pi + .random(in: -0.2...0.2)
                let f = CGFloat.random(in: 0.1...0.45)
                let rr = r * slim * (1 - f) + 0.01
                lights.append(SCNVector3(cos(a) * rr, y + h * f, sin(a) * rr))
            }
        }
        if variant == 1 {
            let colors = [rgb(1, 0.75, 0.3), rgb(1, 0.3, 0.25), rgb(0.5, 0.8, 1), rgb(1, 0.9, 0.6)]
            for (i, p) in lights.enumerated() {
                let s = SCNNode(geometry: SCNSphere(radius: 0.035))
                let c = colors[i % colors.count]
                s.geometry?.firstMaterial = pbr(c, rough: 0.3, emit: c)
                s.position = p
                tree.addChildNode(s)
            }
            let star = SCNNode(geometry: SCNSphere(radius: 0.07))
            star.geometry?.firstMaterial = pbr(rgb(1, 0.85, 0.3), rough: 0.3, emit: rgb(1, 0.8, 0.3))
            star.position = SCNVector3(0, 2.08, 0)
            tree.addChildNode(star)
        }
        addTreeLights(scene)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.usesOrthographicProjection = true
        cam.camera?.orthographicScale = 1.12
        cam.position = SCNVector3(0, 1.08, 10)
        cam.eulerAngles.x = -0.02
        scene.rootNode.addChildNode(cam)
        let tex = render(scene, camera: cam, size: CGSize(width: height * pineAspect(variant), height: height))
        treeCache[key] = tex
        return tex
    }

    /// Key light with soft self-shadowing, a cool rim from behind and ambient fill.
    private static func addTreeLights(_ scene: SCNScene) {
        let key = light(.directional, 850)
        key.eulerAngles = SCNVector3(-0.6, -0.6, 0)
        key.light?.castsShadow = true
        key.light?.shadowRadius = 4
        key.light?.shadowSampleCount = 8
        key.light?.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.45)
        key.light?.orthographicScale = 2
        key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        scene.rootNode.addChildNode(key)
        let rim = light(.directional, 320, color: rgb(0.75, 0.85, 1))
        rim.eulerAngles = SCNVector3(-0.3, 2.6, 0)
        scene.rootNode.addChildNode(rim)
        scene.rootNode.addChildNode(light(.ambient, 240))
    }

    // MARK: - Leafy trees

    static let broadleafAspect: CGFloat = 0.82
    private static var leafCache: [String: SKTexture] = [:]

    /// A rounded leafy tree dressed for the season (bare, snowy branches in winter).
    static func broadleaf(season: Season, variant: Int, height: CGFloat) -> SKTexture {
        let key = "\(season.rawValue)-\(variant)-\(Int(height))"
        if let t = leafCache[key] { return t }
        // Repeatable pseudo-random numbers so each variant always looks the same.
        var seed = UInt64(variant * 7919 + 17)
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        let scene = SCNScene()
        scene.lightingEnvironment.contents = NSColor(calibratedWhite: 0.6, alpha: 1)
        scene.lightingEnvironment.intensity = 0.5
        let tree = SCNNode()
        scene.rootNode.addChildNode(tree)
        let bark = pbr(rgb(0.33, 0.22, 0.14), rough: 0.95)
        let trunk = SCNNode(geometry: SCNCone(topRadius: 0.06, bottomRadius: 0.11, height: 0.95))
        trunk.geometry?.firstMaterial = bark
        trunk.position = SCNVector3(0, 0.475, 0)
        tree.addChildNode(trunk)
        // Main branches
        var tips: [SCNVector3] = []
        for k in 0..<5 {
            let a = CGFloat(k) / 5 * 2 * .pi + rnd()
            let tilt = 0.3 + rnd() * 0.3
            let len = 0.4 + rnd() * 0.2
            let b = SCNNode(geometry: SCNCylinder(radius: 0.03, height: len))
            b.geometry?.firstMaterial = bark
            let base = SCNVector3(0, 0.75 + rnd() * 0.2, 0)
            let dir = SCNVector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
            b.position = SCNVector3(base.x + dir.x * len / 2, base.y + dir.y * len / 2, base.z + dir.z * len / 2)
            b.look(at: SCNVector3(base.x + dir.x * len, base.y + dir.y * len, base.z + dir.z * len), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            tree.addChildNode(b)
            tips.append(SCNVector3(base.x + dir.x * len, base.y + dir.y * len, base.z + dir.z * len))
        }
        let colors: [NSColor]
        switch season {
        case .spring: colors = [rgb(0.98, 0.76, 0.84), rgb(1, 0.88, 0.92), rgb(0.95, 0.65, 0.78), rgb(0.55, 0.75, 0.4)]
        case .summer: colors = [rgb(0.2, 0.5, 0.18), rgb(0.28, 0.58, 0.22), rgb(0.16, 0.42, 0.16)]
        case .autumn: colors = [rgb(0.92, 0.45, 0.1), rgb(0.85, 0.25, 0.1), rgb(0.95, 0.7, 0.18), rgb(0.7, 0.35, 0.12)]
        case .monsoon: colors = [rgb(0.1, 0.42, 0.18), rgb(0.14, 0.5, 0.2), rgb(0.08, 0.36, 0.15)]
        case .winter: colors = []
        }
        if season == .winter {
            let snow = pbr(rgb(0.95, 0.97, 1), rough: 0.6)
            for p in tips {
                let s = SCNNode(geometry: SCNSphere(radius: 0.05))
                s.geometry?.firstMaterial = snow
                s.position = p
                tree.addChildNode(s)
            }
        } else {
            // Canopy: overlapping leafy clumps around the branch tips and the crown.
            let mats = colors.map { pbr($0, rough: 0.8) }
            // A rounded crown: clumps scattered over an egg shape, plus the branch tips.
            var clumps = tips + [SCNVector3(0, 1.62, 0), SCNVector3(0, 1.3, 0.25)]
            for k in 0..<12 {
                let a = CGFloat(k) / 12 * 2 * .pi + rnd() * 0.4
                let up = 1.05 + rnd() * 0.6
                let rad = 0.36 * sin(.pi * (up - 0.95) / 0.85) + 0.08
                clumps.append(SCNVector3(cos(a) * rad, up, sin(a) * rad))
            }
            for (i, p) in clumps.enumerated() {
                let s = SCNNode(geometry: SCNSphere(radius: 0.19 + rnd() * 0.1))
                (s.geometry as? SCNSphere)?.segmentCount = 18
                s.geometry?.firstMaterial = mats[i % mats.count]
                s.position = p
                s.scale = SCNVector3(1, 0.85, 1)
                tree.addChildNode(s)
            }
        }
        addTreeLights(scene)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.usesOrthographicProjection = true
        cam.camera?.orthographicScale = 1.02
        cam.position = SCNVector3(0, 1.0, 10)
        scene.rootNode.addChildNode(cam)
        let tex = render(scene, camera: cam, size: CGSize(width: height * broadleafAspect, height: height))
        leafCache[key] = tex
        return tex
    }
}
