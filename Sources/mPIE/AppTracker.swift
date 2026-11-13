import AppKit

/// Suit les applis activées : dernière appli « extérieure » (cible du Contrôleur) et ordre d'usage récent (Applis ouvertes).
@MainActor
final class AppTracker {
    static let shared = AppTracker()
    private(set) var recent: [pid_t] = []
    private(set) var lastExternal: NSRunningApplication?

    private init() {
        if let front = NSWorkspace.shared.frontmostApplication { note(front) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { AppTracker.shared.note(app) }
        }
    }

    private func note(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternal = app
        recent.removeAll { $0 == app.processIdentifier }
        recent.insert(app.processIdentifier, at: 0)
    }

    /// Applis visibles dans le Dock (hors mPIE et hors exclusions), les plus récemment utilisées d'abord.
    func runningApps(excluding excluded: Set<String>) -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
                && !excluded.contains($0.bundleIdentifier ?? "")
        }
        return apps.sorted { a, b in
            let ia = recent.firstIndex(of: a.processIdentifier) ?? Int.max
            let ib = recent.firstIndex(of: b.processIdentifier) ?? Int.max
            if ia != ib { return ia < ib }
            return (a.localizedName ?? "").localizedCaseInsensitiveCompare(b.localizedName ?? "") == .orderedAscending
        }
    }
}
