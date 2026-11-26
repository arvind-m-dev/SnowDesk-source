import SpriteKit

/// A heightmap of settled snow sitting on a horizontal ledge (a window's top edge, or the screen bottom).
/// Local coordinates: x from 0 to `width`, y up from the ledge.
final class Pile {
    static let colW: CGFloat = 3

    private(set) var heights: [CGFloat]
    var exposed: [Bool]
    var maxHeight: CGFloat
    /// Steepest step between neighbouring columns before snow slumps (raised while ploughing so walls hold).
    var maxSlope: CGFloat = 1.3
    let node = SKShapeNode()
    var dirty = true

    /// Height at which a drift breaks loose and slides off (re-rolled after every slide).
    private var avalancheAt: CGFloat = .random(in: 15...21)
    private var spillLeft: CGFloat = 0
    private var spillRight: CGFloat = 0

    init(width: CGFloat, maxHeight: CGFloat) {
        let n = max(1, Int(width / Pile.colW))
        heights = Array(repeating: 0, count: n)
        exposed = Array(repeating: true, count: n)
        self.maxHeight = maxHeight
        node.fillColor = NSColor(calibratedWhite: 1, alpha: 0.97)
        node.strokeColor = NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.92, alpha: 0.85)
        node.lineWidth = 1
        node.isAntialiased = true
    }

    var count: Int { heights.count }
    var width: CGFloat { CGFloat(heights.count) * Pile.colW }
    var isEmpty: Bool { !heights.contains { $0 > 0.3 } }

    func column(forLocalX x: CGFloat) -> Int? {
        let c = Int(x / Pile.colW)
        return (c >= 0 && c < heights.count) ? c : nil
    }

    func height(at c: Int) -> CGFloat { heights[c] }

    func resize(to width: CGFloat) {
        let n = max(1, Int(width / Pile.colW))
        guard n != heights.count else { return }
        let old = heights
        heights = (0..<n).map { i in
            let src = Int(CGFloat(i) / CGFloat(n) * CGFloat(old.count))
            return old[min(src, old.count - 1)]
        }
        exposed = Array(repeating: true, count: n)
        dirty = true
    }

    func deposit(column c: Int, amount: CGFloat) {
        heights[c] += amount * 0.5
        let side = amount * 0.25
        if c > 0, exposed[c - 1] { heights[c - 1] += side } else { heights[c] += side }
        if c + 1 < heights.count, exposed[c + 1] { heights[c + 1] += side } else { heights[c] += side }
        dirty = true
    }

    func setHeight(_ c: Int, _ h: CGFloat) {
        heights[c] = max(0, h)
        dirty = true
    }

    /// Lifts `fraction` of the snow off every column; returns (localX, amount lifted).
    func loft(fraction: CGFloat) -> [(x: CGFloat, h: CGFloat)] {
        var out: [(CGFloat, CGFloat)] = []
        for i in heights.indices where heights[i] > 0.6 {
            let r = heights[i] * fraction
            heights[i] -= r
            out.append((CGFloat(i) * Pile.colW + Pile.colW / 2, r))
        }
        if !out.isEmpty { dirty = true }
        return out
    }

    /// If the drift has grown past its breaking point, a slab around the tallest spot breaks loose.
    /// Returns (localX, amount, direction) samples for the snow that slid off; direction points to the nearer end.
    func checkAvalanche() -> [(x: CGFloat, h: CGFloat, dir: CGFloat)] {
        guard let peak = heights.indices.max(by: { heights[$0] < heights[$1] }),
              heights[peak] >= avalancheAt else { return [] }
        avalancheAt = .random(in: 15...21)
        let half = Int.random(in: 12...40)                       // 36–120 px either side
        let lo = max(0, peak - half), hi = min(heights.count - 1, peak + half)
        let dir: CGFloat = peak < heights.count / 2 ? -1 : 1
        var out: [(CGFloat, CGFloat, CGFloat)] = []
        for i in lo...hi where heights[i] > 1 {
            let edge = 1 - abs(CGFloat(i - peak)) / CGFloat(half + 1)   // breaks deepest at the peak
            let r = heights[i] * (0.35 + 0.45 * edge)
            heights[i] -= r
            out.append((CGFloat(i) * Pile.colW + Pile.colW / 2, r, dir))
        }
        dirty = true
        return out
    }

    /// Melts columns whose centre lies within [fromX, toX] (local coordinates).
    func melt(by amount: CGFloat, fromX: CGFloat, toX: CGFloat) {
        let lo = max(0, Int(fromX / Pile.colW)), hi = min(heights.count - 1, Int(toX / Pile.colW))
        guard lo <= hi else { return }
        for i in lo...hi where heights[i] > 0 {
            heights[i] = max(0, heights[i] - amount)
            dirty = true
        }
    }

    func add(_ c: Int, _ amount: CGFloat) {
        heights[c] = min(maxHeight, heights[c] + amount)
        dirty = true
    }

    func clearColumn(_ c: Int) {
        if heights[c] > 0 { heights[c] = 0; dirty = true }
    }

    func melt(by amount: CGFloat) {
        for i in heights.indices where heights[i] > 0 {
            heights[i] = max(0, heights[i] - amount)
            dirty = true
        }
    }

    /// Removes all snow and returns it as (localX, height) samples so the caller can spawn falling chunks.
    func takeAll() -> [(x: CGFloat, h: CGFloat)] {
        var out: [(CGFloat, CGFloat)] = []
        for i in heights.indices where heights[i] > 0.6 {
            out.append((CGFloat(i) * Pile.colW + Pile.colW / 2, heights[i]))
        }
        heights = Array(repeating: 0, count: heights.count)
        dirty = true
        return out
    }

    /// Lets snow slump into a natural slope; snow spills off open ends.
    /// Returns local x positions where a lump of snow fell off the edge.
    func settle(spillsAtEdges: Bool) -> [CGFloat] {
        let n = heights.count
        guard n > 1 else { return [] }
        for _ in 0..<2 {
            for i in 0..<(n - 1) where exposed[i] && exposed[i + 1] {
                let d = heights[i] - heights[i + 1]
                if abs(d) > maxSlope {
                    let m = (abs(d) - maxSlope) / 2 * (d > 0 ? 1 : -1)
                    heights[i] -= m
                    heights[i + 1] += m
                    dirty = true
                }
            }
        }
        for i in 0..<n where heights[i] > maxHeight {
            heights[i] = maxHeight
            dirty = true
        }
        guard spillsAtEdges else { return [] }
        var spills: [CGFloat] = []
        let edgeMax: CGFloat = 3
        if heights[0] > edgeMax {
            spillLeft += heights[0] - edgeMax
            heights[0] = edgeMax
            dirty = true
        }
        if heights[n - 1] > edgeMax {
            spillRight += heights[n - 1] - edgeMax
            heights[n - 1] = edgeMax
            dirty = true
        }
        if spillLeft > 2.5 { spills.append(0); spillLeft = 0 }
        if spillRight > 2.5 { spills.append(width); spillRight = 0 }
        return spills
    }

    func rebuildPathIfNeeded() {
        guard dirty else { return }
        dirty = false
        guard !isEmpty else {
            node.path = nil
            return
        }
        let path = CGMutablePath()
        var inRun = false
        let cw = Pile.colW
        for i in heights.indices {
            let h = exposed[i] ? heights[i] : 0
            let x = CGFloat(i) * cw
            if h > 0.3 {
                if !inRun {
                    path.move(to: CGPoint(x: x, y: -0.5))
                    path.addLine(to: CGPoint(x: x, y: min(h, 1.5)))
                    inRun = true
                }
                path.addLine(to: CGPoint(x: x + cw / 2, y: h))
            } else if inRun {
                path.addLine(to: CGPoint(x: x, y: -0.5))
                path.closeSubpath()
                inRun = false
            }
        }
        if inRun {
            path.addLine(to: CGPoint(x: width, y: -0.5))
            path.closeSubpath()
        }
        node.path = path
    }
}
