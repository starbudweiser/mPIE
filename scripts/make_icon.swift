// Dessine l'icône de mPIE : un cercle en quatre parts blanches sur carré rouge, à plat (Socle).
// Usage : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
let red = NSColor(red: 0.882, green: 0.114, blue: 0.282, alpha: 1)   // #e11d48
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.current = context
let cg = context.cgContext

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
cg.addPath(CGPath(roundedRect: tile, cornerWidth: 187, cornerHeight: 187, transform: nil))
cg.setFillColor(red.cgColor)
cg.fillPath()

// Quatre parts de couronne, la première centrée en haut à droite ; deux pleines, deux atténuées.
let center = CGPoint(x: size / 2, y: size / 2)
let outer: CGFloat = 330, inner: CGFloat = 92, gap: CGFloat = 5 // degrés
for i in 0..<4 {
    let start = CGFloat(i) * 90 + gap, end = CGFloat(i + 1) * 90 - gap
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: outer, startAngle: start, endAngle: end)
    path.appendArc(withCenter: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
    path.close()
    NSColor.white.withAlphaComponent(i % 2 == 0 ? 1 : 0.78).setFill()
    path.fill()
}

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
