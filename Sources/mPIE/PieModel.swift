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
    /// Ouverture façon Pieoneer : un anneau fin plus grand de 7 % se resserre en couronne (le trou rétrécit de 0,82 R à r).
    func rIn(_ iris: Double) -> CGFloat { inner + (outer * 0.82 - inner) * CGFloat(1 - iris) }
    func rOut(_ iris: Double) -> CGFloat { outer * (1 + 0.07 * CGFloat(1 - iris)) }
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
    // Animations (réglage « Animations de l'interface », coupées aussi si macOS demande de réduire les animations)
    @Published var animated = true
    @Published var iris: Double = 1        // ouverture : la couronne fine se referme sur le centre (0 = anneau fin, 1 = couronne finale)
    @Published var revealTime: Double = 99 // ouverture : secondes écoulées pour le dévoilement des icônes (99 = terminé)
    @Published var focus: Double = 0       // Sélecteur : indice visé « déroulé » (animé d'une part à l'autre)
    @Published var magnify: Double = 0     // Sélecteur : 0 cercle régulier, 1 loupe complète
    @Published var tilt: CGSize = .zero    // Contrôleur : écart du pointeur au centre, de -1 à 1 (y vers le haut)
    var onSelectModule: ((PieModule) -> Void)?

    var hoveredItem: PieItem? {
        guard let hover, items.indices.contains(hover) else { return nil }
        return items[hover]
    }
}
