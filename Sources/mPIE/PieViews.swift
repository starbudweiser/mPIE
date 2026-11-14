import AppKit
import SwiftUI
import mPIECore

/// Part de couronne : angles en degrés, sens horaire depuis le haut. Les deux bords radiaux sont des droites parallèles au
/// rayon, retirées de `gap / 2` : l'écart entre deux parts voisines a la même largeur partout, du centre au bord.
struct PieSector: Shape {
    var start: Double
    var end: Double
    let inner: CGFloat
    let outer: CGFloat
    var gap: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        if end - start >= 359.9 {
            p.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: 2 * outer, height: 2 * outer))
            p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner))
            return p
        }
        let dOuter = PieGeometry.edgeInset(radius: Double(outer), gap: Double(gap))
        let dInner = PieGeometry.edgeInset(radius: Double(inner), gap: Double(gap))
        p.addArc(center: c, radius: outer, startAngle: .degrees(start - 90 + dOuter), endAngle: .degrees(end - 90 - dOuter), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .degrees(end - 90 - dInner), endAngle: .degrees(start - 90 + dInner), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Ouverture, icône par icône : elles se dévoilent dans le sens horaire depuis le haut, floues puis nettes, en se redressant
/// (relevé image par image sur l'aperçu de Pieoneer, 30 images/s). `time` : secondes depuis l'ouverture.
enum PieReveal {
    static let first = 0.08     // les icônes commencent quand l'anneau est déjà bien refermé
    static let duration = 0.2   // durée d'une icône

    static func step(count n: Int) -> Double { min(0.04, 0.3 / Double(max(n, 1))) }
    /// Durée totale de l'ouverture pour `n` icônes.
    static func total(count n: Int) -> Double { first + step(count: n) * Double(max(n - 1, 0)) + duration + 0.02 }

    /// Avancement adouci (0 à 1) de l'icône `index`.
    static func progress(index: Int, count n: Int, time: Double) -> Double {
        let u = min(1, max(0, (time - first - Double(index) * step(count: n)) / duration))
        return 1 - pow(1 - u, 3)
    }
}

extension View {
    /// Effet d'apparition d'une icône : fondu, flou qui se résorbe (transitoire), redressement et léger grossissement.
    func pieReveal(_ e: Double) -> some View {
        opacity(e).blur(radius: 10 * (1 - e)).rotationEffect(.degrees(-18 * (1 - e))).scaleEffect(0.85 + 0.15 * e)
    }
}

struct PieItemView: View {
    let item: PieItem
    let hovered: Bool
    let m: PieMetrics
    var scale: CGFloat = 1

    private var tint: Color { hovered ? Socle.C.onAccentFill : (item.active ? Socle.C.accentText : Socle.C.text) }

    var body: some View {
        ZStack {
            if let image = item.image {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: m.tile * scale, height: m.tile * scale)
            } else if let symbol = item.symbol {
                Image(systemName: symbol).font(.system(size: 22 * m.s, weight: .semibold)).foregroundStyle(tint)
            } else {
                VStack(spacing: 2) {
                    Text(item.title).socle(Socle.T.label).foregroundStyle(hovered ? Socle.C.onAccentFill : Socle.C.text)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    if let keys = item.keys {
                        Text(keys).socle(Socle.T.monoSm).foregroundStyle(hovered ? Socle.C.onAccentFill : Socle.C.textSubtle)
                    }
                }
                .frame(width: 94 * m.s)
            }
        }
        .overlay(alignment: .bottom) {
            if item.badge == .running {
                Circle().fill(Socle.C.success).frame(width: 5, height: 5).offset(y: 10 * scale)
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.badge == .folder {
                Image(systemName: "folder.fill").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Socle.C.textMuted).padding(3)
                    .background(Socle.C.surfaceRaised, in: Circle()).offset(x: 8, y: -8)
            }
        }
    }
}

