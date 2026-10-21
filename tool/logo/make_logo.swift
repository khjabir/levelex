import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Levelex logo generator. Usage: make_logo <out.png> <variant> [mode]
//   variant: arrowL | figure | bolt
//   mode: full (rounded square, default) | foreground (transparent, padded) | background (square, no mark)
let out = CommandLine.arguments[1]
let variant = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "arrowL"
let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "full"
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let S = CGFloat(size)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}
let lime = rgb(198, 255, 61), mint = rgb(57, 255, 136), cyan = rgb(56, 229, 255)
let brand = CGGradient(colorsSpace: cs, colors: [lime, mint, cyan] as CFArray, locations: [0, 0.55, 1])!

// ---- background -----------------------------------------------------------
if mode != "foreground" {
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    let path = mode == "full"
        ? CGPath(roundedRect: rect, cornerWidth: S * 0.225, cornerHeight: S * 0.225, transform: nil)
        : CGPath(rect: rect, transform: nil)
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [rgb(19, 26, 38), rgb(7, 9, 14)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S * 0.9, y: 0), options: [])
    // diagonal sheen
    let sheen = CGGradient(colorsSpace: cs, colors: [rgb(255,255,255,0.07), rgb(255,255,255,0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: S), end: CGPoint(x: S * 0.55, y: S * 0.45), options: [])
    // glow behind the mark
    let glow = CGGradient(colorsSpace: cs, colors: [rgb(57, 255, 136, 0.32), rgb(57, 255, 136, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S*0.5, y: S*0.5), startRadius: 0,
                           endCenter: CGPoint(x: S*0.5, y: S*0.5), endRadius: S*0.5, options: [])
    ctx.restoreGState()
}
if mode == "background" {
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest); print("wrote \(out)"); exit(0)
}

// ---- mark -----------------------------------------------------------------
let scale: CGFloat = mode == "foreground" ? 0.60 : 0.74
ctx.saveGState()
ctx.translateBy(x: S/2, y: S/2); ctx.scaleBy(x: S * scale, y: S * scale); ctx.translateBy(x: -0.5, y: -0.5)
// unit square, y up
func stroke(_ pts: [CGPoint], _ w: CGFloat, closed: Bool = false) -> CGPath {
    let p = CGMutablePath(); p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; if closed { p.closeSubpath() }
    return p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)
}
let markPath = CGMutablePath()
switch variant {
case "arrowL":
    // A bold L whose foot sweeps up into an arrow: level up.
    let w: CGFloat = 0.17
    markPath.addPath(stroke([CGPoint(x: 0.22, y: 0.86), CGPoint(x: 0.22, y: 0.20), CGPoint(x: 0.78, y: 0.20)], w))
    // arrow head rising from the foot's end
    markPath.addPath(stroke([CGPoint(x: 0.78, y: 0.20), CGPoint(x: 0.78, y: 0.52)], w))
    markPath.addPath(stroke([CGPoint(x: 0.62, y: 0.40), CGPoint(x: 0.78, y: 0.56), CGPoint(x: 0.94, y: 0.40)], w * 0.95))
case "figure":
    // Levelex figure: a person mid star-jump, arms thrown up in a V, legs
    // driving off the ground. Reads "level up" at any size.
    let w: CGFloat = 0.135
    markPath.addEllipse(in: CGRect(x: 0.5 - 0.10, y: 0.73, width: 0.20, height: 0.20))
    markPath.addPath(stroke([CGPoint(x: 0.5, y: 0.66), CGPoint(x: 0.5, y: 0.37)], w * 1.15))                 // torso
    markPath.addPath(stroke([CGPoint(x: 0.22, y: 0.93), CGPoint(x: 0.5, y: 0.60), CGPoint(x: 0.78, y: 0.93)], w * 0.9)) // arms V
    markPath.addPath(stroke([CGPoint(x: 0.27, y: 0.07), CGPoint(x: 0.5, y: 0.37), CGPoint(x: 0.73, y: 0.07)], w))      // legs
case "bolt":
    // Lightning L: an L whose corner is a bolt kink.
    let w: CGFloat = 0.16
    markPath.addPath(stroke([CGPoint(x: 0.30, y: 0.90), CGPoint(x: 0.30, y: 0.48), CGPoint(x: 0.52, y: 0.48), CGPoint(x: 0.40, y: 0.14), CGPoint(x: 0.80, y: 0.14)], w))
default: break
}
// shadow + glow pass
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -0.015), blur: 0.06, color: rgb(0, 0, 0, 0.55))
ctx.addPath(markPath); ctx.setFillColor(mint); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(markPath); ctx.clip()
ctx.drawLinearGradient(brand, start: CGPoint(x: 0.15, y: 0.1), end: CGPoint(x: 0.9, y: 0.95), options: [])
// top-left highlight inside the mark
let hl = CGGradient(colorsSpace: cs, colors: [rgb(255,255,255,0.35), rgb(255,255,255,0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(hl, start: CGPoint(x: 0.2, y: 0.95), end: CGPoint(x: 0.55, y: 0.5), options: [])
ctx.restoreGState()
ctx.restoreGState()

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
print("wrote \(out)")
