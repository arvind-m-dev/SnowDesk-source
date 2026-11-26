import SpriteKit
import SceneKit

/// A real 3D snowcat (SceneKit, physically based materials). It is rendered offscreen into a short loop of
/// animation frames (wheels turning, tread lugs moving, beacon blinking) that the 2D overlay plays as a sprite.
/// Faces +x (drives to the right).
final class Snowcat3D {
    let viewport: CGSize
    private let scene: SCNScene
    private let camera: SCNNode
    private static var cache: [Int: [SKTexture]] = [:]
    private var wheelSpinners: [SCNNode] = []
    private var lugRows: [SCNNode] = []
    private let beacon = SCNMaterial()
    private let lugSpacing: CGFloat = 0.26

    /// Where the blade's front edge and the track bottoms sit, as fractions of the viewport (measured from renders).
    let bladeFrontFraction: CGFloat = 0.80
    let bottomFraction: CGFloat = 0.20
    static let frameCount = 8

    init(width: CGFloat) {
        viewport = CGSize(width: width, height: width * 0.74)
        scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Snowcat3D.environment()
        scene.lightingEnvironment.intensity = 0.55

        let cat = SCNNode()
        scene.rootNode.addChildNode(cat)

        let orange = Snowcat3D.pbr(rgb(0.92, 0.36, 0.03), rough: 0.45, metal: 0.05)
        let rubber = Snowcat3D.pbr(rgb(0.07, 0.07, 0.08), rough: 0.9)
        let steel = Snowcat3D.pbr(rgb(0.72, 0.74, 0.78), rough: 0.3, metal: 0.85)
        let darkSteel = Snowcat3D.pbr(rgb(0.22, 0.23, 0.25), rough: 0.45, metal: 0.7)
        let glass = Snowcat3D.pbr(rgb(0.35, 0.55, 0.78), rough: 0.05, metal: 0.6)

        // Tracks with road wheels and moving lugs
        for z in [-0.95, 0.95] as [CGFloat] {
            let track = SCNNode(geometry: SCNBox(width: 3.4, height: 0.78, length: 0.56, chamferRadius: 0.38))
            track.geometry?.firstMaterial = rubber
            track.position = SCNVector3(-0.1, 0.4, z)
            cat.addChildNode(track)
            for wx in [-1.25, -0.62, 0, 0.62, 1.25] as [CGFloat] {
                let spinner = SCNNode()
                spinner.position = SCNVector3(wx - 0.1, 0.4, z + (z > 0 ? 0.04 : -0.04))
                let wheel = SCNNode(geometry: SCNCylinder(radius: 0.27, height: 0.52))
                wheel.geometry?.firstMaterial = darkSteel
                wheel.eulerAngles.x = .pi / 2
                spinner.addChildNode(wheel)
                let hub = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.56))
                hub.geometry?.firstMaterial = steel
                hub.eulerAngles.x = .pi / 2
                spinner.addChildNode(hub)
                let spoke = SCNNode(geometry: SCNBox(width: 0.42, height: 0.05, length: 0.57, chamferRadius: 0.01))
                spoke.geometry?.firstMaterial = steel
                spinner.addChildNode(spoke)
                cat.addChildNode(spinner)
                wheelSpinners.append(spinner)
            }
            let lugs = SCNNode()
            lugs.position = SCNVector3(0, 0, z)
            var lx: CGFloat = -1.6
            while lx < 1.4 {
                let lug = SCNNode(geometry: SCNBox(width: 0.09, height: 0.06, length: 0.58, chamferRadius: 0.01))
                lug.geometry?.firstMaterial = darkSteel
                lug.position = SCNVector3(lx, 0.8, 0)
                lugs.addChildNode(lug)
                lx += lugSpacing
            }
            cat.addChildNode(lugs)
            lugRows.append(lugs)
        }

        // Body, cabin, glass
        let body = SCNNode(geometry: SCNBox(width: 3.0, height: 0.8, length: 1.9, chamferRadius: 0.13))
        body.geometry?.firstMaterial = orange
        body.position = SCNVector3(0, 1.15, 0)
        cat.addChildNode(body)
        let stripe = SCNNode(geometry: SCNBox(width: 3.02, height: 0.1, length: 1.92, chamferRadius: 0.02))
        stripe.geometry?.firstMaterial = Snowcat3D.pbr(rgb(0.12, 0.12, 0.13), rough: 0.5)
        stripe.position = SCNVector3(0, 1.0, 0)
        cat.addChildNode(stripe)
        let cabin = SCNNode(geometry: SCNBox(width: 1.7, height: 1.15, length: 1.75, chamferRadius: 0.15))
        cabin.geometry?.firstMaterial = orange
        cabin.position = SCNVector3(-0.45, 2.1, 0)
        cat.addChildNode(cabin)
        let front = SCNNode(geometry: SCNBox(width: 0.05, height: 0.7, length: 1.45, chamferRadius: 0.02))
        front.geometry?.firstMaterial = glass
        front.position = SCNVector3(0.41, 2.2, 0)
        cat.addChildNode(front)
        for z in [-0.88, 0.88] as [CGFloat] {
            let side = SCNNode(geometry: SCNBox(width: 1.25, height: 0.62, length: 0.05, chamferRadius: 0.02))
            side.geometry?.firstMaterial = glass
            side.position = SCNVector3(-0.45, 2.2, z)
            cat.addChildNode(side)
        }

        // Roof bar and blinking beacon
        let bar = SCNNode(geometry: SCNBox(width: 0.8, height: 0.12, length: 1.2, chamferRadius: 0.04))
        bar.geometry?.firstMaterial = darkSteel
        bar.position = SCNVector3(-0.45, 2.74, 0)
        cat.addChildNode(bar)
        beacon.lightingModel = .physicallyBased
        beacon.diffuse.contents = rgb(1, 0.55, 0.05)
        beacon.emission.contents = rgb(1, 0.6, 0.1)
        let bulb = SCNNode(geometry: SCNSphere(radius: 0.16))
        bulb.geometry?.firstMaterial = beacon
        bulb.position = SCNVector3(-0.45, 2.92, 0)
        cat.addChildNode(bulb)

        // Headlights
        let lamp = SCNMaterial()
        lamp.diffuse.contents = NSColor.white
        lamp.emission.contents = rgb(1, 0.97, 0.85)
        for z in [-0.6, 0.6] as [CGFloat] {
            let h = SCNNode(geometry: SCNCylinder(radius: 0.12, height: 0.06))
            h.geometry?.firstMaterial = lamp
            h.eulerAngles.z = .pi / 2
            h.position = SCNVector3(1.52, 1.28, z)
            cat.addChildNode(h)
        }

        // Curved blade on push arms
        let profile = NSBezierPath()
        profile.move(to: NSPoint(x: 0, y: 0))
        profile.curve(to: NSPoint(x: 0.12, y: 1.15), controlPoint1: NSPoint(x: 0.42, y: 0.25), controlPoint2: NSPoint(x: 0.4, y: 0.9))
        profile.line(to: NSPoint(x: 0.02, y: 1.18))
        profile.curve(to: NSPoint(x: -0.1, y: 0.04), controlPoint1: NSPoint(x: 0.28, y: 0.9), controlPoint2: NSPoint(x: 0.3, y: 0.3))
        profile.close()
        profile.flatness = 0.01
        let bladeShape = SCNShape(path: profile, extrusionDepth: 2.5)
        bladeShape.chamferRadius = 0.02
        bladeShape.firstMaterial = Snowcat3D.pbr(rgb(0.62, 0.64, 0.68), rough: 0.3, metal: 0.85)
        let blade = SCNNode(geometry: bladeShape)
        blade.position = SCNVector3(1.78, 0.05, 0)
        cat.addChildNode(blade)
        let edge = SCNNode(geometry: SCNBox(width: 0.12, height: 0.1, length: 2.5, chamferRadius: 0.02))
        edge.geometry?.firstMaterial = darkSteel
        edge.position = SCNVector3(1.86, 0.06, 0)
        cat.addChildNode(edge)
        for z in [-0.6, 0.6] as [CGFloat] {
            let arm = SCNNode(geometry: SCNBox(width: 0.75, height: 0.12, length: 0.12, chamferRadius: 0.03))
            arm.geometry?.firstMaterial = darkSteel
            arm.position = SCNVector3(1.55, 0.8, z)
            arm.eulerAngles.z = -0.45
            cat.addChildNode(arm)
        }

        // Exhaust
        let pipe = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.75))
        pipe.geometry?.firstMaterial = darkSteel
        pipe.position = SCNVector3(-1.25, 1.85, -0.55)
        cat.addChildNode(pipe)

        // Lights and camera (3/4 view from slightly above the front)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 950
        key.eulerAngles = SCNVector3(-0.85, 0.55, 0)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 350
        fill.position = SCNVector3(-5, 3, 6)
        scene.rootNode.addChildNode(fill)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.intensity = 220
        scene.rootNode.addChildNode(amb)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 26
        cam.position = SCNVector3(4.6, 2.9, 9.8)
        cam.look(at: SCNVector3(0.35, 1.2, 0))
        scene.rootNode.addChildNode(cam)
        camera = cam
    }

    /// Scene points the vehicle travels per animation frame (one lug spacing spread over the loop).
    var pointsPerFrame: CGFloat { lugSpacing * (viewport.width / 5.2) / CGFloat(Snowcat3D.frameCount) }

    /// The looping frames, rendered once per size at 2× for Retina and cached.
    func frames() -> [SKTexture] {
        let key = Int(viewport.width)
        if let f = Snowcat3D.cache[key] { return f }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let px = CGSize(width: viewport.width * 2, height: viewport.height * 2)
        var out: [SKTexture] = []
        for i in 0..<Snowcat3D.frameCount {
            let u = CGFloat(i) / CGFloat(Snowcat3D.frameCount)
            for s in wheelSpinners { s.eulerAngles.z = -u * lugSpacing / 0.27 }
            for row in lugRows { row.position.x = u * lugSpacing }
            beacon.emission.intensity = i < Snowcat3D.frameCount / 2 ? 1.8 : 0.1
            let img = renderer.snapshot(atTime: 0, with: px, antialiasingMode: .multisampling4X)
            let tex = SKTexture(image: img)
            out.append(tex)
        }
        Snowcat3D.cache[key] = out
        return out
    }

    private static func pbr(_ c: NSColor, rough: CGFloat, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    /// Soft winter-sky gradient used as image-based lighting so metal and glass have something to reflect.
    private static func environment() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 128), flipped: false) { r in
            let g = NSGradient(colors: [rgb(0.75, 0.78, 0.85), rgb(0.55, 0.65, 0.85), rgb(0.85, 0.9, 1.0)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)
            g?.draw(in: r, angle: 90)
            return true
        }
    }
}
