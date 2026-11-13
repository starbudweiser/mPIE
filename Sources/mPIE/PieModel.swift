import AppKit
import SwiftUI
import mPIECore

/// Une part du menu circulaire.
struct PieItem: Identifiable {
    enum Badge { case none, running, folder }
    let id: String
    var title: String
    var subtitle: String?
    var image: NSImage?          // tuile d'appli, de dossier ou de fichier
    var symbol: String?          // pictogramme SF Symbols (télécommande)
    var keys: String?            // raccourci écrit sous le nom (Contrôleur)
    var badge: Badge = .none
    var active = false           // bascule enclenchée (aléatoire, répétition)
    var action: @MainActor () -> Void
}

/// Mesures du cercle, proportionnelles au réglage « Taille ».
struct PieMetrics {
    let s: CGFloat
    var outer: CGFloat { 176 * s }
    var inner: CGFloat { 66 * s }
    var tile: CGFloat { 38 * s }
    var mid: CGFloat { (outer + inner) / 2 }
    var side: CGFloat { 2 * (outer + 14) }
    var panelWidth: CGFloat { max(side, 500) }
    var cardWidth: CGFloat { panelWidth - 40 }
    /// Cercle, puis la carte des modules (plus haute avec la lecture en cours de la télécommande).
    func panelHeight(music: Bool) -> CGFloat { side + 8 + (music ? 142 : 84) }
}

@MainActor
final class PieModel: ObservableObject {
    @Published var module: PieModule = .launcher
    @Published var enabled: [PieModule] = PieModule.allCases
    @Published var items: [PieItem] = []
    @Published var hover: Int?
    @Published var scale: CGFloat = 1
    @Published var showName = true
    @Published var holdStyle = true
    @Published var centerImage: NSImage?
    @Published var centerTitle = ""
    @Published var centerSubtitle = ""
    @Published var now: NowPlaying?
    @Published var cover: NSImage?
    @Published var accessibilityMissing = false
    var onSelectModule: ((PieModule) -> Void)?

    var hoveredItem: PieItem? {
        guard let hover, items.indices.contains(hover) else { return nil }
        return items[hover]
    }
}
