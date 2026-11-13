import XCTest
@testable import mPIECore

final class GeometryTests: XCTestCase {
    func testQuarterSlices() {
        // Quatre parts : 0 en haut, 1 à droite, 2 en bas, 3 à gauche.
        XCTAssertEqual(PieGeometry.index(dx: 0, dy: 100, count: 4, inner: 50, outerLimit: 300), 0)
        XCTAssertEqual(PieGeometry.index(dx: 100, dy: 0, count: 4, inner: 50, outerLimit: 300), 1)
        XCTAssertEqual(PieGeometry.index(dx: 0, dy: -100, count: 4, inner: 50, outerLimit: 300), 2)
        XCTAssertEqual(PieGeometry.index(dx: -100, dy: 0, count: 4, inner: 50, outerLimit: 300), 3)
    }

    func testBordersBelongToTheNextSlice() {
        // 10 parts de 36° : la part 1 est centrée à 36°, elle commence à 18°.
        let a = 20.0 * .pi / 180
        XCTAssertEqual(PieGeometry.index(dx: 100 * sin(a), dy: 100 * cos(a), count: 10, inner: 50, outerLimit: 300), 1)
        let b = 16.0 * .pi / 180
        XCTAssertEqual(PieGeometry.index(dx: 100 * sin(b), dy: 100 * cos(b), count: 10, inner: 50, outerLimit: 300), 0)
    }

    func testNoSelectionInCenterOrTooFar() {
        XCTAssertNil(PieGeometry.index(dx: 10, dy: 10, count: 6, inner: 50, outerLimit: 300))
        XCTAssertNil(PieGeometry.index(dx: 0, dy: 400, count: 6, inner: 50, outerLimit: 300))
        XCTAssertNil(PieGeometry.index(dx: 0, dy: 100, count: 0, inner: 50, outerLimit: 300))
    }

    func testWrapsAroundTopLeft() {
        // Juste à gauche du haut : la dernière part (indice n-1).
        let a = -10.0 * .pi / 180
        XCTAssertEqual(PieGeometry.index(dx: 100 * sin(a), dy: 100 * cos(a), count: 8, inner: 50, outerLimit: 300), 0)
        let b = -30.0 * .pi / 180
        XCTAssertEqual(PieGeometry.index(dx: 100 * sin(b), dy: 100 * cos(b), count: 8, inner: 50, outerLimit: 300), 7)
    }
}

final class LauncherStoreTests: XCTestCase {
    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mpie-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAddRemoveMoveAndPersistence() {
        let dir = makeDirectory()
        let store = LauncherStore(directory: dir)
        XCTAssertEqual(store.add(paths: ["/Applications/A.app", "/Applications/B.app", "/Applications/A.app"]), 2)
        store.move(store.items[1].id, by: -1)
        XCTAssertEqual(store.items.map(\.path), ["/Applications/B.app", "/Applications/A.app"])
        let reloaded = LauncherStore(directory: dir)
        XCTAssertEqual(reloaded.items.map(\.path), ["/Applications/B.app", "/Applications/A.app"])
        reloaded.remove(reloaded.items[0].id)
        XCTAssertEqual(reloaded.items.count, 1)
    }

    func testLimitAndReplaceAll() {
        let store = LauncherStore(directory: makeDirectory())
        let many = (0..<30).map { "/Applications/App\($0).app" }
        XCTAssertEqual(store.add(paths: many), LauncherStore.maxItems)
        XCTAssertEqual(store.replaceAll(paths: ["/x.app", "/x.app", "/y.app"]), 2)
        XCTAssertEqual(store.items.map(\.path), ["/x.app", "/y.app"])
    }

    func testKindsAndNames() {
        XCTAssertEqual(LauncherItem(path: "/nonexistent/Foo.app").kind, .missing)
        XCTAssertEqual(LauncherItem(path: "/System/Applications/Safari.app").name, "Safari")
        XCTAssertEqual(LauncherItem(path: "/System/Applications").kind, .folder)
    }
}

