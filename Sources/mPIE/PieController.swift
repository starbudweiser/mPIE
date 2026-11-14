import AppKit
import SwiftUI
import mPIECore

/// Fenêtre du menu : sans bord, transparente, au-dessus de tout, sans voler le focus à l'appli au premier plan.
final class PiePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}

/// Ouverture, visée, validation et fermeture du menu circulaire.
@MainActor
final class PieController: NSObject {
    enum Source { case key, mouse, menu }

    static let shared = PieController()
    let model = PieModel()
    var launcher: LauncherStore!
    var controls: ControlStore!
    var openSettings: (() -> Void)?

    private let prefs = Prefs.shared
    private var panel: PiePanel?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var center = NSPoint.zero
    private var openedAt = Date.distantPast
    private var openedBy: Source = .key
    private var sticky = false
    private var lastScroll = Date.distantPast
    private var activationObserver: NSObjectProtocol?
    private var target: NSRunningApplication?

    var isOpen: Bool { panel?.isVisible == true }

    // MARK: Ouverture

    /// Ouvre le menu. `module` nil : module de départ du réglage. `anchor` nil : sous le pointeur (ou au centre de l'écran selon le réglage).
    func open(module requested: PieModule? = nil, source: Source, anchor: NSPoint? = nil) {
        guard !isOpen else { return }
        let enabled = prefs.enabledModules
        var module = requested ?? startModule()
        if !enabled.contains(module) { module = enabled[0] }
        model.enabled = enabled
        model.scale = CGFloat(prefs.pieScale)
        model.showName = prefs.showName
        model.animated = prefs.animationsActive
        model.appeared = !model.animated
        model.holdStyle = prefs.style == .hold && source != .menu
        model.hover = nil
        target = AppTracker.shared.lastExternal
        openedBy = source
        openedAt = Date()
        sticky = !(prefs.style == .hold && source != .menu)
        model.onSelectModule = { [weak self] in self?.select($0) }
        select(module)

        let metrics = PieMetrics(s: model.scale)
        let size = NSSize(width: metrics.panelWidth, height: metrics.panelHeight(music: module == .music))
        center = placement(anchor: anchor, metrics: metrics, size: size)
        let panel = PiePanel(size: size)
        panel.contentView = NSHostingView(rootView: PieRoot(model: model))
        panel.setFrame(NSRect(x: center.x - size.width / 2, y: center.y + metrics.side / 2 - size.height, width: size.width, height: size.height), display: true)
        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        startTracking()
        if model.animated {
            // Ouverture : le cercle grandit depuis son centre en apparaissant (ressort court, sans rebond marqué).
            DispatchQueue.main.async { withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { PieController.shared.model.appeared = true } }
        }
    }

    private func startModule() -> PieModule {
        prefs.startModule.module ?? prefs.lastModule
    }

    /// Centre du cercle : sous le pointeur, ramené dans l'écran pour que le cercle et sa barre restent entiers.
    private func placement(anchor: NSPoint?, metrics: PieMetrics, size: NSSize) -> NSPoint {
        let pointer = anchor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame
        var point = (anchor == nil && prefs.openAtPointer) ? pointer : NSPoint(x: frame.midX, y: screen.visibleFrame.midY)
        let half = metrics.side / 2
        let belowRing = metrics.panelHeight(music: true) - metrics.side
        let minX = frame.minX + max(half, size.width / 2) + 6
        let maxX = frame.maxX - max(half, size.width / 2) - 6
        point.x = min(max(point.x, minX), max(minX, maxX))
        point.y = min(max(point.y, frame.minY + half + belowRing + 6), max(frame.minY + half + belowRing + 6, screen.visibleFrame.maxY - half - 6))
        return point
    }

    // MARK: Modules

    func select(_ module: PieModule) {
        model.module = module
        model.hover = nil
        model.focus = 0; model.magnify = 0; model.tilt = .zero
        prefs.lastModule = module
        MusicRemote.shared.stopPolling()
        switch module {
        case .launcher: loadLauncher()
        case .switcher: loadSwitcher()
        case .controller: loadController()
        case .music: loadMusic()
        }
        if let panel {
            // La carte des modules change de hauteur avec la télécommande : le centre du cercle reste en place.
            let metrics = PieMetrics(s: model.scale)
            let height = metrics.panelHeight(music: module == .music)
            panel.setFrame(NSRect(x: panel.frame.minX, y: center.y + metrics.side / 2 - height, width: panel.frame.width, height: height), display: true)
        }
    }

