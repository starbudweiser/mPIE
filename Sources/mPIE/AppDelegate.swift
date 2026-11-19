import AppKit
import SwiftUI
import mPIECore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launcher: LauncherStore
    let controls: ControlStore
    let settings = SettingsWindow()
    let updates = UpdateEngine.shared
    let pie = PieController.shared
    private let mouse = MouseTrigger()
    let prefs = Prefs.shared
    private var statusItem: NSStatusItem?

    override init() {
        let directory = DataDirectory.url()
        launcher = LauncherStore(directory: directory)
        controls = ControlStore(directory: directory, resolve: { KeyMap.code(for: $0) }, localize: { L($0) })
        super.init()
        pie.launcher = launcher
        pie.controls = controls
        settings.launcher = launcher
        settings.controls = controls
        pie.openSettings = { [weak self] in self?.settings.show(tab: .launcher) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        Socle.brand("mPIE", color: BrandColor.color)
        installMainMenu()
        _ = AppTracker.shared
        NotificationCenter.default.addObserver(forName: .prefsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPrefs() }
        }
        NotificationCenter.default.addObserver(forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controls.reloadDefaults() }
        }

        HotkeyCenter.shared.onPress = { [weak self] action in self?.hotkeyPressed(action) }
        HotkeyCenter.shared.onRelease = { [weak self] _ in self?.pie.release(from: .key) }
        mouse.onDown = { [weak self] button, flags in self?.mouseDown(button, flags) }
        mouse.onUp = { [weak self] button in self?.mouseUp(button) }
        mouse.start()
        applyPrefs()

        updates.configure(repo: "mPIE", lang: { Bundle.main.preferredLocalizations.first ?? "en" })
        updates.autoCheck = { Prefs.shared.autoUpdate }
        updates.start()

        let args = CommandLine.arguments
        if args.contains("--demo") { Capture.seed(self) }
        if let i = args.firstIndex(of: "--discret-reglages") {
            let tab = args.indices.contains(i + 1) ? SettingsTab(rawValue: args[i + 1]) : nil
            settings.show(tab: tab, quietly: true)
        }
        if args.contains("--discret-accueil") { showWelcome(quietly: true) }
        if !prefs.welcomed, !args.contains("--no-welcome"), !args.contains("--demo") {
            if launcher.items.isEmpty, let essentials = LauncherPresets.all.first(where: { $0.id == "essentials" }) {
                launcher.replaceAll(paths: LauncherPresets.resolve(essentials))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { self.showWelcome() } }
        }
    }

    /// Relancer l'appli depuis le Finder ouvre les réglages (utile quand l'icône de la barre des menus est masquée).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    private func showWelcome(quietly: Bool = false) {
        let key = prefs.hotkey(.open).map(KeyName.label) ?? L("shortcut.none")
        WelcomeWindow.show(launcherCount: launcher.items.count, hotkey: key, quietly: quietly) { [weak self] in self?.prefs.welcomed = true }
    }

    // MARK: Déclencheurs

    private func hotkeyPressed(_ action: HotkeyAction) {
        if pie.isOpen { pie.close(); return }
        pie.open(module: action.module, source: .key)
    }

    private func mouseDown(_ button: Int, _ flags: UInt) {
        guard prefs.mouseButtonNumber >= 0, button == prefs.mouseButtonNumber else { return }
        let mask = prefs.mouseModifier.mask
        if mask != 0, flags & mask != mask { return }
        if pie.isOpen { pie.close(); return }
        pie.open(source: .mouse)
    }

    private func mouseUp(_ button: Int) {
        guard prefs.mouseButtonNumber >= 0, button == prefs.mouseButtonNumber else { return }
        pie.release(from: .mouse)
    }

    private func applyPrefs() {
        let list = HotkeyAction.allCases.compactMap { action in prefs.hotkey(action).map { (action, $0) } }
        HotkeyCenter.shared.register(list)
        installStatusItem()
    }

    // MARK: Barre des menus (le menu s'ouvre sous l'icône : jamais `statusItem.menu`, sinon macOS le décale sur plusieurs écrans)

    private func installStatusItem() {
        if !prefs.menuBarIcon {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item); statusItem = nil }
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarImage()
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// Silhouette monochrome du cercle en quatre parts (image « modèle » : suit le thème de la barre).
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let center = NSPoint(x: 9, y: 9)
            for i in 0..<4 {
                let start = CGFloat(i) * 90 + 6, end = start + 78
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: 7.6, startAngle: start, endAngle: end)
                path.appendArc(withCenter: center, radius: 2.8, startAngle: end, endAngle: start, clockwise: true)
                path.close()
                NSColor.black.withAlphaComponent(i % 2 == 0 ? 1 : 0.55).setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem?.socleShow(buildMenu())
        } else if pie.isOpen {
            pie.close()
        } else {
            pie.open(source: .menu, anchor: NSEvent.mouseLocation)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, badge: String? = nil, on: Bool = false, tag: Int = 0) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            if on { item.state = .on }
            if let badge { item.badge = NSMenuItemBadge(string: badge) }
            menu.addItem(item)
        }
        add(L("menu.open"), #selector(menuOpen), badge: prefs.hotkey(.open).map(KeyName.label))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: L("menu.module")))
        for (index, module) in PieModule.allCases.enumerated() where prefs.isEnabled(module) {
            add(L("module." + module.rawValue), #selector(menuModule(_:)), badge: prefs.hotkey(HotkeyAction(rawValue: module.rawValue)!).map(KeyName.label),
                on: module == prefs.lastModule, tag: index)
        }
        menu.addItem(.separator())
        add(L("menu.settings"), #selector(menuSettings))
        switch updates.state {
        case .available(let plan): add(L("update.install", plan.target.version), #selector(menuInstallUpdate))
        case .downloading, .verifying, .installing:
            let busy = NSMenuItem(title: L("update.installing"), action: nil, keyEquivalent: ""); busy.isEnabled = false; menu.addItem(busy)
        default: add(L("update.check"), #selector(menuCheckUpdate))
        }
        add(L("about.menu"), #selector(menuAbout))
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func menuOpen() { pie.open(source: .menu, anchor: NSEvent.mouseLocation) }
    @objc private func menuModule(_ sender: NSMenuItem) { pie.open(module: PieModule.allCases[sender.tag], source: .menu, anchor: NSEvent.mouseLocation) }
    @objc private func menuSettings() { settings.show() }
    @objc private func menuCheckUpdate() { updates.checkNow() }
    @objc private func menuInstallUpdate() { if case .available(let plan) = updates.state { updates.present(plan) } }
    @objc private func menuAbout() { About.show() }

    // MARK: Menu principal (porte ⌘W, ⌘Q… même sans Dock)

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.settings"), action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: L("menu.edit"))
        edit.addItem(withTitle: L("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(); let window = NSMenu(title: L("menu.window"))
        window.addItem(withTitle: L("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window; main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}