final class ControlStoreTests: XCTestCase {
    private func makeStore() -> ControlStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mpie-test-\(UUID().uuidString)")
        return ControlStore(directory: dir, resolve: { _ in 7 }, localize: { $0 })
    }

    func testDefaultsAndFallback() {
        let store = makeStore()
        XCTAssertEqual(store.set(for: "com.apple.finder").name, "Finder")
        XCTAssertEqual(store.set(for: "com.unknown.app").id, ControlDefaults.genericID)
        XCTAssertEqual(store.set(for: nil).id, ControlDefaults.genericID)
        XCTAssertTrue(store.defaults.allSatisfy { !$0.actions.isEmpty && $0.actions.count <= ControlDefaults.maxActions })
    }

    func testEditResetAndAddApp() {
        let store = makeStore()
        var finder = store.set(for: "com.apple.finder")
        finder.actions.removeLast()
        let count = finder.actions.count
        store.save(finder)
        XCTAssertTrue(store.isCustomized("com.apple.finder"))
        XCTAssertEqual(store.set(for: "com.apple.finder").actions.count, count)
        store.reset("com.apple.finder")
        XCTAssertEqual(store.set(for: "com.apple.finder").actions.count, count + 1)

        store.addApp(bundleID: "com.example.tool", name: "Tool")
        XCTAssertEqual(store.set(for: "com.example.tool").actions.count, store.generic.actions.count)
        XCTAssertTrue(store.allSets.contains { $0.id == "com.example.tool" })
        XCTAssertEqual(store.allSets.first?.id, ControlDefaults.genericID)
    }

    func testStableActionIDs() {
        let a = ControlDefaults.sets(resolve: { _ in 1 }, localize: { $0 })
        let b = ControlDefaults.sets(resolve: { _ in 2 }, localize: { $0 })
        XCTAssertEqual(a.flatMap(\.actions).map(\.id), b.flatMap(\.actions).map(\.id))
        XCTAssertEqual(Set(a.flatMap(\.actions).map(\.id)).count, a.flatMap(\.actions).count)
    }
}

final class MusicTests: XCTestCase {
    func testParseAppleMusic() {
        let now = MusicScripts.parse("playing|||Marée basse|||Atelier Nuit|||true|||all|||", player: .appleMusic)
        XCTAssertEqual(now, NowPlaying(player: .appleMusic, playing: true, title: "Marée basse", artist: "Atelier Nuit", shuffle: true, repeating: true))
        let off = MusicScripts.parse("paused|||T|||A|||false|||off|||", player: .appleMusic)
        XCTAssertEqual(off?.repeating, false)
        XCTAssertEqual(off?.playing, false)
    }

    func testParseSpotifyWithArtwork() {
        let now = MusicScripts.parse("playing|||T|||A|||false|||true|||https://i.scdn.co/image/x", player: .spotify)
        XCTAssertEqual(now?.repeating, true)
        XCTAssertEqual(now?.artworkURL, "https://i.scdn.co/image/x")
        XCTAssertNil(MusicScripts.parse("garbage", player: .spotify))
    }

    func testCommandsTargetTheRightApp() {
        XCTAssertTrue(MusicScripts.command(.playPause, player: .appleMusic).contains("\"Music\""))
        XCTAssertTrue(MusicScripts.command(.next, player: .spotify).contains("\"Spotify\""))
        XCTAssertTrue(MusicScripts.command(.shuffle, player: .spotify).contains("shuffling"))
        XCTAssertTrue(MusicScripts.command(.repeatToggle, player: .appleMusic).contains("song repeat"))
    }
}

final class PresetsTests: XCTestCase {
    private let tree: [String: [String]] = [
        "/Applications": ["Blender.app", "DaVinci Resolve", "Adobe After Effects 2026", "Notes.txt"],
        "/Applications/Adobe After Effects 2026": ["Adobe After Effects 2026.app", "Plug-ins"],
        "/System/Applications": ["Safari.app", "Mail.app", "Notes.app"],
        "~/Applications/Applications Personnelles": ["mCLOUD.app", "mLINKS.app", ".hidden.app", "readme.txt"],
    ]
    private func listing(_ dir: String) -> [String] { tree[dir] ?? [] }

    func testEssentialsKeepsOnlyInstalledApps() {
        let preset = LauncherPresets.all.first { $0.id == "essentials" }!
        let paths = LauncherPresets.resolve(preset, listing: listing)
        XCTAssertEqual(paths, ["/System/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Notes.app"])
    }

