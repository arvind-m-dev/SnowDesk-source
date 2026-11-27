import AppKit
import SpriteKit
import ServiceManagement
import SceneKit
import Metal
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var overlays: [(window: NSWindow, scene: SnowScene)] = []
    private var statusItem: NSStatusItem!
    private let settings = Settings.shared
    private let room = CozyRoom()
    private let decor = DesktopDecor()
    private var clickMonitor: Any?
    private var calendarTimer: Timer?
    private var hideKey: HotKey?
    private var hiddenAll = false

    private var scenes: [SnowScene] { overlays.map(\.scene) }
    private var primary: SnowScene? { overlays.first?.scene }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildOverlays()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "SnowDesk")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Clicks anywhere (for presents and double-click-to-thaw). Mouse monitoring needs no special permission.
        // Plain clicks always belong to your apps; SnowDesk only reacts to ⌘-clicks (sky effects like fireworks).
        // ⌘ over an object (snowman, present...) is caught by the overlay itself so it can be dragged.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            let p = NSEvent.mouseLocation
            if e.modifierFlags.contains(.command) { self?.scenes.forEach { $0.handleClick(globalPoint: p, count: e.clickCount) } }
            if e.clickCount >= 2 { self?.scenes.forEach { $0.thawFrost() } }     // a double-click thaws every display
        }

        // Rest completely while the screen sleeps or is locked; follow Low Power Mode.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(screensAsleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensAwake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensAsleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensAwake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(self, selector: #selector(screensAsleep), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dn.addObserver(self, selector: #selector(screensAwake), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyPerformance), name: .NSProcessInfoPowerStateDidChange, object: nil)

        // ⌃⌥S hides or shows everything.
        hideKey = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey)) { [weak self] in self?.toggleHidden() }

        WeatherService.shared.onChange = { [weak self] kind in self?.setWeather(kind, fromService: true) }
        WeatherService.shared.start()
        if settings.roomShown { room.show() }
        applyDecor()
        checkCalendar()
        // Seasons and festivals change with the date: look again every hour.
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkCalendar() }
        runDevArguments()
    }

    // MARK: - Developer flags (for testing without screen recording)
    //   --demo santa,bury,plough,frost,fire,lights,globe,room,rain,...   run actions at launch
    //   --snapshot DIR SECONDS                                          save what SnowDesk draws as PNGs
    //   --render-wallpapers DIR                                         paint all wallpapers at 1920×1080 and quit

    private func runDevArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String, _ k: Int = 1) -> String? {
            guard let i = args.firstIndex(of: flag), i + k < args.count else { return nil }
            return args[i + k]
        }
        if let dir = value("--render-wallpapers") {
            for i in Wallpapers.names.indices {
                if let img = Wallpapers.render(i, w: 1920, h: 1080) { savePNG(img, URL(fileURLWithPath: dir).appendingPathComponent("wallpaper-\(i).png")) }
            }
            NSApp.terminate(nil)
            return
        }
        if let path = value("--render-snowcat") {
            let frames = Snowcat3D(width: 420).frames()
            if let cg = frames.first?.cgImage() { savePNG(cg, URL(fileURLWithPath: path)) }
            NSApp.terminate(nil)
            return
        }
        if let list = value("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                for a in list.split(separator: ",").map(String.init) {
                    switch a {
                    case "santa": primary?.callSanta()
                    case "bury": bury()
                    case "plough": plough()
                    case "snowman":
                        guard let sc = primary, let sm = sc.effect(of: SnowmanSystem.self) else { break }
                        for (k, r) in [CGFloat(26), 20, 15].enumerated() {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 1.5) {
                                sm.testDrop(at: CGPoint(x: sc.size.width * 0.3, y: sc.size.height * 0.6), radius: r, vel: .zero, thrown: false, in: sc)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.log("snowman: \(sm.summary)") }
                    case "snowball":
                        guard let sc = primary, let sm = sc.effect(of: SnowmanSystem.self) else { break }
                        sm.testDrop(at: CGPoint(x: sc.size.width * 0.2, y: sc.size.height * 0.5), radius: 18,
                                    vel: CGVector(dx: 900, dy: -300), thrown: true, in: sc)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.log("snowball: \(sm.summary) chunks=\(sc.chunks.count)") }
                    case "present":
                        guard let sc = primary else { break }
                        let p = PresentEffect(at: CGPoint(x: sc.size.width * 0.5, y: sc.size.height * 0.7), vx: 0, scene: sc)
                        sc.add(p)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.log("present: perched=\(p.isPerched) at=\(p.position)")
                            let g = CGPoint(x: p.position.x + sc.screenFrame.minX, y: p.position.y + 10 + sc.screenFrame.minY)
                            sc.handleClick(globalPoint: g, count: 1)
                            self.log("present: opened=\(p.isOpened)")
                        }
                    case "thaw":
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                            scenes.forEach { $0.handleClick(globalPoint: CGPoint(x: $0.screenFrame.midX, y: $0.screenFrame.midY), count: 2) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.log("thaw: frozen=\(self.primary?.isFrozen ?? false)") }
                        }
                    case "clear": clearSnow()
                    case "follow":
                        WeatherService.shared.follow(city: "Oslo") { r in
                            self.log("follow: \(r)")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                self.log("follow: summary=\(WeatherService.shared.lastSummary ?? "nil") sceneWeather=\(self.primary?.weather.rawValue ?? "")")
                            }
                        }
                    case "decorate":
                        room.show()
                        log("decorate: ornaments=\(room.testDecorate())")
                    case "deep": scenes.forEach { sc in for c in 0..<sc.ground.count { sc.ground.add(c, 26 + 6 * sin(CGFloat(c) * 0.05)) } }
                    case "frost": freeze()
                    case "fire": decor.apply(fire: true, trees: settings.treeStyle)
                    case "lights": scenes.forEach { $0.setLights(.twinkle) }
                    case "globe": globe()
                    case "room": room.show()
                    case "skier": primary?.sendRider(.skier)
                    case "forest": settings.treeStyle = 2; applyDecor()
                    case "grabtest":
                        guard let sc = primary, let win = overlays.first?.window else { break }
                        sc.snowmen.build(.classic, in: sc, at: 300)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.log("grab: ignoresMouse(before)=\(win.ignoresMouseEvents)")
                            let p0 = sc.perched.last!.node.position
                            func ev(_ t: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                                NSEvent.mouseEvent(with: t, location: p, modifierFlags: .command, timestamp: 0, windowNumber: win.windowNumber,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                            }
                            let a = CGPoint(x: p0.x, y: p0.y + 20)
                            sc.mouseDown(with: ev(.leftMouseDown, a))
                            sc.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: 700, y: 500)))
                            sc.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: 900, y: 600)))
                            sc.mouseUp(with: ev(.leftMouseUp, CGPoint(x: 900, y: 600)))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                let p = sc.perched.last!
                                self.log("grab: from=\(p0) to=\(p.node.position) window=\(p.windowID.map(String.init) ?? "ground") count=\(sc.snowmen.count)")
                                sc.mouseDown(with: ev(.leftMouseDown, CGPoint(x: p.node.position.x, y: p.node.position.y + 20)))
                                sc.mouseUp(with: ev(.leftMouseUp, CGPoint(x: p.node.position.x, y: p.node.position.y + 20)))
                                self.log("grab: after cmd-click count=\(sc.snowmen.count) ignoresMouse=\(win.ignoresMouseEvents)")
                            }
                        }
                    case "hidetest":
                        toggleHidden()
                        log("hide: visible=\(overlays.map { $0.window.isVisible }) paused=\(scenes.map(\.isPaused))")
                        toggleHidden()
                        log("show: visible=\(overlays.map { $0.window.isVisible }) paused=\(scenes.map(\.isPaused))")
                    case "sledder": primary?.sendRider(.sledder)
                    case "birds": scenes.forEach { $0.setScenery([.birds, .butterflies]) }
                    case "bats": scenes.forEach { $0.setScenery([.birds, .bats]) }
                    case "stress":
                        // Everything on, events cycling, riders and snowmen; logs node counts and memory.
                        scenes.forEach { $0.setScenery(Set(Scenery.allCases)); $0.weathers = [.snow, .rain, .leaves, .mist] }
                        var k = 0
                        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                            guard let self, let sc = self.primary else { return }
                            k += 1
                            if k % 2 == 0 { sc.setEvent(EventKind.allCases[(k / 2) % EventKind.allCases.count]) }
                            sc.sendRider(k % 3 == 0 ? .sledder : .skier)
                            sc.snowmen.build(SnowmanStyle.allCases[k % SnowmanStyle.allCases.count], in: sc)
                            if k % 4 == 0 { sc.snowGlobe() }
                            if k % 5 == 0 { self.toggleHidden(); self.toggleHidden() }
                            var nodes = 0
                            sc.enumerateChildNodes(withName: "//*") { _, _ in nodes += 1 }
                            var info = mach_task_basic_info()
                            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
                            _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
                            self.log("stress t=\(k * 10)s nodes=\(nodes) effects=\(sc.effects.count) perched=\(sc.perched.count) flakes=\(sc.flakes.count) chunks=\(sc.chunks.count) rssMB=\(info.resident_size / 1_048_576)")
                        }
                    case "river": settings.scenery.insert(.river); applyDecor()
                    case let x where x.hasPrefix("season-"):
                        if let se = Season(rawValue: String(x.dropFirst(7))) { applySeason(se, wallpaper: false) }
                    case let x where x.hasPrefix("event-"):
                        if let ev = EventKind(rawValue: String(x.dropFirst(6))) { scenes.forEach { $0.setEvent(ev) } }
                    case let x where x.hasPrefix("snowmen"):
                        if let sc = primary {
                            for (i, st) in SnowmanStyle.allCases.enumerated() where st != .melting {
                                sc.snowmen.build(st, in: sc, at: sc.size.width * (0.08 + CGFloat(i) * 0.15))
                            }
                        }
                    case let x where x.hasPrefix("weathers-"):
                        let ks = Set(x.dropFirst(9).split(separator: "+").compactMap { WeatherKind(rawValue: String($0)) })
                        scenes.forEach { $0.weathers = ks }
                    default: if let k = WeatherKind(rawValue: a) { scenes.forEach { $0.weather = k } }
                    }
                }
            }
        }
        if let dir = value("--snapshot") {
            let delay = Double(value("--snapshot", 2) ?? "") ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                for (i, sc) in scenes.enumerated() {
                    let kinds = sc.effects.map { String(describing: type(of: $0)) }
                    let bats = sc.perched.filter { abs($0.node.zRotation - .pi) < 0.01 }.count
                    log("scene\(i): hangingBats=\(bats) perchedNodes=\(sc.perched.count)")
                    log("scene\(i): flakes=\(sc.flakes.count) chunks=\(sc.chunks.count) perched=\(sc.perched.count) slope=\(sc.ground.maxSlope) ploughs=\(sc.ground.ploughsActive) windows=\(sc.visibleWindows.count) effects=\(kinds)")
                }
                for (i, o) in overlays.enumerated() {
                    guard let view = o.window.contentView as? SKView,
                          let img = view.texture(from: o.scene, crop: o.scene.frame)?.cgImage() else { continue }
                    savePNG(img, URL(fileURLWithPath: dir).appendingPathComponent("overlay-\(i).png"), backdrop: true)
                }
                room.snapshot().map { savePNG($0, URL(fileURLWithPath: dir).appendingPathComponent("room.png")) }
                decor.snapshot().map { savePNG($0, URL(fileURLWithPath: dir).appendingPathComponent("decor.png"), backdrop: true) }
            }
        }
    }

    private func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

    private func savePNG(_ img: CGImage, _ url: URL, backdrop: Bool = false) {
        var out = img
        if backdrop, let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(srgbRed: 0.25, green: 0.3, blue: 0.4, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
            // Draw the real window outlines so piles can be judged against them.
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
            let sx = CGFloat(img.width) / (primary?.size.width ?? 1)
            for w in primary?.visibleWindows ?? [] { ctx.stroke(w.rect.applying(CGAffineTransform(scaleX: sx, y: sx)), width: 2) }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            out = ctx.makeImage() ?? img
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: - Overlays (one per screen)

    private func buildOverlays() {
        // Keep long-lived toggles across rebuilds.
        for o in overlays {                     // shut the old ones down properly (mic, effects, window)
            o.scene.setLights(.off)
            Retire.window(o.window)
        }
        overlays = []
        let skip = ProcessInfo.processInfo.arguments.contains("--skip-overlay")   // dev: isolate window issues
        for (i, screen) in Displays.active.enumerated() where !skip {
            let frame = screen.frame
            // A non-activating panel: even when it briefly catches a ⌘-drag it never takes focus from your app.
            let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true                      // fully click-through
            // Above app windows (and floating ones like picture-in-picture) but just below the Dock and menu bar,
            // so an auto-hiding Dock still slides up and is never covered by snow.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]   // hidden during Mission Control
            window.isReleasedWhenClosed = false

            let view = OverlaySKView(frame: NSRect(origin: .zero, size: frame.size))
            view.allowsTransparency = true
            view.ignoresSiblingOrder = true
            view.preferredFramesPerSecond = Performance.current.fps

            let scene = SnowScene(screenFrame: frame, isPrimary: i == 0)
            scene.enabled = settings.snowing
            scene.weathers = settings.weathers
            scene.targetFlakes = settings.intensity.flakeCount
            view.presentScene(scene)

            window.contentView = view
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            overlays.append((window, scene))

            if settings.lightsMode != .off { scene.setLights(settings.lightsMode) }
            DispatchQueue.main.async { [settings] in
                scene.setScenery(settings.scenery)
                scene.setEvent(settings.activeEvent)
            }
            if hiddenAll { window.orderOut(nil) }
            if hiddenAll || asleep { scene.isPaused = true; view.isPaused = true }
        }
    }

    @objc private func screensChanged() {
        buildOverlays()
        room.rebuildForScreenChange()
        decor.rebuildForScreenChange(fire: settings.fireplace, trees: settings.treeStyle, river: settings.scenery.contains(.river), season: settings.season)
        applyDecor()
        decor.setHidden(hiddenAll)
    }

    /// Fireplace and trees sit on the desktop layer, behind all app windows.
    private func applyDecor() {
        if ProcessInfo.processInfo.arguments.contains("--skip-decor") { return }
        decor.apply(fire: settings.fireplace, trees: settings.treeStyle, river: settings.scenery.contains(.river), season: settings.season)
        primary?.setFireWarmth(at: decor.fireX.map { $0 + (Displays.home?.frame.minX ?? 0) })
    }

    // MARK: - Menu (rebuilt every time it opens, so checkmarks are always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hide = item(hiddenAll ? "Show SnowDesk" : "Hide SnowDesk for Now", #selector(toggleHidden))
        hide.keyEquivalent = "s"
        hide.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(hide)
        menu.addItem(.separator())
        menu.addItem(item("Let It Snow", #selector(toggleEnabled), on: settings.snowing))

        let weather = NSMenu()
        weather.addItem(item("Mix Several Weathers", #selector(toggleMix), on: settings.mixWeathers))
        weather.addItem(.separator())
        let chosen = settings.weathers
        for (i, k) in WeatherKind.allCases.enumerated() {
            let it = item(k.title, #selector(pickWeather(_:)), on: k == .clear ? chosen.isEmpty : chosen.contains(k))
            it.tag = i
            weather.addItem(it)
        }
        weather.addItem(.separator())
        if let summary = WeatherService.shared.lastSummary ?? settings.cityName.map({ "Following \($0)" }) {
            let info = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
            info.isEnabled = false
            weather.addItem(info)
            weather.addItem(item("Stop Following the Weather", #selector(stopFollowing)))
        }
        weather.addItem(item(settings.cityName == nil ? "Follow the Weather in My City…" : "Change City…", #selector(followCity)))
        menu.addItem(submenu(settings.mixWeathers && chosen.count > 1 ? "Weather (\(chosen.count) mixed)" : "Weather", weather))

        let seasons = NSMenu()
        seasons.addItem(item("Follow the Calendar", #selector(toggleAutoSeason), on: settings.autoSeason))
        seasons.addItem(.separator())
        for (i, se) in Season.allCases.enumerated() {
            let it = item(se.title, #selector(pickSeason(_:)), on: settings.season == se)
            it.tag = i
            seasons.addItem(it)
        }
        seasons.addItem(.separator())
        seasons.addItem(item("Change Wallpaper Too", #selector(toggleThemeWallpaper), on: settings.themeWallpaper))
        menu.addItem(submenu("Season: \(settings.season.title)", seasons))

        let events = NSMenu()
        let today = EventKind.on().map { " (now: \($0.title))" } ?? ""
        let auto = item("Automatic by Date" + today, #selector(pickEvent(_:)), on: settings.eventChoice == "auto")
        auto.representedObject = "auto"
        events.addItem(auto)
        let none = item("None", #selector(pickEvent(_:)), on: settings.eventChoice == "")
        none.representedObject = ""
        events.addItem(none)
        events.addItem(.separator())
        for ev in EventKind.allCases {
            let it = item(ev.title, #selector(pickEvent(_:)), on: settings.eventChoice == ev.rawValue)
            it.representedObject = ev.rawValue
            events.addItem(it)
        }
        menu.addItem(submenu("Events and Festivals", events))

        let nature = NSMenu()
        for (i, sc) in Scenery.allCases.enumerated() {
            let it = item(sc.title, #selector(toggleScenery(_:)), on: settings.scenery.contains(sc))
            it.tag = i
            nature.addItem(it)
        }
        nature.addItem(.separator())
        nature.addItem(item("Birds and Bats Perch on Buttons, Rows and Lines", #selector(toggleUIPerches), on: UIPerches.allowed))
        nature.addItem(.separator())
        nature.addItem(item("Send a Skier Now", #selector(sendSkier)))
        nature.addItem(item("Send a Sledder Now", #selector(sendSledder)))
        menu.addItem(submenu("Nature and Life", nature))

        let builds = NSMenu()
        for st in SnowmanStyle.allCases {
            let it = item(st.title, #selector(buildSnowman(_:)))
            it.tag = st.rawValue
            builds.addItem(it)
        }
        builds.addItem(.separator())
        builds.addItem(item("Surprise Me", #selector(buildSnowman(_:))))
        builds.items.last?.tag = -1
        builds.addItem(item("Knock Them All Down", #selector(knockSnowmen)))
        let tip = NSMenuItem(title: "Click a snowman to knock it over", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        builds.addItem(tip)
        menu.addItem(submenu("Build a Snowman", builds))

        let intensity = NSMenu()
        for level in Intensity.allCases {
            let it = item(level.title, #selector(setIntensity(_:)), on: settings.intensity == level)
            it.tag = level.rawValue
            intensity.addItem(it)
        }
        menu.addItem(submenu("Intensity", intensity))

        menu.addItem(.separator())
        menu.addItem(item("Call Santa", #selector(callSanta)))
        menu.addItem(item("Bury My Desktop in Snow", #selector(bury)))
        menu.addItem(item("Send in the Snowplough", #selector(plough)))
        menu.addItem(item("Freeze the Screen", #selector(freeze), on: primary?.isFrozen ?? false))
        menu.addItem(item("Light the Fireplace", #selector(toggleFire), on: settings.fireplace))
        let trees = NSMenu()
        for (i, name) in ["Off", "A Few Trees", "Small Forest"].enumerated() {
            let it = item(name, #selector(setTrees(_:)), on: settings.treeStyle == i)
            it.tag = i
            trees.addItem(it)
        }
        menu.addItem(submenu("Trees Along the Bottom", trees))

        let lights = NSMenu()
        for m in LightsMode.allCases {
            let it = item(m.title, #selector(setLights(_:)), on: settings.lightsMode == m)
            it.tag = m.rawValue
            lights.addItem(it)
        }
        menu.addItem(submenu("Christmas Lights", lights))

        let roomMenu = NSMenu()
        roomMenu.addItem(item("Show Cozy Room on Desktop (covers wallpaper)", #selector(toggleRoom), on: room.isShown))
        roomMenu.addItem(item("Decorate My Tree…", #selector(decorate)))
        roomMenu.addItem(.separator())
        for (i, name) in CozyRoom.themes.enumerated() {
            let it = item(name, #selector(pickRoom(_:)), on: settings.roomTheme == i)
            it.tag = i
            roomMenu.addItem(it)
        }
        menu.addItem(submenu("Christmas Tree", roomMenu))

        let walls = NSMenu()
        for (g, (heading, indices)) in Wallpapers.groups.enumerated() {
            if g > 0 { walls.addItem(.separator()) }
            walls.addItem(NSMenuItem.sectionHeader(title: heading))
            for i in indices {
                let it = item(Wallpapers.names[i], #selector(pickWallpaper(_:)))
                it.tag = i
                walls.addItem(it)
            }
        }
        menu.addItem(submenu("Wallpapers", walls))

        menu.addItem(item("Snow Globe", #selector(globe)))
        menu.addItem(item("Shake Off All Snow", #selector(clearSnow)))

        menu.addItem(.separator())
        if NSScreen.screens.count > 1 {
            let displays = NSMenu()
            let chosen = Displays.active.count == 1 ? Displays.active[0].displayID : 0
            let all = item("All Displays", #selector(pickDisplay(_:)), on: chosen == 0)
            all.representedObject = NSNumber(value: 0)
            displays.addItem(all)
            displays.addItem(.separator())
            for (i, s) in NSScreen.screens.enumerated() {
                let it = item(s.localizedName + (i == 0 ? " (main)" : ""), #selector(pickDisplay(_:)), on: chosen == s.displayID)
                it.representedObject = NSNumber(value: s.displayID)
                displays.addItem(it)
            }
            menu.addItem(submenu("Show On", displays))
        }
        let perf = NSMenu()
        for p in Performance.allCases {
            let it = item(p.title, #selector(setPerformance(_:)), on: Performance.chosen == p)
            it.tag = p.rawValue
            perf.addItem(it)
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            perf.addItem(.separator())
            let note = NSMenuItem(title: "Low Power Mode is on: using Battery Saver", action: nil, keyEquivalent: "")
            note.isEnabled = false
            perf.addItem(note)
        }
        menu.addItem(submenu("Performance", perf))
        menu.addItem(item("Sounds", #selector(toggleSounds), on: settings.sounds))
        menu.addItem(item("Santa Drops By Now and Then", #selector(toggleSantaVisits), on: settings.santaVisits))
        menu.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))

        let tips = NSMenu()
        for t in ["Shake a window to knock its snow off",
                  "Sweep the pointer through snow to dig it",
                  "Hold ⌥ and sweep through snow to roll a snowball",
                  "Let go of ⌥ to drop it; stack three for a snowman",
                  "Fling it while letting go to throw a snowball",
                  "Shake the mouse for a snow globe",
                  "Plain clicks always go to your apps; things fade when the pointer is near",
                  "Hold ⌘ and drag a snowman, present or decoration to move it",
                  "⌘-click a present to open it, or a snowman to knock it over",
                  "⌘-click the sky during New Year, Diwali or Holi",
                  "Move the pointer near a perched bird or hanging bat to scare it off",
                  "Press ⌃⌥S to hide or show SnowDesk",
                  "Frozen screen: move the pointer to scrape, double-click to thaw"] {
            let it = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            it.isEnabled = false
            tips.addItem(it)
        }
        menu.addItem(submenu("Tips", tips))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SnowDesk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.state = on ? .on : .off
        return it
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.snowing.toggle()
        scenes.forEach { $0.enabled = settings.snowing }
    }

    @objc private func pickWeather(_ sender: NSMenuItem) {
        let k = WeatherKind.allCases[sender.tag]
        if WeatherService.shared.isFollowing { WeatherService.shared.stop() }
        var set = settings.weathers
        if k == .clear {
            set = []
        } else if settings.mixWeathers {
            if set.contains(k) { set.remove(k) } else { set.insert(k) }
        } else {
            set = [k]
        }
        setWeathers(set)
    }

    private func setWeather(_ kind: WeatherKind, fromService: Bool) {
        if !fromService && WeatherService.shared.isFollowing { WeatherService.shared.stop() }
        setWeathers(kind == .clear ? [] : [kind])
    }

    private func setWeathers(_ set: Set<WeatherKind>) {
        settings.weathers = set
        scenes.forEach { $0.weathers = set }
    }

    @objc private func setPerformance(_ sender: NSMenuItem) {
        Performance.chosen = Performance(rawValue: sender.tag) ?? .balanced
        applyPerformance()
    }

    @objc private func applyPerformance() {
        DispatchQueue.main.async { [self] in
            let p = Performance.current
            for o in overlays {
                (o.window.contentView as? SKView)?.preferredFramesPerSecond = p.fps
                o.scene.pollInterval = p.poll
                o.scene.targetFlakes = settings.intensity.flakeCount
            }
        }
    }

    private var asleep = false
    @objc private func screensAsleep() { asleep = true; updatePaused() }
    @objc private func screensAwake() { asleep = false; updatePaused() }

    /// Nothing is drawn while hidden, asleep or locked, so SpriteKit stops entirely (no CPU, no GPU).
    private func updatePaused() {
        let stop = hiddenAll || asleep
        for o in overlays {
            o.scene.isPaused = stop
            (o.window.contentView as? SKView)?.isPaused = stop
        }
        decor.setPaused(stop)
    }

    @objc private func toggleHidden() {
        hiddenAll.toggle()
        for o in overlays {
            if hiddenAll { o.window.orderOut(nil) } else { o.window.orderFrontRegardless() }
        }
        decor.setHidden(hiddenAll)
        updatePaused()
    }

    @objc private func toggleMix() { settings.mixWeathers.toggle() }

    // MARK: Seasons, events, nature

    /// Dress everything for a season: weather, scenery, trees, river and (optionally) wallpaper.
    private func applySeason(_ se: Season, wallpaper: Bool) {
        settings.season = se
        if !settings.snowing { settings.snowing = true; scenes.forEach { $0.enabled = true } }
        setWeathers(se.weathers)
        settings.scenery = se.scenery
        scenes.forEach { $0.setScenery(se.scenery) }
        if settings.treeStyle == 0 { settings.treeStyle = 2 }
        applyDecor()
        if wallpaper { setWallpaper(se.wallpaper) }
    }

    @objc private func pickSeason(_ sender: NSMenuItem) {
        settings.autoSeason = false
        applySeason(Season.allCases[sender.tag], wallpaper: settings.themeWallpaper)
    }

    @objc private func toggleAutoSeason() {
        settings.autoSeason.toggle()
        if settings.autoSeason { checkCalendar(force: true) }
    }

    @objc private func toggleThemeWallpaper() { settings.themeWallpaper.toggle() }

    private func applyEvent(_ ev: EventKind?) {
        scenes.forEach { $0.setEvent(ev) }
        guard let ev else { return }
        if let w = ev.weathers { setWeathers(w) }
        if ev == .christmas && settings.lightsMode == .off {
            settings.lightsMode = .twinkle
            scenes.forEach { $0.setLights(.twinkle) }
        }
        if settings.themeWallpaper, let wp = ev.wallpaper { setWallpaper(wp) }
    }

    @objc private func pickEvent(_ sender: NSMenuItem) {
        settings.eventChoice = sender.representedObject as? String ?? "auto"
        applyEvent(settings.activeEvent)
        UserDefaults.standard.set(settings.activeEvent?.rawValue ?? "", forKey: "lastEvent")
    }

    /// Follows the calendar: a new season (when automatic) or a festival starting or ending.
    private func checkCalendar(force: Bool = false) {
        if settings.autoSeason {
            let se = Season.current(latitude: settings.cityName == nil ? 1 : settings.cityLat)
            if se != settings.season || force { applySeason(se, wallpaper: settings.themeWallpaper) }
        }
        let ev = settings.activeEvent
        let key = "lastEvent"
        if UserDefaults.standard.string(forKey: key) != (ev?.rawValue ?? "") {
            UserDefaults.standard.set(ev?.rawValue ?? "", forKey: key)
            applyEvent(ev)
        } else {
            scenes.forEach { $0.setEvent(ev) }
        }
    }

    @objc private func toggleScenery(_ sender: NSMenuItem) {
        let sc = Scenery.allCases[sender.tag]
        var set = settings.scenery
        if set.contains(sc) { set.remove(sc) } else { set.insert(sc) }
        settings.scenery = set
        scenes.forEach { $0.setScenery(set) }
        if sc == .river { applyDecor() }
    }

    @objc private func toggleUIPerches() {
        if UIPerches.allowed { UIPerches.wanted = false; return }
        UIPerches.wanted = true
        if !UIPerches.requestAccess() {
            let a = NSAlert()
            a.messageText = "Let SnowDesk see buttons and rows"
            a.informativeText = "To perch on buttons, rows, toolbars and dividers inside your apps, SnowDesk needs Accessibility access. It only reads where things are on screen, never their contents, and never clicks or types.\n\nTurn on SnowDesk in System Settings › Privacy & Security › Accessibility. Birds and bats start using it within a few seconds."
            a.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    @objc private func sendSkier() { primary?.sendRider(.skier) }
    @objc private func sendSledder() { primary?.sendRider(.sledder) }

    @objc private func buildSnowman(_ sender: NSMenuItem) {
        guard let sc = primary else { return }
        let style = SnowmanStyle(rawValue: sender.tag) ?? SnowmanStyle.allCases.randomElement()!
        sc.snowmen.build(style, in: sc)
    }

    @objc private func knockSnowmen() { scenes.forEach { $0.snowmen.knockAll(in: $0) } }

    @objc private func followCity() {
        let alert = NSAlert()
        alert.messageText = "Follow the weather in your city"
        alert.informativeText = "SnowDesk checks the forecast every 30 minutes using Open-Meteo (free, no account). Only the city you type is sent."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g. Chennai, Oslo, Toronto"
        field.stringValue = settings.cityName ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Follow")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let city = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { return }
        WeatherService.shared.follow(city: city) { result in
            if case let .failure(err) = result {
                let a = NSAlert()
                a.messageText = "Couldn't follow that city"
                a.informativeText = err.localizedDescription
                a.runModal()
            }
        }
    }

    @objc private func stopFollowing() { WeatherService.shared.stop() }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        guard let level = Intensity(rawValue: sender.tag) else { return }
        settings.intensity = level
        scenes.forEach { $0.targetFlakes = level.flakeCount }
    }

    @objc private func callSanta() { primary?.callSanta() }
    @objc private func bury() { scenes.forEach { $0.buryDesktop() } }
    @objc private func plough() { scenes.forEach { $0.sendPlough() } }
    /// Freeze or thaw every display together.
    @objc private func freeze() {
        let freezeNow = !(primary?.isFrozen ?? false)
        scenes.forEach { if $0.isFrozen != freezeNow { $0.toggleFrost() } }
    }
    @objc private func globe() { scenes.forEach { $0.snowGlobe() } }
    @objc private func clearSnow() { scenes.forEach { $0.clearAllSnow() } }

    @objc private func toggleFire() {
        settings.fireplace.toggle()
        applyDecor()
    }

    @objc private func setTrees(_ sender: NSMenuItem) {
        settings.treeStyle = sender.tag
        applyDecor()
    }

    @objc private func setLights(_ sender: NSMenuItem) {
        guard let m = LightsMode(rawValue: sender.tag) else { return }
        settings.lightsMode = m
        scenes.forEach { $0.setLights(m) }
    }

    @objc private func toggleRoom() { room.isShown ? room.hide() : room.show() }
    @objc private func decorate() { room.startDecorating() }
    @objc private func pickRoom(_ sender: NSMenuItem) {
        room.setTheme(sender.tag)
        if !room.isShown { room.show() }
    }

    @objc private func pickWallpaper(_ sender: NSMenuItem) { setWallpaper(sender.tag) }

    private func setWallpaper(_ index: Int) {
        // The cozy room is drawn over the wallpaper, so it would hide the new one.
        if room.isShown { room.hide() }
        Wallpapers.apply(index) { error in
            guard let error else { return }
            let a = NSAlert()
            a.messageText = "Couldn't set the wallpaper"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc private func pickDisplay(_ sender: NSMenuItem) {
        settings.displayID = (sender.representedObject as? NSNumber)?.uint32Value ?? 0
        screensChanged()
    }

    @objc private func toggleSounds() {
        settings.sounds.toggle()
        Sound.shared.soundsChanged()
    }
    @objc private func toggleSantaVisits() { settings.santaVisits.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change login setting"
            alert.informativeText = "Move SnowDesk.app to your Applications folder and try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
}

/// Lets the very first click reach the scene (for ⌘-drag) without activating SnowDesk.
final class OverlaySKView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
