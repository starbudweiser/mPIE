import Combine
import Foundation

public struct ControlAction: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var keyCode: Int
    public var modifiers: UInt

    public init(id: UUID = UUID(), label: String, keyCode: Int, modifiers: UInt) {
        self.id = id; self.label = label; self.keyCode = keyCode; self.modifiers = modifiers
    }

    public var hotkey: Hotkey { Hotkey(keyCode: keyCode, modifiers: modifiers) }
}

/// Raccourcis d'une appli (identifiée par son bundle id) que le Contrôleur sait envoyer.
public struct ControlSet: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var actions: [ControlAction]
    public init(id: String, name: String, actions: [ControlAction]) { self.id = id; self.name = name; self.actions = actions }
}

public enum ControlDefaults {
    public static let genericID = "generic"
    public static let maxActions = 12

    /// Jeux de raccourcis fournis. `resolve` donne le code de touche d'un caractère dans la disposition active (AZERTY compris),
    /// `localize` traduit une clé d'étiquette (`ctl.*`).
    public static func sets(resolve: (String) -> Int, localize: (String) -> String) -> [ControlSet] {
        let c = Hotkey.command, s = Hotkey.shift, o = Hotkey.option, k = Hotkey.control
        func set(_ id: String, _ name: String, _ rows: [(String, String, UInt)]) -> ControlSet {
            ControlSet(id: id, name: name, actions: rows.map {
                ControlAction(id: stableID(id, $0.0), label: localize($0.0), keyCode: resolve($0.1), modifiers: $0.2)
            })
        }
        return [
            set(genericID, localize("ctl.set.generic"), [
                ("ctl.new", "n", c), ("ctl.closewindow", "w", c), ("ctl.minimize", "m", c),
                ("ctl.fullscreen", "f", k | c), ("ctl.find", "f", c), ("ctl.settings", ",", c),
            ]),
            set("com.apple.finder", "Finder", [
                ("ctl.listview", "2", c), ("ctl.goto", "g", s | c), ("ctl.downloads", "l", o | c),
                ("ctl.newfolder", "n", s | c), ("ctl.emptytrash", "delete", s | c), ("ctl.viewoptions", "j", c),
            ]),
            set("com.apple.Safari", "Safari", [
                ("ctl.newtab", "t", c), ("ctl.closetab", "w", c), ("ctl.reopentab", "t", s | c),
                ("ctl.reload", "r", c), ("ctl.sidebar", "l", s | c), ("ctl.private", "n", s | c),
            ]),
            set("com.google.Chrome", "Chrome", [
                ("ctl.newtab", "t", c), ("ctl.closetab", "w", c), ("ctl.reopentab", "t", s | c),
                ("ctl.reload", "r", c), ("ctl.devtools", "i", o | c), ("ctl.incognito", "n", s | c),
            ]),
            set("com.apple.mail", "Mail", [
                ("ctl.newmessage", "n", c), ("ctl.reply", "r", c), ("ctl.replyall", "r", s | c),
                ("ctl.forward", "f", s | c), ("ctl.archive", "a", k | c), ("ctl.getmail", "n", s | c),
            ]),
            set("com.apple.Notes", "Notes", [
                ("ctl.newnote", "n", c), ("ctl.newfolder", "n", s | c), ("ctl.checklist", "l", s | c),
                ("ctl.bold", "b", c), ("ctl.find", "f", o | c),
            ]),
            set("com.apple.Terminal", "Terminal", [
                ("ctl.newtab", "t", c), ("ctl.newwindow", "n", c), ("ctl.clear", "k", c),
                ("ctl.closetab", "w", c), ("ctl.split", "d", c),
            ]),
            set("com.blackmagic-design.DaVinciResolve", "DaVinci Resolve", [
                ("ctl.blade", "b", c), ("ctl.ripple", "delete", s), ("ctl.marker", "m", 0),
                ("ctl.snap", "n", 0), ("ctl.undo", "z", c), ("ctl.redo", "z", s | c),
            ]),
            set("org.blenderfoundation.blender", "Blender", [
                ("ctl.editmode", "tab", 0), ("ctl.render", "f12", 0), ("ctl.save", "s", c),
                ("ctl.undo", "z", c), ("ctl.redo", "z", s | c),
            ]),
            set("com.apple.dt.Xcode", "Xcode", [
                ("ctl.build", "b", c), ("ctl.run", "r", c), ("ctl.test", "u", c),
                ("ctl.clean", "k", s | c), ("ctl.quickopen", "o", s | c), ("ctl.save", "s", c),
            ]),
            set("com.microsoft.VSCode", "Visual Studio Code", [
                ("ctl.palette", "p", s | c), ("ctl.quickopen", "p", c), ("ctl.panel", "j", c),
                ("ctl.sidebar", "b", c), ("ctl.search", "f", s | c), ("ctl.saveall", "s", o | c),
            ]),
        ]
    }

