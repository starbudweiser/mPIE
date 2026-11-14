// Dessine l'icône de mPIE : les quatre parts de couronne de l'icône de la barre des menus, en couleurs, sur la tuile sombre Socle.
// À plat (aucun dégradé, aucune ombre). Usage : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// Fond Socle (bg #1e1e1e) ; parts : ambre (action), rose (la marque), bleu (accent), vert (succès).
let tileColor = rgb(0x1E1E1E)
let colors = [rgb(0xFBBF24), rgb(0xFB7185), rgb(0x38BDF8), rgb(0x4ADE80)]

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.current = context
let cg = context.cgContext

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
cg.addPath(CGPath(roundedRect: tile, cornerWidth: 187, cornerHeight: 187, transform: nil))
cg.setFillColor(tileColor.cgColor)
cg.fillPath()

// Même géométrie que la silhouette de la barre des menus (rayons 7,6 et 2,8 ; parts de 78° séparées de 12°), agrandie.
let center = CGPoint(x: size / 2, y: size / 2)
let outer: CGFloat = 330, inner: CGFloat = outer * 2.8 / 7.6
for i in 0..<4 {
    let start = CGFloat(i) * 90 + 6, end = start + 78
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: outer, startAngle: start, endAngle: end)
    path.appendArc(withCenter: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
    path.close()
    colors[i].setFill()
    path.fill()
}

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
