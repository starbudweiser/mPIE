import Foundation

/// Raccourci clavier : code de touche virtuel et modificateurs (mêmes valeurs que `NSEvent.ModifierFlags`).
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: Int
    public var modifiers: UInt
    public init(keyCode: Int, modifiers: UInt) { self.keyCode = keyCode; self.modifiers = modifiers }

    public static let command: UInt = 1 << 20
    public static let option: UInt = 1 << 19
    public static let control: UInt = 1 << 18
    public static let shift: UInt = 1 << 17
}

/// Les quatre modules du menu circulaire.
public enum PieModule: String, CaseIterable, Codable, Sendable {
    case launcher, switcher, controller, music
}

/// Maintenir pour viser puis relâcher, ou appuyer pour ouvrir et cliquer.
public enum TriggerStyle: String, CaseIterable, Codable, Sendable { case hold, tap }

public enum MouseButtonChoice: String, CaseIterable, Codable, Sendable {
    case off, middle, button4, button5
    /// Numéro de bouton d'`NSEvent` (0 gauche, 1 droit, 2 milieu…).
    public var buttonNumber: Int? {
        switch self {
        case .off: nil
        case .middle: 2
        case .button4: 3
        case .button5: 4
        }
    }
}

public enum ModifierChoice: String, CaseIterable, Codable, Sendable {
    case none, option, control, shift, command
    public var mask: UInt {
        switch self {
        case .none: 0
        case .option: Hotkey.option
        case .control: Hotkey.control
        case .shift: Hotkey.shift
        case .command: Hotkey.command
        }
    }
}

/// Module montré à l'ouverture du menu.
public enum StartModule: String, CaseIterable, Codable, Sendable {
    case last, launcher, switcher, controller, music
    public var module: PieModule? { PieModule(rawValue: rawValue) }
}

public enum MusicPlayer: String, CaseIterable, Codable, Sendable {
    case auto, appleMusic, spotify
    public var bundleID: String? {
        switch self {
        case .auto: nil
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }
}

/// Raccourcis globaux : ouvrir le menu, ou ouvrir directement un module.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case open, launcher, switcher, controller, music

    public var defaultHotkey: Hotkey? {
        self == .open ? Hotkey(keyCode: 49, modifiers: Hotkey.option) : nil // ⌥ Espace
    }

    public var module: PieModule? { PieModule(rawValue: rawValue) }
}

/// Part du menu visée par le pointeur.
public enum PieGeometry {
    /// Indice de la part sous le pointeur : la part 0 est centrée en haut, les suivantes tournent dans le sens horaire.
    /// `dx`, `dy` : écart au centre, repère écran (y vers le haut). Rend nil dans le disque central ou trop loin.
    public static func index(dx: Double, dy: Double, count: Int, inner: Double, outerLimit: Double) -> Int? {
        guard count > 0 else { return nil }
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= inner, distance <= outerLimit else { return nil }
        var angle = atan2(dx, dy) // 0 en haut, positif vers la droite
        if angle < 0 { angle += 2 * .pi }
        let step = 2 * .pi / Double(count)
        return Int(((angle + step / 2) / step).rounded(.down)) % count
    }

    /// Angle (degrés, sens horaire depuis le haut) du centre d'une part.
    public static func centerAngle(of index: Int, count: Int) -> Double {
        360.0 / Double(max(count, 1)) * Double(index)
    }
}

/// Dossier des données : `MPIE_DATA_DIR` (essais, édition de développement) ou Application Support/mPIE.
public enum DataDirectory {
    public static func url() -> URL {
        if let custom = ProcessInfo.processInfo.environment["MPIE_DATA_DIR"], !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("mPIE", isDirectory: true)
    }
}