/// Cercle du Lanceur et du Sélecteur : couronne continue (sans séparations), surlignage arrondi sur l'élément visé.
/// Au Sélecteur, la loupe façon Dock et le surlignage, qui dépasse de la couronne, suivent la visée par un ressort très court ;
/// au Lanceur le surlignage saute d'un élément à l'autre. `focus` et `magnify` sont animables.
struct PieAnnulusRing: View, Animatable {
    var focus: Double
    var magnify: Double
    let items: [PieItem]
    let hover: Int?
    let m: PieMetrics
    let rIn: CGFloat
    let rOut: CGFloat
    let protrude: CGFloat        // > 0 : le surlignage dépasse de la couronne des deux côtés ; < 0 : il reste en retrait
    let revealTime: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(focus, magnify) }
        set { focus = newValue.first; magnify = newValue.second }
    }

    var body: some View {
        let n = items.count, c = m.side / 2, step = 360.0 / Double(max(n, 1))
        let layout = PieLayout.make(count: n, focus: focus, magnify: magnify)
        let count = Double(max(n, 1))
        let f = (focus.truncatingRemainder(dividingBy: count) + count).truncatingRemainder(dividingBy: count)
        let wedge = max(4, PieLayout.wedgeWidth(count: n, magnify: magnify) - (protrude > 0 ? 3 : 8))
        let rr = 7 * m.s
        let sector = PieSector(start: f * step - wedge / 2, end: f * step + wedge / 2,
                               inner: rIn - protrude + rr, outer: rOut + protrude - rr, gap: 2 * rr)
        ZStack {
            PieSector(start: 0, end: 360, inner: rIn, outer: rOut).fill(Socle.C.surfaceRaised, style: FillStyle(eoFill: true))
            if hover != nil, n > 0 {
                sector.fill(Socle.C.accentFill)
                sector.stroke(Socle.C.accentFill, style: StrokeStyle(lineWidth: 2 * rr, lineJoin: .round))
            }
            ForEach(0..<n, id: \.self) { i in
                let pull = layout.pull[i]
                let a = (layout.centers[i] - 90) * .pi / 180
                let radius = m.mid + 9 * m.s * pull
                PieItemView(item: items[i], hovered: false, m: m, scale: CGFloat(PieLayout.iconScale(count: n, pull: pull)))
                    .pieReveal(PieReveal.progress(index: i, count: n, time: revealTime))
                    .position(x: c + radius * CGFloat(cos(a)), y: c + radius * CGFloat(sin(a)))
                    .zIndex(pull)
            }
        }
        .frame(width: m.side, height: m.side)
    }
}

/// Cercle du Contrôleur et de la Musique : une part par action, écart constant et fin entre les parts, survol immédiat.
struct PieStaticRing: View {
    let items: [PieItem]
    let hover: Int?
    let m: PieMetrics
    let rIn: CGFloat
    let rOut: CGFloat
    let iris: Double
    let revealTime: Double

    var body: some View {
        let n = items.count, c = m.side / 2, step = 360.0 / Double(max(n, 1))
        ZStack {
            ForEach(0..<n, id: \.self) { i in
                PieSector(start: (Double(i) - 0.5) * step, end: (Double(i) + 0.5) * step, inner: rIn, outer: rOut, gap: 2.5 * CGFloat(iris))
                    .fill(i == hover ? Socle.C.accentFill : Socle.C.surfaceRaised, style: FillStyle(eoFill: true))
            }
            ForEach(0..<n, id: \.self) { i in
                let a = (Double(i) * step - 90) * .pi / 180
                PieItemView(item: items[i], hovered: i == hover, m: m)
                    .pieReveal(PieReveal.progress(index: i, count: n, time: revealTime))
                    .position(x: c + m.mid * CGFloat(cos(a)), y: c + m.mid * CGFloat(sin(a)))
            }
        }
        .frame(width: m.side, height: m.side)
    }
}

/// Pochette qui tourne comme un disque (33 tours/min) tant que la lecture est en cours, et ralentit à l'arrêt.
final class SpinState {
    var angle = 0.0
    var speed = 0.0
    var last: Date?

    func step(_ date: Date, playing: Bool) -> Double {
        let dt = min(0.1, last.map { date.timeIntervalSince($0) } ?? 0)
        last = date
        speed += ((playing ? 200.0 : 0) - speed) * min(1, dt * 5)
        angle = (angle + speed * dt).truncatingRemainder(dividingBy: 360)
        return angle
    }
}

struct PieCenter: View {
    @ObservedObject var model: PieModel
    let m: PieMetrics
    let radius: CGFloat
    @State private var spin = SpinState()

