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
                Circle().fill(hovered ? Socle.C.onAccentFill : Socle.C.success).frame(width: 5, height: 5).offset(y: 10 * scale)
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

/// Cercle régulier (Lanceur, Contrôleur, Musique) : une part par élément, écart constant entre les parts, survol immédiat.
struct PieStaticRing: View {
    let items: [PieItem]
    let hover: Int?
    let m: PieMetrics

    var body: some View {
        let n = items.count, c = m.side / 2, step = 360.0 / Double(max(n, 1))
        ZStack {
            ForEach(0..<n, id: \.self) { i in
                PieSector(start: (Double(i) - 0.5) * step, end: (Double(i) + 0.5) * step, inner: m.inner, outer: m.outer, gap: 3)
                    .fill(i == hover ? Socle.C.accentFill : Socle.C.surfaceRaised, style: FillStyle(eoFill: true))
            }
            ForEach(0..<n, id: \.self) { i in
                let a = (Double(i) * step - 90) * .pi / 180
                PieItemView(item: items[i], hovered: i == hover, m: m)
                    .position(x: c + m.mid * CGFloat(cos(a)), y: c + m.mid * CGFloat(sin(a)))
            }
        }
        .frame(width: m.side, height: m.side)
    }
}

/// Cercle du Sélecteur : couronne continue, surlignage qui glisse d'une appli à l'autre, loupe façon Dock. `focus` et `magnify`
/// sont animables : SwiftUI redessine le cercle à chaque image du ressort.
struct PieMagnifiedRing: View, Animatable {
    var focus: Double
    var magnify: Double
    let items: [PieItem]
    let hover: Int?
    let m: PieMetrics

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(focus, magnify) }
        set { focus = newValue.first; magnify = newValue.second }
    }

    var body: some View {
        let n = items.count, c = m.side / 2, step = 360.0 / Double(max(n, 1))
        let layout = PieLayout.make(count: n, focus: focus, magnify: magnify)
        let count = Double(max(n, 1))
        let f = (focus.truncatingRemainder(dividingBy: count) + count).truncatingRemainder(dividingBy: count)
        let wedge = PieLayout.wedgeWidth(count: n, magnify: magnify)
        ZStack {
            PieSector(start: 0, end: 360, inner: m.inner, outer: m.outer)
                .fill(Socle.C.surfaceRaised, style: FillStyle(eoFill: true))
            if hover != nil, n > 0 {
                PieSector(start: f * step - wedge / 2, end: f * step + wedge / 2, inner: m.inner, outer: m.outer, gap: 0)
                    .fill(Socle.C.accentFill)
            }
            ForEach(0..<n, id: \.self) { i in
                let pull = layout.pull[i]
                let scale = 1 + 0.55 * PieLayout.strength(count: n) * pull
                let a = (layout.centers[i] - 90) * .pi / 180
                let radius = m.mid + 9 * m.s * pull
                PieItemView(item: items[i], hovered: false, m: m, scale: CGFloat(scale))
                    .position(x: c + radius * CGFloat(cos(a)), y: c + radius * CGFloat(sin(a)))
                    .zIndex(pull)
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
    @State private var spin = SpinState()

    var body: some View {
        let live = model.module == .launcher || model.module == .switcher
        let hovered = (live && model.showName) ? model.hoveredItem : nil
        let radius = m.inner - 4
        ZStack {
            Circle().fill(Socle.C.surface).frame(width: 2 * radius, height: 2 * radius)
            Circle().stroke(Socle.C.borderStrong, lineWidth: 1).frame(width: 2 * radius, height: 2 * radius)
            if model.module == .music, model.accessibilityMissing == false {
                cover(radius: radius)
            } else {
                VStack(spacing: 3) {
                    if hovered == nil, let image = model.centerImage {
                        icon(image)
                    }
                    Text(hovered?.title ?? model.centerTitle).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    Text(hovered?.subtitle ?? model.centerSubtitle).socle(Socle.T.meta).foregroundStyle(
                        model.accessibilityMissing && model.module == .controller ? Socle.C.warning : Socle.C.textMuted)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(width: 2 * radius - 18)
            }
        }
    }

    /// Icône de l'appli visée par le Contrôleur : elle se penche vers le pointeur.
    @ViewBuilder private func icon(_ image: NSImage) -> some View {
        let tilt = model.module == .controller && model.animated ? model.tilt : .zero
        let vx = Double(tilt.width), vy = -Double(tilt.height)   // y de SwiftUI vers le bas
        // Inclinaison simulée à plat : l'icône se rétrécit dans le sens du pointeur et se décale légèrement vers lui.
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
            Text(item.title).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Socle.C.bgSunken.opacity(0.92), in: RoundedRectangle(cornerRadius: Socle.M.radius))
        }
    }
}

struct PieCanvas: View {
    @ObservedObject var model: PieModel

    var body: some View {
        let m = PieMetrics(s: model.scale)
        ZStack {
            Circle().fill(Socle.C.bgSunken).frame(width: 2 * (m.outer + 3), height: 2 * (m.outer + 3))
            Circle().stroke(Socle.C.borderStrong, lineWidth: 1).frame(width: 2 * (m.outer + 3), height: 2 * (m.outer + 3))
            if model.module == .switcher {
                PieMagnifiedRing(focus: model.focus, magnify: model.magnify, items: model.items, hover: model.hover, m: m)
            } else {
                PieStaticRing(items: model.items, hover: model.hover, m: m)
            }
            PieCenter(model: model, m: m)
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
            PieCanvas(model: model).allowsHitTesting(false)
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
        }
        .frame(width: m.panelWidth, height: height, alignment: .top)
        // Ouverture : le cercle grandit depuis son centre en apparaissant.
        .scaleEffect(model.appeared ? 1 : 0.9, anchor: UnitPoint(x: 0.5, y: (m.side / 2) / height))
        .opacity(model.appeared ? 1 : 0)
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
