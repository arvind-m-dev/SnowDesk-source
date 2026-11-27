import SpriteKit

final class WinState {
    let id: CGWindowID
    var rect: CGRect
    let pile: Pile
    var visible = true
    var lastSeen: TimeInterval
    var history: [(t: TimeInterval, x: CGFloat, y: CGFloat)] = []

    init(id: CGWindowID, rect: CGRect, t: TimeInterval) {
        self.id = id
        self.rect = rect
        self.lastSeen = t
        self.pile = Pile(width: rect.width, maxHeight: 24)
    }
}

struct Particle {
    let node: SKSpriteNode
    var vx: CGFloat
    var vy: CGFloat          // downward speed, px/s
    let size: CGFloat
    let phase: CGFloat
    let isChunk: Bool
    var ix: CGFloat = 0      // extra velocity from the cursor / snow globe, decays over time
    var iy: CGFloat = 0      // (downward positive, like vy)
    var skip: Pile? = nil    // snow knocked off a pile falls past it instead of landing straight back
    var bounces = 0
}

enum Landing {
    case none
    case stuck
    case bounced(surfaceY: CGFloat, onBare: Bool)
}

/// Something extra running in the scene (weather, Santa, fireplace...).
protocol SceneEffect: AnyObject {
    /// Called every frame. Return false when finished; the scene then drops it.
    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool
    /// A global mouse click at a scene point. Return true if handled.
    func click(at p: CGPoint, count: Int, in scene: SnowScene) -> Bool
}

extension SceneEffect {
    func click(at p: CGPoint, count: Int, in scene: SnowScene) -> Bool { false }
}

/// An object resting on a window's top edge (or on the ground) that rides along with it.
final class Perched {
    let node: SKNode
    var windowID: CGWindowID?      // nil = the ground
    var localX: CGFloat            // from the window's left edge (or the scene's left edge)
    var yOffset: CGFloat           // above the ledge
    var onDislodge: (() -> Void)?
    /// Can be picked up with ⌘-drag (birds can't: they fly off instead).
    var draggable = true
    /// Being dragged right now: the scene leaves its position alone.
    var held = false

    init(node: SKNode, windowID: CGWindowID?, localX: CGFloat, yOffset: CGFloat) {
        self.node = node
        self.windowID = windowID
        self.localX = localX
        self.yOffset = yOffset
    }
}

/// The highest surface (window top + snow, or the snowy ground) under a point.
struct Surface {
    let windowID: CGWindowID?
    let ledgeX: CGFloat    // scene x of the ledge's left end (0 for the ground)
    let baseY: CGFloat     // the bare ledge
    let top: CGFloat       // ledge + settled snow
}

final class SnowScene: SKScene {
    let screenFrame: CGRect          // in global Cocoa coordinates
    let isPrimary: Bool

