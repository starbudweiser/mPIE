import AppKit
import mPIECore

let arguments = CommandLine.arguments

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// Pas d'icône dans le Dock : la barre des menus suffit.
app.setActivationPolicy(.accessory)

/// Essais : rendu hors écran de l'interface (aucune fenêtre ouverte devant le travail en cours).
func after(_ flag: String, _ count: Int, _ run: @escaping @MainActor ([String]) -> Void) {
    guard let index = arguments.firstIndex(of: flag), arguments.count > index + count else { return }
    let values = Array(arguments[(index + 1)...(index + count)])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { run(values); exit(0) } }
}
after("--capture-pie", 2) { v in
    let hover = arguments.firstIndex(of: "--hover").flatMap { Int(arguments[$0 + 1]) }
    Capture.pie(delegate, module: PieModule(rawValue: v[0]) ?? .launcher, hover: hover, to: v[1])
}
after("--capture-settings", 2) { v in Capture.settings(delegate, tab: SettingsTab(rawValue: v[0]) ?? .general, to: v[1]) }
after("--capture-about", 1) { v in Capture.about(to: v[0]) }
after("--capture-welcome", 1) { v in Capture.welcome(delegate, to: v[0]) }

app.run()
