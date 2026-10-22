// Renders the app icon from the same vector layers as the Android launcher icon (ic_launcher_background /
// ic_launcher_foreground), using Core Graphics so it needs no window server.
// Usage: swiftc -o /tmp/make-icon ios/scripts/make-icon.swift && /tmp/make-icon ios/AquaRestore/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let manta = "M54.00,39.60 L56.50,39.00 C56.90,36.20 57.00,33.60 56.60,31.60 C59.60,32.00 61.60,34.60 61.60,38.20 C68.00,38.60 77.50,42.20 86.00,50.00 C78.50,53.20 69.50,55.20 63.00,61.60 C60.20,65.00 58.00,67.00 55.90,68.20 L54.70,83.00 L54.00,84.00 L53.30,83.00 L52.10,68.20 C50.00,67.00 47.80,65.00 45.00,61.60 C38.50,55.20 29.50,53.20 22.00,50.00 C30.50,42.20 40.00,38.60 46.40,38.20 C46.40,34.60 48.40,32.00 51.40,31.60 C51.00,33.60 51.10,36.20 51.50,39.00 L54.00,39.60 Z"
let leftWing = "M46.50,43.60 C40.50,42.90 34.20,44.60 29.40,48.40 C35.40,47.00 40.80,47.20 45.80,48.90 Z"
let rightWing = "M61.50,43.60 C67.50,42.90 73.80,44.60 78.60,48.40 C72.60,47.00 67.20,47.20 62.20,48.90 Z"

func path(_ data: String) -> CGPath {
    let p = CGMutablePath()
    var tokens: [String] = [], number = ""
    for ch in data {
        if ch.isLetter { if !number.isEmpty { tokens.append(number); number = "" }; tokens.append(String(ch)) }
        else if ch == " " || ch == "," { if !number.isEmpty { tokens.append(number); number = "" } }
        else { number.append(ch) }
    }
    if !number.isEmpty { tokens.append(number) }
    var i = 0, command = ""
    func next() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    while i < tokens.count {
        if tokens[i].first!.isLetter { command = tokens[i]; i += 1 }
        switch command {
        case "M": p.move(to: CGPoint(x: next(), y: next())); command = "L"
        case "L": p.addLine(to: CGPoint(x: next(), y: next()))
        case "C":
            // SVG lists the two control points first and the end point last.
            let c1 = CGPoint(x: next(), y: next()), c2 = CGPoint(x: next(), y: next()), end = CGPoint(x: next(), y: next())
            p.addCurve(to: end, control1: c1, control2: c2)
        case "Z": p.closeSubpath()
        default: i += 1
        }
    }
    return p
}
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// Opaque, because the App Store rejects icons with an alpha channel.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// CG's origin is bottom-left; flip so the 108-unit art reads top-down, then window 80 x 80 units around the manta.
let scale = CGFloat(size) / 80
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.translateBy(x: -14 * scale, y: -17 * scale)
ctx.scaleBy(x: scale, y: scale)

func gradient(_ rect: CGRect, _ top: UInt32, _ bottom: UInt32) {
    ctx.saveGState()
    ctx.clip(to: rect)
    let g = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 18), end: CGPoint(x: 0, y: 90), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
gradient(CGRect(x: 0, y: 0, width: 54, height: 108), 0x3A8FD9, 0x0B3566)
gradient(CGRect(x: 54, y: 0, width: 54, height: 108), 0x4FD1BC, 0xF0B880)

func half(_ rect: CGRect, body: UInt32, wing: CGPath, wingColor: UInt32) {
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.addPath(path(manta)); ctx.setFillColor(color(body)); ctx.fillPath()
    ctx.addPath(wing); ctx.setFillColor(color(wingColor)); ctx.fillPath()
    ctx.restoreGState()
}
half(CGRect(x: 0, y: 0, width: 54, height: 108), body: 0x143E6E, wing: path(leftWing), wingColor: 0x5F95C8)
half(CGRect(x: 54, y: 0, width: 54, height: 108), body: 0x263238, wing: path(rightWing), wingColor: 0xF4F1EA)
ctx.setFillColor(color(0xFFFFFF, 0.9)); ctx.fill(CGRect(x: 53.4, y: 18, width: 1.2, height: 72))
ctx.setFillColor(color(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: 49, y: 75.5, width: 10, height: 10))
func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ hex: UInt32) {
    ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c); ctx.closePath(); ctx.setFillColor(color(hex)); ctx.fillPath()
}
triangle(CGPoint(x: 52.6, y: 78.4), CGPoint(x: 50.6, y: 80.5), CGPoint(x: 52.6, y: 82.6), 0x2C7BC4)
triangle(CGPoint(x: 55.4, y: 78.4), CGPoint(x: 57.4, y: 80.5), CGPoint(x: 55.4, y: 82.6), 0x2BAE9A)

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output.path)")