    private func loadLauncher() {
        model.centerImage = nil
        model.centerTitle = L("module.launcher")
        model.accessibilityMissing = false
        if launcher.items.isEmpty {
            model.items = []
            model.centerSubtitle = L("launcher.empty")
            return
        }
        model.centerSubtitle = L("launcher.count", launcher.items.count)
        model.items = launcher.items.map { item in
            let kind = item.kind
            let icon = NSWorkspace.shared.icon(forFile: item.path)
            let subtitle = L(kind == .app ? "kind.app" : kind == .folder ? "kind.folder" : kind == .file ? "kind.file" : "kind.missing")
            return PieItem(id: item.id.uuidString, title: item.name, subtitle: subtitle, image: icon,
                           badge: kind == .folder ? .folder : .none, action: {
                if kind == .missing { NSSound.beep() } else { NSWorkspace.shared.open(item.url) }
            })
        }
    }

    private func loadSwitcher() {
        let apps = AppTracker.shared.runningApps(excluding: Set(prefs.excludedApps)).prefix(LauncherStore.maxItems)
        model.centerImage = nil
        model.centerTitle = L("module.switcher")
        model.centerSubtitle = L("switcher.count", apps.count)
        model.accessibilityMissing = false
        model.items = apps.map { app in
            PieItem(id: "\(app.processIdentifier)", title: app.localizedName ?? "?", subtitle: L("switcher.running"),
                    image: app.icon, badge: .running, action: {
                if app.isHidden { app.unhide() }
                app.activate(options: [.activateAllWindows])
            })
        }
    }

    private func loadController() {
        let app = target ?? AppTracker.shared.lastExternal
        let set = controls.set(for: app?.bundleIdentifier)
        model.centerImage = app?.icon
        model.centerTitle = app?.localizedName ?? L("module.controller")
        let trusted = KeySender.trusted
        model.accessibilityMissing = !trusted
        model.centerSubtitle = trusted ? L("controller.count", set.actions.count) : L("controller.needs.access")
        model.items = set.actions.filter { $0.keyCode >= 0 && !$0.label.isEmpty }.prefix(ControlDefaults.maxActions).map { action in
            PieItem(id: action.id.uuidString, title: action.label, keys: KeyName.label(action.hotkey), action: {
                if !KeySender.send(action.hotkey) { self.openSettings?() }
            })
        }
    }

    private func loadMusic() {
        model.centerImage = nil
        model.accessibilityMissing = false
        let remote = MusicRemote.shared
        func build(_ now: NowPlaying?) {
            let playing = now?.playing ?? false
            model.items = [
                PieItem(id: "playpause", title: L(playing ? "music.pause" : "music.play"), symbol: playing ? "pause.fill" : "play.fill", action: { remote.run(.playPause) }),
                PieItem(id: "next", title: L("music.next"), symbol: "forward.end.fill", action: { remote.run(.next) }),
                PieItem(id: "repeat", title: L("music.repeat"), symbol: "repeat", active: now?.repeating ?? false, action: { remote.run(.repeatToggle) }),
                PieItem(id: "shuffle", title: L("music.shuffle"), symbol: "shuffle", active: now?.shuffle ?? false, action: { remote.run(.shuffle) }),
                PieItem(id: "previous", title: L("music.previous"), symbol: "backward.end.fill", action: { remote.run(.previous) }),
            ]
            model.now = now
        }
        build(remote.now)
        model.cover = remote.cover
        remote.onUpdate = { [weak self] now, cover in
            guard let self, self.isOpen, self.model.module == .music else { return }
            build(now)
            self.model.cover = cover
        }
        remote.startPolling()
    }

    // MARK: Visée et validation

