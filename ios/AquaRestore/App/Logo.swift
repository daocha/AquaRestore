import SwiftUI

/// Parses the absolute M / L / C / Z path data used by the Android launcher vectors.
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var number = ""
        for ch in data {
            if ch.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else if ch == "-" && !number.isEmpty {
                tokens.append(number); number = "-"
            } else { number.append(ch) }
        }
        if !number.isEmpty { tokens.append(number) }
        var i = 0
        func next() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        var command = ""
        while i < tokens.count {
            if tokens[i].first?.isLetter == true { command = tokens[i]; i += 1 }
            switch command {
            case "M": path.move(to: CGPoint(x: next(), y: next())); command = "L"
            case "L": path.addLine(to: CGPoint(x: next(), y: next()))
            case "C":
                // SVG lists the two control points first and the end point last.
                let c1 = CGPoint(x: next(), y: next()), c2 = CGPoint(x: next(), y: next()), end = CGPoint(x: next(), y: next())
                path.addCurve(to: end, control1: c1, control2: c2)
            case "Z", "z": path.closeSubpath()
            default: i += 1
            }
        }
        return path
    }
}

/// The launcher icon's own layers (a manta seen twice: blue-cast on the left, true charcoal and white on the
/// right, split by a compare seam with its handle), drawn in the 108-unit viewport.
enum Logo {
    static let manta = "M54.00,39.60 L56.50,39.00 C56.90,36.20 57.00,33.60 56.60,31.60 C59.60,32.00 61.60,34.60 61.60,38.20 C68.00,38.60 77.50,42.20 86.00,50.00 C78.50,53.20 69.50,55.20 63.00,61.60 C60.20,65.00 58.00,67.00 55.90,68.20 L54.70,83.00 L54.00,84.00 L53.30,83.00 L52.10,68.20 C50.00,67.00 47.80,65.00 45.00,61.60 C38.50,55.20 29.50,53.20 22.00,50.00 C30.50,42.20 40.00,38.60 46.40,38.20 C46.40,34.60 48.40,32.00 51.40,31.60 C51.00,33.60 51.10,36.20 51.50,39.00 L54.00,39.60 Z"
    static let leftWing = "M46.50,43.60 C40.50,42.90 34.20,44.60 29.40,48.40 C35.40,47.00 40.80,47.20 45.80,48.90 Z"
    static let rightWing = "M61.50,43.60 C67.50,42.90 73.80,44.60 78.60,48.40 C72.60,47.00 67.20,47.20 62.20,48.90 Z"

    static func background(_ ctx: inout GraphicsContext) {
        let left = LinearGradient(colors: [Color(hex: 0x3A8FD9), Color(hex: 0x0B3566)], startPoint: .init(x: 0, y: 18 / 108), endPoint: .init(x: 0, y: 90 / 108))
        let right = LinearGradient(colors: [Color(hex: 0x4FD1BC), Color(hex: 0xF0B880)], startPoint: .init(x: 0, y: 18 / 108), endPoint: .init(x: 0, y: 90 / 108))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 54, height: 108)), with: .linearGradient(Gradient(colors: [Color(hex: 0x3A8FD9), Color(hex: 0x0B3566)]), startPoint: CGPoint(x: 0, y: 18), endPoint: CGPoint(x: 0, y: 90)))
        ctx.fill(Path(CGRect(x: 54, y: 0, width: 54, height: 108)), with: .linearGradient(Gradient(colors: [Color(hex: 0x4FD1BC), Color(hex: 0xF0B880)]), startPoint: CGPoint(x: 0, y: 18), endPoint: CGPoint(x: 0, y: 90)))
        _ = (left, right)
    }

    static func foreground(_ ctx: inout GraphicsContext) {
        let body = SVGPath.parse(manta)
        var l = ctx
        l.clip(to: Path(CGRect(x: 0, y: 0, width: 54, height: 108)))
        l.fill(body, with: .color(Color(hex: 0x143E6E)))
        l.fill(SVGPath.parse(leftWing), with: .color(Color(hex: 0x5F95C8)))
        var r = ctx
        r.clip(to: Path(CGRect(x: 54, y: 0, width: 54, height: 108)))
        r.fill(body, with: .color(Color(hex: 0x263238)))
        r.fill(SVGPath.parse(rightWing), with: .color(Color(hex: 0xF4F1EA)))
        ctx.fill(Path(CGRect(x: 53.4, y: 18, width: 1.2, height: 72)), with: .color(Color.white.opacity(0.9)))
        ctx.fill(Path(ellipseIn: CGRect(x: 49, y: 75.5, width: 10, height: 10)), with: .color(.white))
        var leftArrow = Path(); leftArrow.move(to: CGPoint(x: 52.6, y: 78.4)); leftArrow.addLine(to: CGPoint(x: 50.6, y: 80.5)); leftArrow.addLine(to: CGPoint(x: 52.6, y: 82.6)); leftArrow.closeSubpath()
        var rightArrow = Path(); rightArrow.move(to: CGPoint(x: 55.4, y: 78.4)); rightArrow.addLine(to: CGPoint(x: 57.4, y: 80.5)); rightArrow.addLine(to: CGPoint(x: 55.4, y: 82.6)); rightArrow.closeSubpath()
        ctx.fill(leftArrow, with: .color(Color(hex: 0x2C7BC4)))
        ctx.fill(rightArrow, with: .color(Color(hex: 0x2BAE9A)))
    }
}

/// The launcher icon cropped to its visible circle (the middle 72 of 108 units), as in the Android top bar.
struct AppLogo: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, canvas in
            // 72 of the 108 units fill the circle.
            let scale = canvas.width / 72
            ctx.translateBy(x: -18 * scale, y: -18 * scale)
            ctx.scaleBy(x: scale, y: scale)
            Logo.background(&ctx)
            Logo.foreground(&ctx)
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The home screen illustration: light rays, layered waves and bubbles over deep water.
struct OceanArt: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            for i in 0...5 {
                let x = CGFloat(i) * 0.15
                var ray = Path()
                ray.move(to: CGPoint(x: w * (0.08 + x), y: 0))
                ray.addLine(to: CGPoint(x: w * (0.3 + x), y: h))
                ray.addLine(to: CGPoint(x: w * (0.42 + x), y: h))
                ray.closeSubpath()
                ctx.fill(ray, with: .color(Color(hex: 0x8BECE3, alpha: 0.04)))
            }
            let colors = [0x145C69, 0x167C7E, 0x20A39A, 0x46C9AC]
            for i in 0...3 {
                let f = CGFloat(i)
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: h * (0.64 + f * 0.09)))
                wave.addCurve(to: CGPoint(x: w, y: h * (0.6 + f * 0.08)),
                              control1: CGPoint(x: w * 0.3, y: h * (0.35 + f * 0.12)),
                              control2: CGPoint(x: w * 0.55, y: h * (1.05 - f * 0.06)))
                wave.addLine(to: CGPoint(x: w, y: h))
                wave.addLine(to: CGPoint(x: 0, y: h))
                wave.closeSubpath()
                ctx.fill(wave, with: .color(Color(hex: UInt32(colors[i]))))
            }
            for i in 0...13 {
                let r = CGFloat(2 + i % 3)
                let center = CGPoint(x: w * CGFloat(i * 37 % 93) / 100, y: h * CGFloat(i * 19 % 58 + 8) / 100)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(0.18)))
            }
        }
        .background(LinearGradient(colors: [Color(hex: 0x124A60), Color(hex: 0x071E31)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
    }
}
