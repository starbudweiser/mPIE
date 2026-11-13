import AppKit
import SwiftUI
import mPIECore

extension Notification.Name {
    static let prefsChanged = Notification.Name("mPIEPrefsChanged")
}

/// Marque : couleur du logo, utilisée pour la lettre « m » du nom de l'appli (rose, éclaircie pour rester lisible sur le fond sombre).
enum BrandColor {
    static let ns = NSColor(red: 0.984, green: 0.443, blue: 0.522, alpha: 1)   // #fb7185
    static let color = Color(red: 0.984, green: 0.443, blue: 0.522)
}

/// Réglages de l'appli (UserDefaults). Chaque changement prévient l'appli par `.prefsChanged`.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard
    private func changed() { NotificationCenter.default.post(name: .prefsChanged, object: nil) }

    @Published var style: TriggerStyle { didSet { d.set(style.rawValue, forKey: "style"); changed() } }
    @Published var mouseButton: MouseButtonChoice { didSet { d.set(mouseButton.rawValue, forKey: "mouseButton"); changed() } }
    @Published var mouseModifier: ModifierChoice { didSet { d.set(mouseModifier.rawValue, forKey: "mouseModifier"); changed() } }
    @Published var hotkeys: [String: Hotkey] { didSet { d.set(try? JSONEncoder().encode(hotkeys), forKey: "hotkeys"); changed() } }
    @Published var disabledModules: [String] { didSet { d.set(disabledModules, forKey: "disabledModules"); changed() } }
    @Published var startModule: StartModule { didSet { d.set(startModule.rawValue, forKey: "startModule"); changed() } }
    @Published var pieScale: Double { didSet { d.set(pieScale, forKey: "pieScale"); changed() } }
    @Published var openAtPointer: Bool { didSet { d.set(openAtPointer, forKey: "openAtPointer"); changed() } }
    @Published var showName: Bool { didSet { d.set(showName, forKey: "showName"); changed() } }
    @Published var sound: Bool { didSet { d.set(sound, forKey: "sound"); changed() } }
    @Published var excludedApps: [String] { didSet { d.set(excludedApps, forKey: "excludedApps"); changed() } }
    @Published var musicPlayer: MusicPlayer { didSet { d.set(musicPlayer.rawValue, forKey: "musicPlayer"); changed() } }
    @Published var menuBarIcon: Bool { didSet { d.set(menuBarIcon, forKey: "menuBarIcon"); changed() } }
    @Published var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "autoUpdate"); changed() } }
    var lastModule: PieModule {
        get { PieModule(rawValue: d.string(forKey: "lastModule") ?? "") ?? .launcher }
        set { d.set(newValue.rawValue, forKey: "lastModule") }
    }
    var welcomed: Bool {
        get { d.bool(forKey: "welcomed") }
        set { d.set(newValue, forKey: "welcomed") }
    }

    private init() {
        func bool(_ k: String, _ v: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? v }
        let d = UserDefaults.standard
        style = TriggerStyle(rawValue: d.string(forKey: "style") ?? "") ?? .hold
        mouseButton = MouseButtonChoice(rawValue: d.string(forKey: "mouseButton") ?? "") ?? .middle
        mouseModifier = ModifierChoice(rawValue: d.string(forKey: "mouseModifier") ?? "") ?? .option
        hotkeys = (d.data(forKey: "hotkeys").flatMap { try? JSONDecoder().decode([String: Hotkey].self, from: $0) }) ?? [:]
        disabledModules = d.stringArray(forKey: "disabledModules") ?? []
        startModule = StartModule(rawValue: d.string(forKey: "startModule") ?? "") ?? .last
        pieScale = d.object(forKey: "pieScale") as? Double ?? 1.0
        openAtPointer = bool("openAtPointer", true)
        showName = bool("showName", true)
        sound = bool("sound", false)
        excludedApps = d.stringArray(forKey: "excludedApps") ?? []
        musicPlayer = MusicPlayer(rawValue: d.string(forKey: "musicPlayer") ?? "") ?? .auto
        menuBarIcon = bool("menuBarIcon", true)
        autoUpdate = bool("autoUpdate", true)
    }

    /// Modules actifs, dans l'ordre fixe du sélecteur.
    var enabledModules: [PieModule] {
        let list = PieModule.allCases.filter { !disabledModules.contains($0.rawValue) }
        return list.isEmpty ? [.launcher] : list
    }

    func isEnabled(_ module: PieModule) -> Bool { !disabledModules.contains(module.rawValue) }

    /// Active ou coupe un module ; au moins un module reste actif.
    func setEnabled(_ module: PieModule, _ on: Bool) {
        if on { disabledModules.removeAll { $0 == module.rawValue } }
        else if enabledModules.count > 1, !disabledModules.contains(module.rawValue) { disabledModules.append(module.rawValue) }
    }

    func hotkey(_ action: HotkeyAction) -> Hotkey? {
        if let custom = hotkeys[action.rawValue] { return custom.keyCode < 0 ? nil : custom }
        return action.defaultHotkey
    }

    /// nil efface le raccourci ; `resetHotkey` rend la valeur d'origine.
    func setHotkey(_ action: HotkeyAction, _ hotkey: Hotkey?) {
        hotkeys[action.rawValue] = hotkey ?? Hotkey(keyCode: -1, modifiers: 0)
    }
    func resetHotkey(_ action: HotkeyAction) { hotkeys[action.rawValue] = nil }

    /// Applique un profil de déclenchement (style, souris et raccourci d'ouverture).
    func apply(_ profile: TriggerProfile) {
        style = profile.style
        mouseButton = profile.mouseButton
        mouseModifier = profile.mouseModifier
        if profile.keyboard { resetHotkey(.open) } else { setHotkey(.open, nil) }
    }

    /// Profil dont les réglages correspondent à ceux d'aujourd'hui, s'il y en a un.
    var currentProfile: TriggerProfile? {
        TriggerProfiles.all.first {
            $0.style == style && $0.mouseButton == mouseButton && $0.mouseModifier == mouseModifier
                && $0.keyboard == (hotkey(.open) != nil)
        }
    }
}