    func testVersionedAppInOwnFolder() {
        let preset = LauncherPresets.all.first { $0.id == "video" }!
        let paths = LauncherPresets.resolve(preset, listing: listing)
        XCTAssertTrue(paths.contains("/Applications/Adobe After Effects 2026/Adobe After Effects 2026.app"))
        XCTAssertTrue(paths.contains("/Applications/Blender.app"))
        XCTAssertFalse(paths.contains { $0.contains("DaVinci") }) // dossier sans .app : ignoré
    }

    func testFolderPreset() {
        let preset = LauncherPresets.all.first { $0.id == "personal" }!
        let paths = LauncherPresets.resolve(preset, listing: listing)
        XCTAssertEqual(paths.map { ($0 as NSString).lastPathComponent }, ["mCLOUD.app", "mLINKS.app"])
    }

    func testLimit() {
        let preset = LauncherPreset(id: "x", symbol: "x", folder: "/many")
        let many = (0..<40).map { "A\($0).app" }
        XCTAssertEqual(LauncherPresets.resolve(preset, limit: 5, listing: { _ in many }).count, 5)
    }

    func testProfilesAreDistinct() {
        let ids = TriggerProfiles.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

/// Les quatre langues ont les mêmes clés ; chaque clé utilisée par le code existe.
final class LocalizationTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private func keys(_ lang: String) throws -> [String: String] {
        let text = try String(contentsOf: root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8)
        var out: [String: String] = [:]
        let regex = try NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$"#, options: .anchorsMatchLines)
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            out[String(text[Range(m.range(at: 1), in: text)!])] = String(text[Range(m.range(at: 2), in: text)!])
        }
        return out
    }

    func testSameKeysInAllLanguages() throws {
        let fr = try keys("fr")
        XCTAssertGreaterThan(fr.count, 100)
        for lang in ["en", "es", "it"] {
            let other = try keys(lang)
            XCTAssertEqual(Set(fr.keys), Set(other.keys), "clés différentes en \(lang)")
            for (key, value) in other { XCTAssertFalse(value.isEmpty, "\(lang) : \(key) vide") }
        }
    }

    func testFormatPlaceholdersMatch() throws {
        let fr = try keys("fr")
        func placeholders(_ s: String) -> [String] { s.components(separatedBy: "%").dropFirst().map { String($0.prefix(1)) }.sorted() }
        for lang in ["en", "es", "it"] {
            for (key, value) in try keys(lang) { XCTAssertEqual(placeholders(value), placeholders(fr[key] ?? ""), "\(lang) : \(key)") }
        }
    }

    func testEveryLiteralKeyUsedByTheCodeExists() throws {
        let fr = try keys("fr")
        let sources = root.appendingPathComponent("Sources/mPIE")
        let regex = try NSRegularExpression(pattern: #"\bL\(\s*"([A-Za-z0-9_.]+)""#)
        let skip: Set<String> = ["Socle.swift", "Updater.swift", "UpdaterView.swift"]
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") && !skip.contains(file) {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(m.range(at: 1), in: text)!])
                if key.hasSuffix(".") { continue } // clé composée (« module. » + identifiant), couverte par testEnumeratedKeysExist
                XCTAssertNotNil(fr[key], "\(file) : clé \(key) absente")
            }
        }
    }

    func testEnumeratedKeysExist() throws {
        let fr = try keys("fr")
        var needed: [String] = []
        needed += PieModule.allCases.map { "module.\($0.rawValue)" }
        needed += StartModule.allCases.map { "start.\($0.rawValue)" }
        needed += MouseButtonChoice.allCases.map { "mouse.\($0.rawValue)" }
        needed += ModifierChoice.allCases.map { "modifier.\($0.rawValue)" }
        needed += MusicPlayer.allCases.map { "player.\($0.rawValue)" }
        needed += TriggerStyle.allCases.map { "style.\($0.rawValue)" }
        needed += LauncherPresets.all.map { "preset.\($0.id)" }
        needed += TriggerProfiles.all.flatMap { ["profile.\($0.id)", "profile.\($0.id).text"] }
        needed += ["general", "trigger", "presets", "launcher", "controller", "music", "updates"].map { "settings.tab.\($0)" }
        needed += ControlDefaults.sets(resolve: { _ in 0 }, localize: { $0 }).flatMap { $0.actions.map(\.label) }
        for key in needed { XCTAssertNotNil(fr[key], "clé \(key) absente") }
    }
}