    init(screenFrame: CGRect, isPrimary: Bool) {
        self.screenFrame = screenFrame
        self.isPrimary = isPrimary
        super.init(size: screenFrame.size)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var flakes: [Particle] = []
    var chunks: [Particle] = []
    private(set) var windows: [CGWindowID: WinState] = [:]
    private(set) var ground: Pile!
    private(set) var effects: [SceneEffect] = []
    private(set) var perched: [Perched] = []
    private var weatherEffects: [WeatherKind: AmbientWeather] = [:]
    private var nextSanta: TimeInterval = 0

    // Controls
    var enabled = true { didSet { applyWeather() } }
    var weathers: Set<WeatherKind> = [.snow] { didSet { if weathers != oldValue { applyWeather() } } }
    /// Single-weather view of `weathers` (used by the follow-the-weather service).
    var weather: WeatherKind {
        get { weathers.first ?? .clear }
        set { weathers = newValue == .clear ? [] : [newValue] }
    }
    var surgeFlakes = 0              // extra flakes during "bury my desktop"
    var forceSnow = false            // snow even when another weather is picked (bury)
    var snowFalling: Bool { enabled && (weathers.contains(.snow) || forceSnow) }
    var now: TimeInterval { lastTime }
    private var lastTime: TimeInterval = 0
    private var lastPoll: TimeInterval = 0
    var pollInterval: TimeInterval = Performance.current.poll
    private var texture: SKTexture!
    private let maxChunks = 1600
    private var filledOnce = false

    // Cursor
    private(set) var cursor = CGPoint(x: -9999, y: -9999)
    private(set) var cursorVel = CGVector.zero
    private(set) var cursorSpeed: CGFloat = 0
    private(set) var cursorInside = false
    var optionHeld: Bool { NSEvent.modifierFlags.contains(.option) }
    private var shakeSamples: [(t: TimeInterval, sign: CGFloat)] = []
    private var lastGlobe: TimeInterval = 0
    private let cursorRadius: CGFloat = 110
    private let brushRadius: CGFloat = 16

    var targetFlakes = Intensity.medium.flakeCount

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        texture = SnowScene.makeFlakeTexture()
        ground = Pile(width: size.width, maxHeight: 34)
        ground.node.zPosition = 50
        addChild(ground.node)
        add(SnowmanSystem())
        applyWeather()
    }

    // MARK: - Effects

    func add(_ effect: SceneEffect) { effects.append(effect) }
    func remove(where pred: (SceneEffect) -> Bool) { effects.removeAll(where: pred) }
    func effect<T: SceneEffect>(of type: T.Type) -> T? { effects.first { $0 is T } as? T }

    private func applyWeather() {
        guard ground != nil else { return }
        let want = enabled ? weathers.subtracting([.snow, .clear]) : []
        for (k, e) in weatherEffects where !want.contains(k) {
            e.finish()
            weatherEffects[k] = nil
        }
        for k in want where weatherEffects[k] == nil {
            let e = AmbientWeather(kind: k, scene: self)
            weatherEffects[k] = e
            add(e)
        }
    }

    func handleClick(globalPoint g: CGPoint, count: Int) {
        let p = CGPoint(x: g.x - screenFrame.minX, y: g.y - screenFrame.minY)
        guard frame.contains(p) else { return }
        for e in effects.reversed() where e.click(at: p, count: count, in: self) { return }
    }

    // MARK: - Perching

    func perch(_ p: Perched) {
        perched.append(p)
        positionPerched(p)
    }

    func unperch(_ p: Perched) { perched.removeAll { $0 === p } }

    private func positionPerched(_ p: Perched) {
        if p.held { return }
        if let id = p.windowID {
            guard let s = windows[id], s.visible else { p.node.isHidden = true; return }
            p.node.isHidden = false
            p.node.position = CGPoint(x: s.rect.minX + p.localX, y: s.rect.maxY + p.yOffset)
        } else {
            p.node.isHidden = false
            p.node.position = CGPoint(x: p.localX, y: p.yOffset)
        }
    }

    /// Highest window top (plus its snow) or the ground under x, at or below y.
    func surface(under x: CGFloat, atOrBelow y: CGFloat, ignoring: CGWindowID? = nil) -> Surface {
        let gc = ground.column(forLocalX: min(max(x, 0), size.width - 1)) ?? 0
        var best = Surface(windowID: nil, ledgeX: 0, baseY: 0, top: ground.height(at: gc))
        for s in windows.values where s.visible && s.id != ignoring {
            let r = s.rect
            guard x >= r.minX, x < r.maxX, let c = s.pile.column(forLocalX: x - r.minX), s.pile.exposed[c] else { continue }
            let top = r.maxY + s.pile.height(at: c)
            if top <= y + 0.5 && top > best.top {
                best = Surface(windowID: s.id, ledgeX: r.minX, baseY: r.maxY, top: top)
            }
        }
        return best
    }

    var visibleWindows: [WinState] { windows.values.filter { $0.visible } }

    // MARK: - Public controls

