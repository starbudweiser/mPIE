import AppKit
import mPIECore

enum Shell {
    /// Lance un script AppleScript (hors du fil principal) ; rend sa sortie, ou nil en cas d'échec.
    static func osascript(_ script: String, completion: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            do { try process.run() } catch { completion(nil); return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(process.terminationStatus == 0 ? text : nil)
        }
    }
}

/// Télécommande d'Apple Musique et de Spotify : état de lecture, pochette et commandes.
@MainActor
final class MusicRemote {
    static let shared = MusicRemote()
    var onUpdate: ((NowPlaying?, NSImage?) -> Void)?
    private(set) var now: NowPlaying?
    private(set) var cover: NSImage?
    private var timer: Timer?
    private var coverKey = ""
    private var busy = false

    /// Lecteurs ouverts, selon le réglage (Musique d'abord en mode automatique).
    func runningPlayers() -> [MusicPlayer] {
        let wanted: [MusicPlayer] = switch Prefs.shared.musicPlayer {
        case .auto: [.appleMusic, .spotify]
        case .appleMusic: [.appleMusic]
        case .spotify: [.spotify]
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return wanted.filter { $0.bundleID.map(running.contains) ?? false }
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { MusicRemote.shared.refresh() }
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        guard !busy else { return }
        let players = runningPlayers()
        guard !players.isEmpty else { publish(nil); return }
        busy = true
        query(players, index: 0, found: [])
    }

    private func query(_ players: [MusicPlayer], index: Int, found: [NowPlaying]) {
        guard index < players.count else {
            busy = false
            publish(found.first { $0.playing } ?? found.first)
            return
        }
        let player = players[index]
        Shell.osascript(MusicScripts.info(player: player)) { output in
            let parsed = output.flatMap { MusicScripts.parse($0, player: player) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MusicRemote.shared.query(players, index: index + 1, found: found + (parsed.map { [$0] } ?? []))
                }
            }
        }
    }

    private func publish(_ value: NowPlaying?) {
        now = value
        let key = value.map { "\($0.player.rawValue)|\($0.title)|\($0.artist)" } ?? ""
        if key != coverKey {
            coverKey = key
            cover = nil
            if let value, !value.title.isEmpty { loadCover(for: value, key: key) }
        }
        onUpdate?(now, cover)
    }

    private func loadCover(for value: NowPlaying, key: String) {
        if value.player == .spotify {
            guard let string = value.artworkURL, let url = URL(string: string) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { MusicRemote.shared.setCover(image, key: key) } }
            }.resume()
        } else {
            let path = NSTemporaryDirectory() + "mpie-cover-\(ProcessInfo.processInfo.processIdentifier).img"
            Shell.osascript(MusicScripts.artwork(toFile: path)) { output in
                guard output == "ok", let image = NSImage(contentsOfFile: path) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { MusicRemote.shared.setCover(image, key: key) } }
            }
        }
    }

    private func setCover(_ image: NSImage, key: String) {
        guard key == coverKey else { return }
        cover = image
        onUpdate?(now, cover)
    }

    /// Envoie une commande au lecteur actif ; lance Musique si aucun lecteur n'est ouvert (lecture seulement).
    func run(_ command: MusicCommand) {
        let player = now?.player ?? runningPlayers().first
        guard let player else {
            if command == .playPause, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        Shell.osascript(MusicScripts.command(command, player: player)) { _ in }
    }
}
