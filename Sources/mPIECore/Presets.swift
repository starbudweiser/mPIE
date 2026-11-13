import Foundation

/// Lanceur de départ : une liste d'applis connues (`names`, « * » en fin de nom pour une appli versionnée comme
/// « Adobe After Effects 2026 ») ou toutes les applis d'un dossier (`folder`). Seules celles installées sur ce Mac sont retenues.
public struct LauncherPreset: Identifiable, Sendable {
    public let id: String
    public let symbol: String
    public let names: [String]
    public let folder: String?
    public init(id: String, symbol: String, names: [String] = [], folder: String? = nil) {
        self.id = id; self.symbol = symbol; self.names = names; self.folder = folder
    }
}

public enum LauncherPresets {
    public static let all: [LauncherPreset] = [
        LauncherPreset(id: "essentials", symbol: "square.grid.2x2", names: [
            "Safari", "Mail", "Messages", "Notes", "Calendar", "Photos", "Music", "Maps", "System Settings", "Terminal",
        ]),
        LauncherPreset(id: "video", symbol: "film", names: [
            "DaVinci Resolve", "Adobe After Effects*", "Blender", "Final Cut Pro", "Motion", "Compressor", "QuickTime Player",
            "Adobe Premiere Pro*", "Adobe Media Encoder*", "Photos",
        ]),
        LauncherPreset(id: "dev", symbol: "chevron.left.forwardslash.chevron.right", names: [
            "Xcode", "Terminal", "Visual Studio Code", "Claude", "GitHub Desktop", "iTerm", "Safari", "Activity Monitor", "System Settings",
        ]),
        LauncherPreset(id: "office", symbol: "doc.text", names: [
            "Pages", "Numbers", "Keynote", "Microsoft Word", "Microsoft Excel", "Microsoft PowerPoint", "Mail", "Calendar", "Notes", "Preview",
        ]),
        LauncherPreset(id: "design", symbol: "paintpalette", names: [
            "Adobe Photoshop*", "Adobe Illustrator*", "Adobe InDesign*", "Figma", "Affinity Photo*", "Pixelmator Pro", "Sketch", "Preview", "Photos",
        ]),
        LauncherPreset(id: "talk", symbol: "bubble.left.and.bubble.right", names: [
            "Messages", "Mail", "Slack", "Discord", "Telegram", "WhatsApp", "zoom.us", "FaceTime", "Signal",
        ]),
        LauncherPreset(id: "personal", symbol: "person.crop.square", folder: "~/Applications/Applications Personnelles"),
        LauncherPreset(id: "skyrim", symbol: "hammer", folder: "~/Applications/Skyrim Tools"),
    ]

    public static let searchDirectories = [
        "/Applications", "/System/Applications", "/System/Applications/Utilities", "~/Applications",
        "~/Applications/Applications Personnelles", "~/Applications/Skyrim Tools",
    ]

    public static func defaultListing(_ directory: String) -> [String] {
        let path = (directory as NSString).expandingTildeInPath
        return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
    }

    /// Chemins des applis du préréglage présentes sur ce Mac, dans l'ordre du préréglage, au plus `limit`.
    /// `listing` donne le contenu d'un dossier (injectable pour les essais).
    public static func resolve(_ preset: LauncherPreset, limit: Int = LauncherStore.maxItems,
                               listing: (String) -> [String] = defaultListing) -> [String] {
        var paths: [String] = []
        if let folder = preset.folder {
            let base = (folder as NSString).expandingTildeInPath
            for entry in listing(folder) where entry.hasSuffix(".app") && !entry.hasPrefix(".") { paths.append(base + "/" + entry) }
        } else {
            for name in preset.names {
                if let found = locate(name, listing: listing), !paths.contains(found) { paths.append(found) }
            }
        }
        return Array(paths.prefix(limit))
    }

    private static func locate(_ name: String, listing: (String) -> [String]) -> String? {
        let wildcard = name.hasSuffix("*")
        let base = wildcard ? String(name.dropLast()) : name
        for directory in searchDirectories {
            let root = (directory as NSString).expandingTildeInPath
            let entries = listing(directory)
            if let app = entries.first(where: { wildcard ? ($0.hasPrefix(base) && $0.hasSuffix(".app")) : $0 == base + ".app" }) {
                return root + "/" + app
            }
            guard wildcard else { continue }
            // Applis versionnées rangées dans leur propre dossier : « Adobe After Effects 2026/Adobe After Effects 2026.app ».
            for folder in entries where folder.hasPrefix(base) && !folder.hasSuffix(".app") {
                let sub = root + "/" + folder
                if let app = listing(sub).first(where: { $0.hasPrefix(base) && $0.hasSuffix(".app") }) { return sub + "/" + app }
            }
        }
        return nil
    }
}

/// Façon d'ouvrir le menu : un profil règle d'un coup le raccourci, la souris et le style.
public struct TriggerProfile: Identifiable, Sendable {
    public let id: String
    public let style: TriggerStyle
    public let mouseButton: MouseButtonChoice
    public let mouseModifier: ModifierChoice
    public let keyboard: Bool
    public init(id: String, style: TriggerStyle, mouseButton: MouseButtonChoice, mouseModifier: ModifierChoice, keyboard: Bool) {
        self.id = id; self.style = style; self.mouseButton = mouseButton; self.mouseModifier = mouseModifier; self.keyboard = keyboard
    }
}

public enum TriggerProfiles {
    public static let all: [TriggerProfile] = [
        TriggerProfile(id: "both", style: .hold, mouseButton: .middle, mouseModifier: .option, keyboard: true),
        TriggerProfile(id: "keyboard", style: .hold, mouseButton: .off, mouseModifier: .none, keyboard: true),
        TriggerProfile(id: "mouse", style: .hold, mouseButton: .middle, mouseModifier: .none, keyboard: false),
        TriggerProfile(id: "click", style: .tap, mouseButton: .middle, mouseModifier: .option, keyboard: true),
    ]
}