    private func startTracking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 90.0, repeats: true) { _ in
            MainActor.assumeIsolated { PieController.shared.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel], handler: { event in
            MainActor.assumeIsolated { PieController.shared.local(event) }
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel], handler: { event in
            MainActor.assumeIsolated { PieController.shared.global(event) }
        }) { monitors.append(global) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PieController.shared.close() }
        }
    }

    private func tick() {
        guard isOpen else { return }
        let metrics = PieMetrics(s: model.scale)
        let pointer = NSEvent.mouseLocation
        let index = PieGeometry.index(dx: Double(pointer.x - center.x), dy: Double(pointer.y - center.y), count: model.items.count,
                                      inner: Double(metrics.inner), outerLimit: Double(metrics.outer + 70))
        if index != model.hover {
            let before = model.hover
            model.hover = index
            if model.module == .switcher { followFocus(index, before: before) }
            if index != nil, prefs.sound { NSSound(named: "Tink")?.play() }
        }
        updateTilt(dx: pointer.x - center.x, dy: pointer.y - center.y, outer: metrics.outer)
    }

    private static let ringSpring = Animation.spring(response: 0.14, dampingFraction: 0.78)

    /// Sélecteur : la loupe et le surlignage suivent l'appli visée par un ressort court ; sans animations, le surlignage saute
    /// d'une appli à l'autre et le cercle reste régulier.
    private func followFocus(_ index: Int?, before: Int?) {
        let n = model.items.count
        guard n > 0 else { return }
        guard let index else {
            if model.animated { withAnimation(Self.ringSpring) { model.magnify = 0 } } else { model.magnify = 0 }
            return
        }
        guard model.animated else { model.focus = Double(index); model.magnify = 0; return }
        if before == nil {
            // Le pointeur entre dans le cercle : le surlignage apparaît sur place, seule la loupe s'installe.
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { model.focus = Double(index) }
            withAnimation(Self.ringSpring) { model.magnify = 1 }
            return
        }
        var current = model.focus.truncatingRemainder(dividingBy: Double(n))
        if current < 0 { current += Double(n) }
        var delta = Double(index) - current
        if delta > Double(n) / 2 { delta -= Double(n) } else if delta < -Double(n) / 2 { delta += Double(n) }
        withAnimation(Self.ringSpring) { model.focus += delta; model.magnify = 1 }
    }

    /// Contrôleur : l'icône de l'appli se penche vers le pointeur.
    private func updateTilt(dx: CGFloat, dy: CGFloat, outer: CGFloat) {
        guard model.module == .controller, model.animated else {
            if model.tilt != .zero { model.tilt = .zero }
            return
        }
        let target = CGSize(width: max(-1, min(1, dx / outer)), height: max(-1, min(1, dy / outer)))
        guard abs(target.width - model.tilt.width) > 0.02 || abs(target.height - model.tilt.height) > 0.02 else { return }
        withAnimation(.spring(response: 0.12, dampingFraction: 0.75)) { model.tilt = target }
    }

    private func local(_ event: NSEvent) -> NSEvent? {
        guard isOpen else { return event }
        switch event.type {
        case .keyDown:
            switch event.keyCode {
            case 53: close()                                       // Échap
            case 36, 76: commit()                                  // Retour
            case 48: stepModule(event.modifierFlags.contains(.shift) ? -1 : 1)
            case 18, 19, 20, 21:                                   // 1 à 4
                let index = [18: 0, 19: 1, 20: 2, 21: 3][Int(event.keyCode)] ?? 0
                if model.enabled.indices.contains(index) { select(model.enabled[index]) }
            default: break
            }
            return nil
        case .leftMouseDown:
            if model.hover != nil { commit(); return nil }
            if let panel, NSMouseInRect(NSEvent.mouseLocation, panel.frame, false), !insideRing() { return event } // barre des modules
            if sticky { close(); return nil }
            return event
        case .scrollWheel:
            scroll(event.scrollingDeltaY)
            return nil
        default:
            return event
        }
    }

    private func global(_ event: NSEvent) {
        guard isOpen else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown: if model.hover != nil && event.type == .leftMouseDown { commit() } else if sticky { close() }
        case .scrollWheel: scroll(event.scrollingDeltaY)
        default: break
        }
    }

    private func insideRing() -> Bool {
        let metrics = PieMetrics(s: model.scale)
        let pointer = NSEvent.mouseLocation
        return hypot(pointer.x - center.x, pointer.y - center.y) <= metrics.outer + 70
    }

    private func scroll(_ delta: CGFloat) {
        guard delta != 0, Date().timeIntervalSince(lastScroll) > 0.3 else { return }
        lastScroll = Date()
        stepModule(delta < 0 ? 1 : -1)
    }

    private func stepModule(_ step: Int) {
        let list = model.enabled
        guard list.count > 1, let index = list.firstIndex(of: model.module) else { return }
        select(list[(index + step + list.count) % list.count])
    }

    /// Relâchement de la touche ou du bouton qui a ouvert le menu : valide la part visée (sauf appui bref : le menu reste ouvert).
    func release(from source: Source) {
        guard isOpen, !sticky, source == openedBy else { return }
        if Date().timeIntervalSince(openedAt) < 0.25 { sticky = true; model.holdStyle = false; return }
        commit()
    }

    func commit() {
        guard isOpen else { return }
        let item = model.hoveredItem
        let emptyLauncher = model.module == .launcher && model.items.isEmpty
        close()
        if let item {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { item.action() } }
        } else if emptyLauncher {
            openSettings?()
        }
    }

    func close() {
        timer?.invalidate(); timer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        MusicRemote.shared.stopPolling()
        MusicRemote.shared.onUpdate = nil
        if let closing = panel {
            panel = nil
            if model.animated {
                // Fermeture : fondu court, sans bloquer une réouverture immédiate (le panneau suivant est un autre panneau).
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.1
                    closing.animator().alphaValue = 0
                }, completionHandler: { closing.orderOut(nil) })
            } else {
                closing.orderOut(nil)
            }
        }
        model.hover = nil
    }
}
