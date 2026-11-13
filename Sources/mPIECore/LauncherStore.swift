import Combine
import Foundation

public struct LauncherItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var path: String

    public init(id: UUID = UUID(), path: String) { self.id = id; self.path = path }

    public enum Kind: String, Sendable { case app, folder, file, missing }

    public var url: URL { URL(fileURLWithPath: path) }

    public var kind: Kind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .missing }
        if path.hasSuffix(".app") { return .app }
        return isDirectory.boolValue ? .folder : .file
    }

    public var name: String {
        let shown = FileManager.default.displayName(atPath: path)
        return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
    }
}

/// Éléments du Lanceur : applis, dossiers et fichiers, dans l'ordre du cercle (sens horaire depuis le haut).
public final class LauncherStore: ObservableObject {
    public static let maxItems = 16
    @Published public private(set) var items: [LauncherItem] = []
    private let file: URL

    public init(directory: URL) {
        file = directory.appendingPathComponent("launcher.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([LauncherItem].self, from: data) { items = list }
    }

    /// Ajoute des chemins (sans doublon, dans la limite de `maxItems`) ; rend le nombre ajouté.
    @discardableResult
    public func add(paths: [String]) -> Int {
        var added = 0
        for path in paths where items.count < Self.maxItems && !items.contains(where: { $0.path == path }) {
            items.append(LauncherItem(path: path)); added += 1
        }
        if added > 0 { save() }
        return added
    }

    /// Remplace toute la liste (préréglage) ; rend le nombre d'éléments retenus.
    @discardableResult
    public func replaceAll(paths: [String]) -> Int {
        var seen = Set<String>()
        items = paths.filter { seen.insert($0).inserted }.prefix(Self.maxItems).map { LauncherItem(path: $0) }
        save()
        return items.count
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Décale un élément dans l'ordre du cercle (-1 : plus tôt, +1 : plus tard).
    public func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: file, options: .atomic) }
    }
}
