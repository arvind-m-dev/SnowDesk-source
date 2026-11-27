import SpriteKit

/// Menu actions and helpers used by the effects.
extension SnowScene {
    func callSanta() {
        add(SantaEffect(scene: self))
        Sound.shared.play(.bells, volume: 0.7)
    }

    func buryDesktop() {
        guard effect(of: BuryEffect.self) == nil else { return }
        add(BuryEffect(scene: self))
    }

    func sendPlough() {
        guard effect(of: PloughEffect.self) == nil else { return }
        add(PloughEffect(big: false, scene: self))
    }

    var isFrozen: Bool { effect(of: FrostEffect.self) != nil }

    func thawFrost() { effect(of: FrostEffect.self)?.thaw() }

    func toggleFrost() {
        if let f = effect(of: FrostEffect.self) { f.thaw() } else { add(FrostEffect(scene: self)) }
    }

    /// Warmth from the desktop fireplace (pass nil when it's out).
    func setFireWarmth(at x: CGFloat?) {
        effects.compactMap { $0 as? WarmthEffect }.forEach { $0.extinguish() }
        if let x { add(WarmthEffect(fireX: x - screenFrame.minX)) }
    }

    func setLights(_ mode: LightsMode) {
        let existing = effects.compactMap { $0 as? LightsEffect }.first { !$0.isFinishing }
        if mode == .off {
            existing?.finish()
            return
        }
        if let e = existing { e.mode = mode } else { add(LightsEffect(mode: mode)) }
    }

    /// Takes snow from piles near p (the ⌥ snowball roller). Returns the amount collected (sum of column heights).
    func collectSnow(around p: CGPoint, radius: CGFloat, depthBelowCursor: CGFloat) -> CGFloat {
        var got: CGFloat = 0
        var ledges: [(Pile, CGFloat, CGFloat)] = [(ground, 0, 0)]
        for s in visibleWindows { ledges.append((s.pile, s.rect.minX, s.rect.maxY)) }
        for (pile, minX, baseY) in ledges {
            let rel = p.y - baseY
            guard rel > -depthBelowCursor - 6, rel < pile.maxHeight + radius,
                  p.x > minX - radius, p.x < minX + pile.width + radius else { continue }
            let first = max(0, Int((p.x - minX - radius) / Pile.colW))
            let last = min(pile.count - 1, Int((p.x - minX + radius) / Pile.colW))
            guard first <= last else { continue }
            for c in first...last where pile.exposed[c] {
                let x = minX + (CGFloat(c) + 0.5) * Pile.colW
                let off = abs(x - p.x) / radius
                guard off < 1 else { continue }
                let floor = max(0, rel - depthBelowCursor + off * off * 6)
                let h = pile.height(at: c)
                guard h > floor + 0.2 else { continue }
                // Roll up a share each frame so the ball grows smoothly.
                let take = (h - floor) * 0.5
                pile.setHeight(c, h - take)
                got += take
            }
        }
        return got
    }

    /// The running (not fading-out) effect of a type.
    func live<T: SceneEffect & Finishable>(_ t: T.Type) -> T? {
        effects.compactMap { $0 as? T }.first { !$0.isFinishing }
    }

    func setScenery(_ s: Set<Scenery>) {
        if s.contains(.birds) { if live(BirdsEffect.self) == nil { add(BirdsEffect(scene: self)) } } else { live(BirdsEffect.self)?.finish() }
        if s.contains(.butterflies) { if live(ButterfliesEffect.self) == nil { add(ButterfliesEffect(scene: self)) } } else { live(ButterfliesEffect.self)?.finish() }
        let menuBats = effects.compactMap { $0 as? BatsEffect }.first { !$0.isFinishing && !$0.eventOwned }
        if s.contains(.bats) { if menuBats == nil { add(BatsEffect(scene: self)) } } else { menuBats?.finish() }
        let ski = s.contains(.skiers), sled = s.contains(.sledders)
        if let r = live(RidersEffect.self) {
            r.skiers = ski
            r.sledders = sled
        } else if ski || sled {
            add(RidersEffect(skiers: ski, sledders: sled, scene: self))
        }
    }

    func setEvent(_ kind: EventKind?) {
        let current = live(EventEffect.self)
        if current?.kind == kind { return }
        current?.finish()
        if let kind { add(EventEffect(kind: kind, scene: self)) }
    }

    func sendRider(_ kind: RidersEffect.Kind) {
        let r = live(RidersEffect.self) ?? {
            let r = RidersEffect(skiers: false, sledders: false, scene: self)
            add(r)
            return r
        }()
        r.send(kind, scene: self)
    }

    /// A perched object whose window went away lands on the ground under where it was.
    func dropToGround(_ p: Perched) {
        let x = min(max(p.node.position.x, 10), size.width - 10)
        p.windowID = nil
        p.localX = x
        p.yOffset = ground.column(forLocalX: x).map { ground.height(at: $0) } ?? 0
        p.node.isHidden = false
    }

    var snowmen: SnowmanBuilds {
        if let b = effect(of: SnowmanBuilds.self) { return b }
        let b = SnowmanBuilds()
        add(b)
        return b
    }
}

/// An effect that fades out after `finish()` before the scene drops it.
protocol Finishable: AnyObject {
    var isFinishing: Bool { get }
    func finish()
}
