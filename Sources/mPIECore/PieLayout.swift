import Foundation

extension PieGeometry {
    /// Demi-écart angulaire (degrés) à retirer de chaque bord radial pour que deux parts voisines soient séparées d'un écart
    /// de largeur CONSTANTE `gap` (px), quel que soit le rayon : le bord est une droite parallèle au rayon, décalée de `gap / 2`.
    public static func edgeInset(radius: Double, gap: Double) -> Double {
        guard radius > 0 else { return 0 }
        return asin(min(0.99, (gap / 2) / radius)) * 180 / .pi
    }
}

/// Disposition du cercle du Sélecteur façon « loupe du Dock » : les applis proches de la visée grossissent et prennent plus de place,
/// les autres se serrent ; le point visé garde sa place. Pure géométrie, sans SwiftUI.
public struct PieLayout: Equatable, Sendable {
    /// Centre de chaque part (degrés, sens horaire depuis le haut).
    public var centers: [Double]
    /// Largeur angulaire de chaque part (degrés) ; leur somme vaut 360.
    public var widths: [Double]
    /// Influence de la loupe sur chaque part, de 0 (aucune) à 1 (part visée).
    public var pull: [Double]

    public static let gain = 0.6      // une part visée prend 1,6 fois sa place avant normalisation (cercle bien rempli)
    public static let sigma = 1.15    // portée de la loupe, en nombre de parts
    public static let crowded = 14.0  // en dessous de ce nombre de parts, la loupe s'atténue : peu d'applis, peu besoin de loupe

    /// Force de la loupe selon le nombre de parts : pleine à partir de `crowded`, proportionnelle en dessous.
    public static func strength(count n: Int) -> Double { min(1, Double(n) / crowded) }

    /// `focus` : indice visé, fractionnaire pendant le déplacement (il peut dépasser `count`, il est ramené dans le cercle).
    /// `magnify` : 0 (cercle régulier) à 1 (loupe complète).
    public static func make(count n: Int, focus: Double, magnify: Double) -> PieLayout {
        guard n > 0 else { return PieLayout(centers: [], widths: [], pull: []) }
        let step = 360.0 / Double(n)
        let regular = PieLayout(centers: (0..<n).map { Double($0) * step }, widths: Array(repeating: step, count: n), pull: Array(repeating: 0, count: n))
        guard n > 2, magnify > 0.001 else { return regular }

        var f = focus.truncatingRemainder(dividingBy: Double(n))
        if f < 0 { f += Double(n) }
        let pull: [Double] = (0..<n).map { i in
            var d = abs(Double(i) - f)
            d = min(d, Double(n) - d)
            return magnify * exp(-(d * d) / (sigma * sigma))
        }
        let g = gain * strength(count: n)
        let raw = pull.map { 1 + g * $0 }
        let k = Double(n) / raw.reduce(0, +)
        let widths = raw.map { $0 * k * step }

        // Angle cumulé jusqu'au point u (en parts, u peut dépasser n : on refait un tour).
        func cumul(_ u: Double) -> Double {
            if u >= Double(n) { return 360 + cumul(u - Double(n)) }
            let whole = Int(floor(u))
            var a = 0.0
            for j in 0..<whole { a += widths[j] }
            return a + (u - Double(whole)) * widths[whole]
        }
        // Le point visé garde son angle nominal : la part visée reste sous le pointeur.
        let offset = f * step - cumul(f + 0.5)
        let centers = (0..<n).map { cumul(Double($0) + 0.5) + offset }
        return PieLayout(centers: centers, widths: widths, pull: pull)
    }

    /// Largeur angulaire du surlignage de la part visée (continue quand `focus` passe d'une part à l'autre).
    public static func wedgeWidth(count n: Int, magnify: Double) -> Double {
        guard n > 0 else { return 0 }
        let step = 360.0 / Double(n)
        guard n > 2, magnify > 0.001 else { return step }
        // Somme des poids à la visée exacte : 1 + gain·m pour la part visée, 1 + gain·m·e^(-d²/σ²) pour les voisines.
        let g = gain * strength(count: n)
        var total = 0.0
        for i in 0..<n {
            var d = Double(i)
            d = min(d, Double(n) - d)
            total += 1 + g * magnify * exp(-(d * d) / (sigma * sigma))
        }
        return (1 + g * magnify) * Double(n) / total * step
    }
}
