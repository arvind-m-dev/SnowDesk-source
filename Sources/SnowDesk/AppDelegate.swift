import AppKit
import SpriteKit
import ServiceManagement
import SceneKit
import Metal

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var overlays: [(window: NSWindow, scene: SnowScene)] = []
    private var statusItem: NSStatusItem!
    private let settings = Settings.shared
    private let room = CozyRoom()
    private let decor = DesktopDecor()
    private var clickMonitor: Any?

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
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            let p = NSEvent.mouseLocation
            self?.scenes.forEach { $0.handleClick(globalPoint: p, count: e.clickCount) }
        }

        WeatherService.shared.onChange = { [weak self] kind in self?.setWeather(kind, fromService: true) }
        WeatherService.shared.start()
        if settings.roomShown { room.show() }
        applyDecor()
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
                    case "deep": scenes.forEach { sc in for c in 0..<sc.ground.count { sc.ground.add(c, 26 + 6 * sin(CGFloat(c) * 0.05)) } }
                    case "frost": freeze()
                    case "fire": decor.apply(fire: true, trees: settings.trees)
                    case "lights": scenes.forEach { $0.setLights(.twinkle) }
                    case "globe": globe()
                    case "room": room.show()
                    default: if let k = WeatherKind(rawValue: a) { scenes.forEach { $0.weather = k } }
                    }
                }
            }
        }
        if let dir = value("--snapshot") {
            let delay = Double(value("--snapshot", 2) ?? "") ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
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
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = []
        for (i, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true                      // fully click-through
            window.level = .statusBar                             // above app windows, below menus
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false

            let view = SKView(frame: NSRect(origin: .zero, size: frame.size))
            view.allowsTransparency = true
            view.ignoresSiblingOrder = true
            view.preferredFramesPerSecond = 60

            let scene = SnowScene(screenFrame: frame, isPrimary: i == 0)
            scene.enabled = settings.snowing
            scene.weather = settings.weather
            scene.targetFlakes = settings.intensity.flakeCount
            view.presentScene(scene)

            window.contentView = view
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            overlays.append((window, scene))

            if settings.lightsMode != .off { scene.setLights(settings.lightsMode) }
        }
    }

    @objc private func screensChanged() {
        buildOverlays()
        room.rebuildForScreenChange()
        decor.rebuildForScreenChange(fire: settings.fireplace, trees: settings.trees)
        applyDecor()
    }

    /// Fireplace and trees sit on the desktop layer, behind all app windows.
    private func applyDecor() {
        decor.apply(fire: settings.fireplace, trees: settings.trees)
        primary?.setFireWarmth(at: decor.fireX.map { $0 + (NSScreen.screens.first?.frame.minX ?? 0) })
    }

    // MARK: - Menu (rebuilt every time it opens, so checkmarks are always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Let It Snow", #selector(toggleEnabled), on: settings.snowing))

        let weather = NSMenu()
        for (i, k) in WeatherKind.allCases.enumerated() {
            let it = item(k.title, #selector(pickWeather(_:)), on: settings.weather == k)
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
        menu.addItem(submenu("Weather", weather))

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
        menu.addItem(item("Little Pine Trees", #selector(toggleTrees), on: settings.trees))

        let lights = NSMenu()
        for m in LightsMode.allCases {
            let it = item(m.title, #selector(setLights(_:)), on: settings.lightsMode == m)
            it.tag = m.rawValue
            lights.addItem(it)
        }
        menu.addItem(submenu("Christmas Lights", lights))

        let roomMenu = NSMenu()
        roomMenu.addItem(item("Show Cozy Room on Desktop", #selector(toggleRoom), on: room.isShown))
        roomMenu.addItem(item("Decorate My Tree…", #selector(decorate)))
        roomMenu.addItem(.separator())
        for (i, name) in CozyRoom.themes.enumerated() {
            let it = item(name, #selector(pickRoom(_:)), on: settings.roomTheme == i)
            it.tag = i
            roomMenu.addItem(it)
        }
        menu.addItem(submenu("Christmas Tree", roomMenu))

        let walls = NSMenu()
        for (i, name) in Wallpapers.names.enumerated() {
            let it = item(name, #selector(pickWallpaper(_:)))
            it.tag = i
            walls.addItem(it)
        }
        menu.addItem(submenu("Winter Wallpapers", walls))

        menu.addItem(item("Snow Globe", #selector(globe)))
        menu.addItem(item("Shake Off All Snow", #selector(clearSnow)))

        menu.addItem(.separator())
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
                  "Click a present to open it",
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
        setWeather(WeatherKind.allCases[sender.tag], fromService: false)
    }

    private func setWeather(_ kind: WeatherKind, fromService: Bool) {
        if !fromService && WeatherService.shared.isFollowing { WeatherService.shared.stop() }
        settings.weather = kind
        scenes.forEach { $0.weather = kind }
    }

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
    @objc private func freeze() { scenes.forEach { $0.toggleFrost() } }
    @objc private func globe() { scenes.forEach { $0.snowGlobe() } }
    @objc private func clearSnow() { scenes.forEach { $0.clearAllSnow() } }

    @objc private func toggleFire() {
        settings.fireplace.toggle()
        applyDecor()
    }

    @objc private func toggleTrees() {
        settings.trees.toggle()
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

    @objc private func pickWallpaper(_ sender: NSMenuItem) {
        Wallpapers.apply(sender.tag) { error in
            guard let error else { return }
            let a = NSAlert()
            a.messageText = "Couldn't set the wallpaper"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc private func toggleSounds() { settings.sounds.toggle() }
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
