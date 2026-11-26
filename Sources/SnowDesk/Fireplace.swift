import SpriteKit

/// The fireplace itself is drawn on the desktop layer (see DesktopDecor) so it never covers your apps.
/// This invisible effect lives in the snow overlay and lets its warmth melt snow — faster the closer it is.
final class WarmthEffect: SceneEffect {
    private let fireX: CGFloat
    private var out = false

    init(fireX: CGFloat) { self.fireX = fireX }

    var isOut: Bool { out }
    func extinguish() { out = true }

    func update(dt: CGFloat, t: TimeInterval, in scene: SnowScene) -> Bool {
        if out { return false }
        for s in scene.visibleWindows {
            let d = hypot(s.rect.midX - fireX, s.rect.maxY - 100)
            s.pile.melt(by: (0.2 + 1.4 * max(0, 1 - d / 1100)) * dt)
        }
        scene.ground.melt(by: 0.12 * dt)
        scene.ground.melt(by: 6 * dt, fromX: fireX - 110, toX: fireX + 110)
        return true
    }
}
