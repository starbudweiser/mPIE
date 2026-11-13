import AppKit
import SwiftUI
import mPIECore

/// Essais sans fenêtre : rendu hors écran de l'interface dans un PNG (`mPIE --capture-pie launcher sortie.png`…).
@MainActor
enum Capture {
    /// Données de démonstration : lanceur d'après le préréglage « Essentiels », si la liste est vide.
    static func seed(_ delegate: AppDelegate) {
        guard delegate.launcher.items.isEmpty, let essentials = LauncherPresets.all.first(where: { $0.id == "essentials" }) else { return }
        delegate.launcher.replaceAll(paths: LauncherPresets.resolve(essentials))
    }

    static func png(_ view: NSView, size: NSSize, to path: String, backdrop: NSColor? = nil) {
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let backdrop, let flat = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, bitsPerSample: 8,
                                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
           let context = NSGraphicsContext(bitmapImageRep: flat) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            backdrop.setFill()
            NSRect(x: 0, y: 0, width: flat.pixelsWide, height: flat.pixelsHigh).fill()
            rep.draw(in: NSRect(x: 0, y: 0, width: flat.pixelsWide, height: flat.pixelsHigh))
            NSGraphicsContext.restoreGraphicsState()
            try? flat.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            return
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func pie(_ delegate: AppDelegate, module: PieModule, hover: Int?, to path: String) {
        let controller = delegate.pie
        controller.model.enabled = PieModule.allCases
        controller.model.scale = 1
        controller.model.showName = true
        controller.model.holdStyle = true
        controller.select(module)
        if module == .music {
            let now = NowPlaying(player: .appleMusic, playing: true, title: "Marée basse", artist: "Atelier Nuit", shuffle: true, repeating: false)
            controller.model.now = now
            controller.model.items[0].title = L("music.pause")
            controller.model.items[0].symbol = "pause.fill"
            controller.model.items[3].active = true
        }
        MusicRemote.shared.stopPolling()
        controller.model.hover = hover
        let metrics = PieMetrics(s: 1)
        let view = NSHostingView(rootView: PieRoot(model: controller.model).background(Color(white: 0.07)).environment(\.colorScheme, .dark))
        png(view, size: NSSize(width: metrics.panelWidth, height: metrics.panelHeight(music: module == .music)), to: path)
    }

    static func settings(_ delegate: AppDelegate, tab: SettingsTab, to path: String) {
        SettingsRouter.shared.tab = tab
        let view = NSHostingView(rootView: SettingsView(launcher: delegate.launcher, controls: delegate.controls).environment(\.colorScheme, .dark))
        png(view, size: NSSize(width: 860, height: 680), to: path)
    }

    static func about(to path: String) {
        let window = About.makeWindow()
        guard let view = window.contentView else { return }
        png(view, size: view.fittingSize, to: path)
    }

    static func welcome(_ delegate: AppDelegate, to path: String) {
        let view = WelcomeWindow.view(launcherCount: delegate.launcher.items.count, hotkey: delegate.prefs.hotkey(.open).map(KeyName.label) ?? "")
        png(view, size: view.fittingSize, to: path)
    }
}