    /// Identifiant stable d'une action par défaut (pour que l'interface ne la recrée pas à chaque lecture).
    private static func stableID(_ set: String, _ key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in (set + "|" + key).utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &+ b &* UInt8(truncatingIfNeeded: i + 1) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Jeux de raccourcis : ceux fournis, plus les versions modifiées par l'utilisateur (enregistrées en JSON).
public final class ControlStore: ObservableObject {
    @Published public private(set) var custom: [String: ControlSet] = [:]
    @Published public private(set) var defaults: [ControlSet] = []
    private let file: URL
    private let resolve: (String) -> Int
    private let localize: (String) -> String

    public init(directory: URL, resolve: @escaping (String) -> Int, localize: @escaping (String) -> String) {
        file = directory.appendingPathComponent("controller.json")
        self.resolve = resolve; self.localize = localize
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file), let map = try? JSONDecoder().decode([String: ControlSet].self, from: data) { custom = map }
        reloadDefaults()
    }

    /// À rappeler si la disposition du clavier change : les jeux fournis suivent la disposition active.
    public func reloadDefaults() { defaults = ControlDefaults.sets(resolve: resolve, localize: localize) }

    public var generic: ControlSet { resolved(ControlDefaults.genericID) ?? ControlSet(id: ControlDefaults.genericID, name: "", actions: []) }

    private func resolved(_ id: String) -> ControlSet? { custom[id] ?? defaults.first { $0.id == id } }

    /// Jeu de l'appli au premier plan, sinon le jeu générique.
    public func set(for bundleID: String?) -> ControlSet {
        if let bundleID, let found = resolved(bundleID) { return found }
        return generic
    }

    /// Tous les jeux : le générique d'abord, puis les autres par nom.
    public var allSets: [ControlSet] {
        var ids = defaults.map(\.id)
        for id in custom.keys where !ids.contains(id) { ids.append(id) }
        let sets = ids.compactMap(resolved)
        return sets.sorted { a, b in
            if a.id == ControlDefaults.genericID { return true }
            if b.id == ControlDefaults.genericID { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public func isCustomized(_ id: String) -> Bool { custom[id] != nil }
    public func isBuiltIn(_ id: String) -> Bool { defaults.contains { $0.id == id } }

    public func save(_ set: ControlSet) {
        var copy = set
        copy.actions = Array(copy.actions.prefix(ControlDefaults.maxActions))
        custom[copy.id] = copy
        persist()
    }

    /// Rend un jeu fourni à son état d'origine, ou supprime un jeu ajouté par l'utilisateur.
    public func reset(_ id: String) {
        custom[id] = nil
        persist()
    }

    /// Ajoute une appli : son jeu part d'une copie du jeu générique.
    public func addApp(bundleID: String, name: String) {
        guard resolved(bundleID) == nil else { return }
        let actions = generic.actions.map { ControlAction(label: $0.label, keyCode: $0.keyCode, modifiers: $0.modifiers) }
        save(ControlSet(id: bundleID, name: name, actions: actions))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) { try? data.write(to: file, options: .atomic) }
    }
}