    func clearAllSnow() {
        for state in windows.values where state.visible {
            drop(state, velocity: .zero)
        }
        _ = ground.takeAll()
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 20))
        lastTime = currentTime

        if currentTime - lastPoll >= pollInterval {
            poll(currentTime)
            lastPoll = currentTime
        }
        updateCursor(dt: dt, t: currentTime)
        if cursorInside && cursorSpeed > 60 && !optionHeld { carvePiles() }
        for p in perched { positionPerched(p) }
        updateGrab(dt: dt)
        // Effects may add new effects while updating (Santa drops a present, bury calls the plough): keep those.
        let running = effects
        effects = []
        let kept = running.filter { $0.update(dt: dt, t: currentTime, in: self) }
        effects = kept + effects
        if isPrimary && enabled && Settings.shared.santaVisits {
            if nextSanta == 0 { nextSanta = currentTime + .random(in: 1200...2400) }
            if currentTime > nextSanta {
                nextSanta = currentTime + .random(in: 1500...2700)
                callSanta()
            }
        }
        adjustFlakeCount()
        stepFlakes(dt: dt, t: CGFloat(currentTime))
        stepChunks(dt: dt)

        if !snowFalling {
            let melt = dt * (enabled && !weathers.isDisjoint(with: [.rain, .storm]) ? 3 : 1.2)
            ground.melt(by: melt)
            for s in windows.values { s.pile.melt(by: melt) }
        }
        ground.rebuildPathIfNeeded()
        for s in windows.values where s.visible { s.pile.rebuildPathIfNeeded() }
    }

    // MARK: - Windows

    private func poll(_ t: TimeInterval) {
        let snap = WindowTracker.snapshot().map { VisibleWindow(id: $0.id, rect: $0.rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)) }
        var seen = Set<CGWindowID>()

        for (idx, w) in snap.enumerated() {
            seen.insert(w.id)
            let state: WinState
            if let existing = windows[w.id] {
                state = existing
                if !state.visible {
                    state.visible = true
                    state.pile.node.isHidden = false
                    state.history.removeAll()
                }
                let old = state.rect
                if old != w.rect {
                    if abs(old.width - w.rect.width) > 1 {
                        state.pile.resize(to: w.rect.width)
                    }
                    state.history.append((t, w.rect.minX, w.rect.maxY))
                    state.history.removeAll { t - $0.t > 0.8 }
                    let jump = hypot(w.rect.minX - old.minX, w.rect.maxY - old.maxY)
                    if isShaking(state) || jump > 350 {
                        let dtp = max(CGFloat(pollInterval), 0.001)
                        let v = CGVector(dx: (w.rect.minX - old.minX) / dtp, dy: 0)
                        drop(state, velocity: v)
                        state.history.removeAll()
                    }
                } else if let last = state.history.last, t - last.t > 0.8 {
                    state.history.removeAll()
                }
                state.rect = w.rect
            } else {
                state = WinState(id: w.id, rect: w.rect, t: t)
                windows[w.id] = state
                addChild(state.pile.node)
            }
            state.lastSeen = t
            state.pile.node.position = CGPoint(x: w.rect.minX, y: w.rect.maxY)
            state.pile.node.zPosition = 10 + CGFloat(snap.count - idx) * 0.01
            updateExposure(state, front: snap[0..<idx])
        }

        for (id, state) in windows where !seen.contains(id) {
            if state.visible {
                state.visible = false
                state.pile.node.isHidden = true
            }
            if t - state.lastSeen > 120 {
                for p in perched where p.windowID == id { p.onDislodge?() }
                state.pile.node.removeFromParent()
                windows[id] = nil
            }
        }

        for state in windows.values where state.visible {
            for lx in state.pile.settle(spillsAtEdges: true) {
                let p = CGPoint(x: state.rect.minX + lx + (lx == 0 ? -2 : 2), y: state.rect.maxY + 2)
                spawnChunk(at: p, vx: lx == 0 ? -25 : 25)
            }
            // Too much snow: a drift breaks loose and tumbles off the window.
            let slide = state.pile.checkAvalanche()
            for (i, s) in slide.enumerated() where i % 2 == 0 {
                let n = min(3, Int(s.h / 3) + 1)
                for _ in 0..<n {
                    let p = CGPoint(x: state.rect.minX + s.x + .random(in: -2...2),
                                    y: state.rect.maxY + state.pile.height(at: min(state.pile.count - 1, Int(s.x / Pile.colW))) + .random(in: 0...s.h))
                    spawnChunk(at: p, vx: s.dir * .random(in: 40...150), vy: -.random(in: 0...90), skip: state.pile)
                }
            }
        }
        _ = ground.settle(spillsAtEdges: false)
    }

    /// A column of a window's top edge is buried if a window in front overlaps that spot.
    private func updateExposure(_ state: WinState, front: ArraySlice<VisibleWindow>) {
        let r = state.rect
        let top = r.maxY
        let pile = state.pile
        let blockers = front.map(\.rect).filter {
            $0.minY < top + 2 && $0.maxY > top - 2 && $0.maxX > r.minX && $0.minX < r.maxX
        }
        let offScreen = top > size.height - 2 || top < 1      // e.g. a window on a display below this one
        for c in 0..<pile.count {
            let x = r.minX + (CGFloat(c) + 0.5) * Pile.colW
            let covered = offScreen || x < 0 || x > size.width || blockers.contains { x >= $0.minX && x <= $0.maxX }
            let open = !covered
            if pile.exposed[c] != open {
                pile.exposed[c] = open
                pile.dirty = true
            }
            if !open { pile.clearColumn(c) }
        }
    }

    /// Fast back-and-forth horizontal motion within the last ~0.8 s.
    private func isShaking(_ state: WinState) -> Bool {
        let h = state.history
        guard h.count >= 4 else { return false }
        var reversals = 0
        var lastSign: CGFloat = 0
        for i in 1..<h.count {
            let dt = CGFloat(h[i].t - h[i - 1].t)
            guard dt > 0 else { continue }
            let vx = (h[i].x - h[i - 1].x) / dt
            guard abs(vx) > 350 else { continue }
            let s: CGFloat = vx > 0 ? 1 : -1
            if lastSign != 0 && s != lastSign { reversals += 1 }
            lastSign = s
        }
        return reversals >= 2
    }

    func drop(_ state: WinState, velocity: CGVector) {
        for p in perched where p.windowID == state.id { p.onDislodge?() }
        let r = state.rect
        let samples = state.pile.takeAll()
        var i = 0
        for s in samples {
            i += 1
            if i % 2 == 0 { continue }
            let n = min(4, Int(s.h / 4) + 1)
            for _ in 0..<n {
                let p = CGPoint(x: r.minX + s.x + .random(in: -2...2), y: r.maxY + .random(in: 0...s.h))
                spawnChunk(at: p, vx: velocity.dx * 0.15 + .random(in: -40...40), skip: state.pile)
            }
        }
    }

    // MARK: - Particles

    private func adjustFlakeCount() {
        let target = snowFalling ? targetFlakes + surgeFlakes : 0
        if flakes.count < target {
            // First launch: fill the sky at once. Later (e.g. turning snow back on): drift in from the top.
            let initial = !filledOnce
            let toAdd = initial ? target : min(target - flakes.count, 40)
            for _ in 0..<toAdd {
                flakes.append(makeFlake(y: initial ? .random(in: 0...size.height) : size.height + .random(in: 0...60)))
            }
            filledOnce = true
        }
    }

    func makeFlake(y: CGFloat) -> Particle {
        let s = CGFloat.random(in: 0...1)
        let size = 2 + s * s * 5            // mostly small flakes, a few big ones
        let node = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
        node.alpha = .random(in: 0.55...1)
        node.zPosition = 100
        node.position = CGPoint(x: .random(in: -60...(self.size.width + 60)), y: y)
        addChild(node)
        return Particle(node: node, vx: 0, vy: 28 + size * 9 + .random(in: 0...15),
                        size: size, phase: .random(in: 0...(2 * .pi)), isChunk: false)
    }

    func spawnChunk(at p: CGPoint, vx: CGFloat, vy: CGFloat = .random(in: 0...30), skip: Pile? = nil) {
        guard chunks.count < maxChunks else { return }
        let size = CGFloat.random(in: 2.5...5)
        let node = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
        node.zPosition = 101
        node.position = p
        addChild(node)
        chunks.append(Particle(node: node, vx: vx, vy: vy, size: size, phase: 0, isChunk: true, skip: skip))
    }

    private func stepFlakes(dt: CGFloat, t: CGFloat) {
        guard dt > 0 else { return }
        let wind = 12 + sin(t * 0.13) * 18
        let target = snowFalling ? targetFlakes + surgeFlakes : 0
        var i = 0
        while i < flakes.count {
            var f = flakes[i]
            let p = f.node.position
            if cursorInside { pushByCursor(&f, at: p, dt: dt) }
            let decay = exp(-2.2 * dt)
            f.ix *= decay
            f.iy *= decay
            let sway = sin(t * 1.3 + f.phase) * (6 + f.size * 2)
            let nx = p.x + (wind + sway + f.ix) * dt
            let ny = min(p.y - (f.vy + f.iy) * dt, size.height + 300)
            // Flakes fall in front of the windows: only some settle on a ledge they pass, the rest keep falling.
            let hit = land(x: nx, prevY: p.y, y: ny, amount: f.size * 1.1, skip: nil, stickChance: 0.3,
                           bounceOdds: f.bounces < 2 ? (bare: 0.4, snow: 0.12) : nil)
            if case let .bounced(surfaceY, onBare) = hit {
                // Hop off the surface: a little skip up and sideways, then keep falling.
                f.bounces += 1
                let pop: CGFloat = onBare ? .random(in: 70...150) : .random(in: 35...80)
                f.iy = -(f.vy + pop)
                f.ix += .random(in: -90...90)
                f.node.position = CGPoint(x: nx, y: surfaceY + 0.5)
                flakes[i] = f
                i += 1
                continue
            }
            if case .stuck = hit {} else if !(ny < -10 || nx < -100 || nx > size.width + 100) {
                f.node.position = CGPoint(x: nx, y: ny)
                flakes[i] = f
                i += 1
                continue
            }
            do {
                if flakes.count > target {
                    f.node.removeFromParent()
                    flakes.swapAt(i, flakes.count - 1)
                    flakes.removeLast()
                    continue
                }
                f.node.position = CGPoint(x: .random(in: -60...(size.width + 60)), y: size.height + .random(in: 0...40))
                f.ix = 0
                f.iy = 0
                f.bounces = 0
            }
            flakes[i] = f
            i += 1
        }
    }

    // MARK: - Cursor interaction

    /// Polls the pointer (no permissions needed) and detects a fast side-to-side mouse shake.
    private func updateCursor(dt: CGFloat, t: TimeInterval) {
        let g = NSEvent.mouseLocation   // global Cocoa coords
        let m = CGPoint(x: g.x - screenFrame.minX, y: g.y - screenFrame.minY)
        let inside = m.x >= 0 && m.x <= size.width && m.y >= 0 && m.y <= size.height
        if dt > 0 && inside && cursorInside {
            let raw = CGVector(dx: (m.x - cursor.x) / dt, dy: (m.y - cursor.y) / dt)
            cursorVel = CGVector(dx: cursorVel.dx * 0.55 + raw.dx * 0.45, dy: cursorVel.dy * 0.55 + raw.dy * 0.45)
            if abs(raw.dx) > 1300 {
                let sign: CGFloat = raw.dx > 0 ? 1 : -1
                if shakeSamples.last?.sign != sign { shakeSamples.append((t, sign)) }
            }
        } else {
            cursorVel = .zero
        }
        shakeSamples.removeAll { t - $0.t > 0.7 }
        if shakeSamples.count >= 4 && t - lastGlobe > 1.5 {
            shakeSamples.removeAll()
            lastGlobe = t
            snowGlobe()
        }
        cursorSpeed = hypot(cursorVel.dx, cursorVel.dy)
        cursor = m
        cursorInside = inside
    }

    /// Air pushed by the pointer: flakes are dragged along in its wake and nudged out of its path.
    private func pushByCursor(_ f: inout Particle, at p: CGPoint, dt: CGFloat) {
        let dx = p.x - cursor.x
        let dy = p.y - cursor.y
        let d2 = dx * dx + dy * dy
        let r = cursorRadius
        guard d2 < r * r else { return }
        let d = sqrt(d2) + 0.001
        let fall = 1 - d / r
        // Wake: pick up some of the pointer's velocity (small flakes are lighter, so they react more).
        let lightness = 1.4 - f.size / 10
        let wake = 5.5 * fall * lightness * dt
        f.ix += cursorVel.dx * wake
        f.iy -= cursorVel.dy * wake
        // Push: a gentle "personal space" even when still, stronger when the pointer moves.
        let push = (120 + min(cursorSpeed, 2500) * 3.5) * fall * fall * lightness * dt
        f.ix += dx / d * push
        f.iy -= dy / d * push
        f.ix = max(-900, min(900, f.ix))
        f.iy = max(-900, min(900, f.iy))
    }

    /// Sweeping the pointer through settled snow digs a trough and flicks the snow out of the way.
    func carvePiles() {
        let speed = min(cursorSpeed, 2500)
        var targets: [(pile: Pile, minX: CGFloat, baseY: CGFloat)] = [(ground, 0, 0)]
        for s in windows.values where s.visible { targets.append((s.pile, s.rect.minX, s.rect.maxY)) }
        for (pile, minX, baseY) in targets {
            let rel = cursor.y - baseY                           // pointer height above this ledge
            guard rel > -8, rel < pile.maxHeight + brushRadius,
                  cursor.x > minX - brushRadius, cursor.x < minX + pile.width + brushRadius else { continue }
            let first = max(0, Int((cursor.x - minX - brushRadius) / Pile.colW))
            let last = min(pile.count - 1, Int((cursor.x - minX + brushRadius) / Pile.colW))
            guard first <= last else { continue }
            var removedAcc: CGFloat = 0
            for c in first...last where pile.exposed[c] {
                let x = minX + (CGFloat(c) + 0.5) * Pile.colW
                let off = abs(x - cursor.x) / brushRadius
                guard off < 1 else { continue }
                // Round-bottomed trough centred on the pointer, a few px below it.
                let floor = max(0, rel - 5 + off * off * 8)
                let h = pile.height(at: c)
                guard h > floor + 0.3 else { continue }
                pile.setHeight(c, floor)
                removedAcc += h - floor
                while removedAcc > 2.2 {
                    removedAcc -= 2.2
                    let p = CGPoint(x: x + .random(in: -2...2), y: baseY + floor + .random(in: 0...max(1, h - floor)))
                    let vx = cursorVel.dx * .random(in: 0.25...0.6) + .random(in: -40...40)
                    let up = -(abs(cursorVel.dy) * 0.25 + speed * 0.12 + .random(in: 60...220))
                    spawnChunk(at: p, vx: vx, vy: up)
                }
            }
        }
    }

    /// Shake the mouse: settled snow is thrown back into the air and everything swirls, like a snow globe.
    func snowGlobe() {
        var extra = 0
        let maxExtra = 1400
        var lofts: [(samples: [(x: CGFloat, h: CGFloat)], minX: CGFloat, baseY: CGFloat)] = [(ground.loft(fraction: 0.75), 0, 0)]
        for s in windows.values where s.visible {
            lofts.append((s.pile.loft(fraction: 0.85), s.rect.minX, s.rect.maxY))
        }
        for (samples, minX, baseY) in lofts {
            for (i, smp) in samples.enumerated() where i % 2 == 0 {
                let n = min(3, Int(smp.h / 2.5) + 1)
                for _ in 0..<n where extra < maxExtra {
                    var f = makeFlake(y: baseY + .random(in: 0...max(1, smp.h)))
                    f.node.position.x = minX + smp.x + .random(in: -2...2)
                    f.ix = .random(in: -260...260)
                    f.iy = -.random(in: 250...750)
                    flakes.append(f)
                    extra += 1
                }
            }
        }
        for i in flakes.indices {
            flakes[i].ix += .random(in: -320...320)
            flakes[i].iy -= .random(in: 120...480)
        }
    }

    private func stepChunks(dt: CGFloat) {
        guard dt > 0 else { return }
        var i = 0
        while i < chunks.count {
            var c = chunks[i]
            c.vy += 1100 * dt
            c.vx *= (1 - 1.5 * dt)
            let p = c.node.position
            let nx = p.x + c.vx * dt
            let ny = p.y - c.vy * dt
            let hit = land(x: nx, prevY: p.y, y: ny, amount: 2.2, skip: c.skip,
                           bounceOdds: c.bounces < 1 && c.vy > 250 ? (bare: 0.6, snow: 0.3) : nil)
            if case let .bounced(surfaceY, onBare) = hit {
                // Clumps hitting hard rebound a little and skitter sideways.
                c.bounces += 1
                c.vy = -c.vy * (onBare ? .random(in: 0.25...0.4) : .random(in: 0.1...0.2))
                c.vx += .random(in: -80...80)
                c.node.position = CGPoint(x: nx, y: surfaceY + 0.5)
                chunks[i] = c
                i += 1
                continue
            }
            if case .stuck = hit {} else if ny >= -10 {
                c.node.position = CGPoint(x: nx, y: ny)
                chunks[i] = c
                i += 1
                continue
            }
            do {
                c.node.removeFromParent()
                chunks.swapAt(i, chunks.count - 1)
                chunks.removeLast()
            }
        }
    }

    /// Checks whether a particle moving from prevY to y at x hits a surface. It either sticks (deposited),
    /// or — with the given odds, higher on a bare window edge than on soft snow — bounces off.
    func land(x: CGFloat, prevY: CGFloat, y: CGFloat, amount: CGFloat, skip: Pile?, stickChance: Double = 1,
                      bounceOdds: (bare: Double, snow: Double)?) -> Landing {
        func decide(_ h: CGFloat, _ surface: CGFloat) -> Landing? {
            guard let odds = bounceOdds else { return nil }
            let bare = h < 1.5
            return Double.random(in: 0..<1) < (bare ? odds.bare : odds.snow) ? .bounced(surfaceY: surface, onBare: bare) : nil
        }
        for s in windows.values where s.visible && s.pile !== skip {
            let r = s.rect
            guard x >= r.minX, x < r.maxX, let c = s.pile.column(forLocalX: x - r.minX), s.pile.exposed[c] else { continue }
            let h = s.pile.height(at: c)
            let surface = r.maxY + h
            if prevY >= surface - 0.5 && y < surface {
                if stickChance < 1 && Double.random(in: 0..<1) > stickChance { continue }
                if let b = decide(h, surface) { return b }
                s.pile.deposit(column: c, amount: amount)
                return .stuck
            }
        }
        if let c = ground.column(forLocalX: x), y < ground.height(at: c) {
            let h = ground.height(at: c)
            if prevY >= h - 0.5, let b = decide(max(h, 2), h) { return b }   // the ground is always snowy-soft
            ground.deposit(column: c, amount: amount * 0.35)
            return .stuck
        }
        return .none
    }

    private static func makeFlakeTexture() -> SKTexture {
        let d = 24
        let image = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            let colors = [NSColor.white, NSColor.white.withAlphaComponent(0.85), NSColor.white.withAlphaComponent(0)]
            let g = NSGradient(colors: colors, atLocations: [0, 0.45, 1], colorSpace: .sRGB)
            g?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        return SKTexture(image: image)
    }

    // MARK: - Staying out of the way / ⌘-grab

    /// Snow height under a perched object, relative to its ledge (nil if the ledge is gone).
    func restOffset(for p: Perched) -> CGFloat? {
        if let id = p.windowID {
            guard let s = windows[id], s.visible, let c = s.pile.column(forLocalX: p.localX) else { return nil }
            return s.pile.height(at: c)
        }
        guard let c = ground.column(forLocalX: min(max(p.localX, 0), size.width - 1)) else { return nil }
        return ground.height(at: c)
    }

    private var grabbed: Perched?
    private var grabOffset = CGPoint.zero
    private var grabStart = CGPoint.zero
    private var grabMoved = false
    var commandHeld: Bool { NSEvent.modifierFlags.contains(.command) }

    /// The frontmost perched object under a point (with a little slack).
    private func perched(at pt: CGPoint, slack: CGFloat) -> Perched? {
        for p in perched.reversed() where !p.node.isHidden && p.node.parent != nil {
            let n = p.node
            guard abs(n.position.x - pt.x) < 260, abs(n.position.y - pt.y) < 260 else { continue }
            let origin = n.parent.map { convert(CGPoint.zero, from: $0) } ?? .zero
            let f = n.calculateAccumulatedFrame().offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -slack, dy: -slack)
            if f.contains(pt) { return p }
        }
        return nil
    }

    /// Objects fade when the pointer comes close so you can see (and click) what's under them.
    /// Holding ⌘ brings them back and lets the overlay catch the mouse, but only over an object.
    private func updateGrab(dt: CGFloat) {
        let cmd = commandHeld
        let near = cursorInside ? perched(at: cursor, slack: cmd ? 4 : 36) : nil
        for p in perched where p !== grabbed {
            let target: CGFloat = (p === near && !cmd) ? 0.22 : 1
            p.node.alpha += (target - p.node.alpha) * min(1, dt * 10)
        }
        let capture = grabbed != nil || (cmd && near?.draggable == true)
        if let w = view?.window, w.ignoresMouseEvents == capture {
            w.ignoresMouseEvents = !capture
            if capture { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        guard let p = perched(at: pt, slack: 4), p.draggable else { return }
        grabbed = p
        p.held = true
        grabOffset = CGPoint(x: p.node.position.x - pt.x, y: p.node.position.y - pt.y)
        grabStart = pt
        grabMoved = false
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let p = grabbed else { return }
        let pt = event.location(in: self)
        if hypot(pt.x - grabStart.x, pt.y - grabStart.y) > 4 { grabMoved = true }
        p.node.position = CGPoint(x: pt.x + grabOffset.x, y: pt.y + grabOffset.y)
        p.node.alpha = 1
    }

    override func mouseUp(with event: NSEvent) {
        guard let p = grabbed else { return }
        grabbed = nil
        p.held = false
        if !grabMoved {
            // A ⌘-click: let the object react (open a present, knock over a snowman...).
            let g = CGPoint(x: grabStart.x + screenFrame.minX, y: grabStart.y + screenFrame.minY)
            handleClick(globalPoint: g, count: event.clickCount)
        } else {
            // Set it down on whatever is below: a window top or the ground.
            let x = min(max(p.node.position.x, 2), size.width - 2)
            let s = surface(under: x, atOrBelow: p.node.position.y + 2)
            p.windowID = s.windowID
            p.localX = x - s.ledgeX
            p.yOffset = s.top - s.baseY
            Sound.shared.play(.pop, volume: 0.3)
        }
        NSCursor.openHand.set()
    }
}
