import AppKit
import SwiftUI
import mPIECore

/// Une part de couronne, centrée sur le haut pour l'indice 0 puis dans le sens horaire.
struct PieSlice: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        if count <= 1 {
            p.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: 2 * outer, height: 2 * outer))
            p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner))
            return p
        }
        let step = 360.0 / Double(count)
        let mid = -90.0 + Double(index) * step
        let gap = 1.4
        let a0 = Angle.degrees(mid - step / 2 + gap), a1 = Angle.degrees(mid + step / 2 - gap)
        p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }
}

struct PieItemView: View {
    let item: PieItem
    let hovered: Bool
    let m: PieMetrics

    private var tint: Color { hovered ? Socle.C.onAccentFill : (item.active ? Socle.C.accentText : Socle.C.text) }

    var body: some View {
        ZStack {
            if let image = item.image {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: m.tile, height: m.tile)
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
                Circle().fill(hovered ? Socle.C.onAccentFill : Socle.C.success).frame(width: 5, height: 5).offset(y: 10)
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

struct PieCenter: View {
    @ObservedObject var model: PieModel
    let m: PieMetrics

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
                        Image(nsImage: image).resizable().interpolation(.high).frame(width: 36 * m.s, height: 36 * m.s)
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

    @ViewBuilder private func cover(radius: CGFloat) -> some View {
        let size = 2 * radius - 16
        if let image = model.cover {
            Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            Circle().fill(Socle.C.control).frame(width: size, height: size)
                .overlay(Image(systemName: "music.note").font(.system(size: 28 * m.s, weight: .semibold)).foregroundStyle(Socle.C.textMuted))
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
        let m = PieMetrics(s: model.scale), n = model.items.count, c = m.side / 2
        ZStack {
            Circle().fill(Socle.C.bgSunken).frame(width: 2 * (m.outer + 3), height: 2 * (m.outer + 3))
            Circle().stroke(Socle.C.borderStrong, lineWidth: 1).frame(width: 2 * (m.outer + 3), height: 2 * (m.outer + 3))
            ForEach(0..<n, id: \.self) { i in
                PieSlice(index: i, count: n, inner: m.inner, outer: m.outer)
                    .fill(i == model.hover ? Socle.C.accentFill : Socle.C.surfaceRaised, style: FillStyle(eoFill: true))
            }
            ForEach(0..<n, id: \.self) { i in
                let a = (-90.0 + Double(i) * 360.0 / Double(n)) * .pi / 180
                PieItemView(item: model.items[i], hovered: i == model.hover, m: m)
                    .position(x: c + m.mid * CGFloat(cos(a)), y: c + m.mid * CGFloat(sin(a)))
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
        .frame(width: m.panelWidth, height: m.panelHeight(music: model.module == .music), alignment: .top)
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