    var body: some View {
        let live = model.module == .launcher || model.module == .switcher
        let hovered = (live && model.showName) ? model.hoveredItem : nil
        ZStack {
            Circle().fill(Socle.C.surface).frame(width: 2 * radius, height: 2 * radius)
            Circle().stroke(Socle.C.borderStrong, lineWidth: 1).frame(width: 2 * radius, height: 2 * radius)
            if model.module == .music, model.accessibilityMissing == false {
                cover(radius: radius)
            } else if let hovered {
                // Comme l'original : une pastille avec le seul nom de l'élément visé.
                Text(hovered.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
                    .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
                    .frame(maxWidth: 2 * radius - 14)
            } else {
                VStack(spacing: 3) {
                    if let image = model.centerImage { icon(image) }
                    Text(model.centerTitle).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    Text(model.centerSubtitle).socle(Socle.T.meta).foregroundStyle(
                        model.accessibilityMissing && model.module == .controller ? Socle.C.warning : Socle.C.textMuted)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(width: 2 * radius - 18)
            }
        }
    }

    /// Icône de l'appli visée par le Contrôleur : elle se penche vers le pointeur (inclinaison simulée à plat).
    @ViewBuilder private func icon(_ image: NSImage) -> some View {
        let tilt = model.module == .controller && model.animated ? model.tilt : .zero
        let vx = Double(tilt.width), vy = -Double(tilt.height)
        Image(nsImage: image).resizable().interpolation(.high).frame(width: 36 * m.s, height: 36 * m.s)
            .scaleEffect(x: cos(vx * 0.42), y: cos(vy * 0.42))
            .offset(x: CGFloat(vx) * 3, y: CGFloat(vy) * 3)
    }

    @ViewBuilder private func cover(radius: CGFloat) -> some View {
        let size = 2 * radius - 16
        let spinning = model.animated
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !spinning)) { timeline in
            let angle = spinning ? spin.step(timeline.date, playing: model.now?.playing ?? false) : 0
            Group {
                if let image = model.cover {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
                        .rotationEffect(.degrees(angle))
                } else {
                    Circle().fill(Socle.C.control).frame(width: size, height: size)
                        .overlay(Image(systemName: "music.note").font(.system(size: 28 * m.s, weight: .semibold)).foregroundStyle(Socle.C.textMuted))
                }
            }
        }
        if let item = model.hoveredItem {
            Text(item.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
        }
    }
}

/// Le cercle complet. `iris` (ouverture de la couronne) et `revealTime` (dévoilement des icônes) sont animables : SwiftUI
/// redessine à chaque image avec leurs valeurs intermédiaires.
struct PieCanvas: View, Animatable {
    @ObservedObject var model: PieModel
    var iris: Double
    var revealTime: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(iris, revealTime) }
        set { iris = newValue.first; revealTime = newValue.second }
    }

    var body: some View {
        let m = PieMetrics(s: model.scale)
        let rIn = m.rIn(iris), rOut = m.rOut(iris)
        ZStack {
            Circle().fill(Socle.C.bgSunken).frame(width: 2 * rOut, height: 2 * rOut)
            Circle().stroke(Socle.C.borderStrong, lineWidth: 1).frame(width: 2 * rOut, height: 2 * rOut)
            if model.module == .launcher || model.module == .switcher {
                PieAnnulusRing(focus: model.focus, magnify: model.magnify, items: model.items, hover: model.hover, m: m,
                               rIn: rIn, rOut: rOut, protrude: model.module == .switcher ? 7 * m.s : -4 * m.s, revealTime: revealTime)
            } else {
                PieStaticRing(items: model.items, hover: model.hover, m: m, rIn: rIn, rOut: rOut, iris: iris, revealTime: revealTime)
            }
            PieCenter(model: model, m: m, radius: rIn - 4)
        }
        .frame(width: m.side, height: m.side)
    }
}

struct PieRoot: View {
    @ObservedObject var model: PieModel

    var body: some View {
        let m = PieMetrics(s: model.scale)
        let height = m.panelHeight(music: model.module == .music)
        VStack(spacing: 8) {
            PieCanvas(model: model, iris: model.iris, revealTime: model.revealTime).allowsHitTesting(false)
            VStack(spacing: Socle.M.space2) {
                if model.module == .music { nowCard }
                modeBar
                Text(L(model.holdStyle ? "pie.hint.hold" : "pie.hint.tap")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(Socle.M.space2_5)
            .frame(width: m.cardWidth)
            .background(Socle.C.surfaceRaised, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
            .opacity(model.iris)   // la carte des modules apparaît avec l'anneau
        }
        .frame(width: m.panelWidth, height: height, alignment: .top)
    }

    private var modeBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(model.enabled.enumerated()), id: \.element) { index, module in
                let on = module == model.module
                Button { model.onSelectModule?(module) } label: {
                    HStack(spacing: 6) {
                        Text("\(index + 1)").socle(Socle.T.monoSm).opacity(on ? 0.8 : 1).foregroundStyle(on ? Socle.C.onAccentFill : Socle.C.textSubtle)
                        Text(L("module." + module.rawValue)).socle(Socle.T.label).foregroundStyle(on ? Socle.C.onAccentFill : Socle.C.textMuted)
                    }
                    .padding(.horizontal, Socle.M.space3).frame(minHeight: 28)
                    .background(on ? Socle.C.accentFill : Color.clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
    }

    private var nowCard: some View {
        HStack(spacing: Socle.M.space3) {
            Group {
                if let image = model.cover {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Socle.C.control).overlay(Image(systemName: "music.note").foregroundStyle(Socle.C.textMuted))
                }
            }
            .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: Socle.M.radius))
            VStack(alignment: .leading, spacing: 1) {
                if let now = model.now, !now.title.isEmpty {
                    Text(now.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                    Text(now.artist + " · " + L(now.player == .spotify ? "music.spotify" : "music.applemusic"))
                        .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1)
                } else {
                    Text(L(model.now == nil ? "music.noplayer" : "music.stopped")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Socle.M.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radius))
    }
}
