import SpriteKit

/// Where a bird sits or a bat hangs, tracked relative to its window so it rides along when the window moves.
struct Ledge {
    let windowID: CGWindowID?      // nil = the ground
    var localX: CGFloat            // from the window's left edge (scene x for the ground)
    let yRel: CGFloat              // from the window's top edge (ignored for the ground)
    let onPile: Bool               // sits on the window-top snow (adds the pile height)
    let minLocalX: CGFloat         // the ledge's ends, for hopping along it
    let maxLocalX: CGFloat
    let size: CGSize               // window size when chosen: if it changes, the ledge may have moved
}

extension SnowScene {
    /// Current scene point of a landing, or nil if its window is gone, hidden or resized.
    func point(of l: Ledge) -> CGPoint? {
        guard let id = l.windowID else {
            let c = ground.column(forLocalX: min(max(l.localX, 0), size.width - 1)) ?? 0
            return CGPoint(x: l.localX, y: ground.height(at: c))
        }
        guard let w = visibleWindows.first(where: { $0.id == id }), w.rect.size == l.size else { return nil }
        var y = w.rect.maxY + l.yRel
        if l.onPile, let c = w.pile.column(forLocalX: l.localX) { y += w.pile.height(at: c) }
        return CGPoint(x: w.rect.minX + l.localX, y: y)
    }

    /// A random free ledge. Birds sit on tops; bats hang from undersides (`hang`).
    /// Window tops and the ground always count; with Accessibility allowed, so do buttons, rows, toolbars and dividers.
    func randomLedge(hang: Bool) -> Ledge? {
        let order = WindowTracker.snapshot()             // front-most first, global coords
        let originX = screenFrame.minX, originY = screenFrame.minY
        func covered(_ g: CGPoint, ownerIndex: Int) -> Bool {
            order.prefix(ownerIndex).contains { $0.rect.insetBy(dx: -2, dy: -2).contains(g) }
        }
        var options: [Ledge] = []

        // Window top edges
        for (i, vw) in order.enumerated() {
            guard let w = windows[vw.id], w.visible else { continue }
            let r = w.rect
            guard r.width > 120, r.maxY < size.height - (hang ? 10 : 34), r.maxY > 60 else { continue }
            for _ in 0..<3 {
                let lx = CGFloat.random(in: 24...(r.width - 24))
                guard r.minX + lx > 10, r.minX + lx < size.width - 10 else { continue }     // on this display
                let g = CGPoint(x: r.minX + lx + originX, y: r.maxY + originY + (hang ? -3 : 3))
                guard !covered(g, ownerIndex: i) else { continue }
                if !hang, let c = w.pile.column(forLocalX: lx), !w.pile.exposed[c] { continue }
                options.append(Ledge(windowID: w.id, localX: lx, yRel: hang ? -1 : 0, onPile: !hang,
                                       minLocalX: 16, maxLocalX: r.width - 16, size: r.size))
                break
            }
        }

        // Buttons, rows, toolbars, dividers inside windows
        for spot in UIPerches.spots(in: order) {
            guard let i = order.firstIndex(where: { $0.id == spot.windowID }), let w = windows[spot.windowID], w.visible else { continue }
            let x = CGFloat.random(in: spot.minX...max(spot.minX, spot.maxX))
            let edge = hang ? spot.bottom : spot.top
            let g = CGPoint(x: x, y: edge + (hang ? -3 : 3))
            guard !covered(g, ownerIndex: i), g.y - originY > 30, g.y - originY < size.height - 30,
                  g.x - originX > 10, g.x - originX < size.width - 10 else { continue }
            let wTop = w.rect.maxY + originY, wLeft = w.rect.minX + originX
            options.append(Ledge(windowID: w.id, localX: x - wLeft, yRel: edge - wTop, onPile: false,
                                   minLocalX: spot.minX - wLeft, maxLocalX: spot.maxX - wLeft, size: w.rect.size))
        }
        // UI ledges are many: keep them, but leave window tops a fair chance too.
        if !hang && (options.isEmpty || Int.random(in: 0..<6) == 0) {
            let x = CGFloat.random(in: 60...max(61, size.width - 60))
            options.append(Ledge(windowID: nil, localX: x, yRel: 0, onPile: false, minLocalX: 20, maxLocalX: size.width - 20, size: .zero))
        }
        return options.randomElement()
    }
}
