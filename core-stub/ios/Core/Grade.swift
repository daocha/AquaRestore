import Foundation

// Public stand-in for the private grading core: same API, deliberately basic formula.
// See core-stub/README.md.

/// Immutable snapshots are shared with the render thread; an export gets its own frozen snapshot.
struct Grade: Equatable {
    var red: Float = 0.3
    var temperature: Float = 0.1
    var tint: Float = 0.05
    var exposure: Float = 0
    var haze: Float = 0.1
    var contrast: Float = 0.05
    var saturation: Float = 0.1
    var shadows: Float = 0.05
    var strength: Float = 1
    var levels: Float = 0
    var blackR: Float = 0, blackG: Float = 0, blackB: Float = 0
    var whiteR: Float = 1, whiteG: Float = 1, whiteB: Float = 1
    var coolProtection: Float = 0
    var clarity: Float = 0

    /// Intensity (0–200%) scales every correction parameter; only 0% is a pixel-exact bypass.
    func effective() -> Grade {
        let k = min(max(strength, 0), 2)
        var g = self
        g.red = red * k
        g.temperature = temperature * k
        g.tint = tint * k
        g.exposure = exposure * k
        g.haze = haze * k
        g.contrast = contrast * k
        g.saturation = max(saturation * k, -1)
        g.shadows = shadows * k
        g.levels = min(max(levels * k, 0), 1)
        g.coolProtection = min(max(coolProtection * k, 0), 1)
        g.clarity = clarity * k
        g.strength = k == 0 ? 0 : 1
        return g
    }

    static let neutral = Grade(red: 0, temperature: 0, tint: 0, exposure: 0, haze: 0, contrast: 0, saturation: 0, shadows: 0, strength: 0)
    static let reef = Grade()
    static let blue = Grade(red: 0.5, temperature: 0.25, haze: 0.15)
    static let green = Grade(red: 0.4, tint: 0.3, haze: 0.15)
}

enum ColorGrade {
    static func pixel(_ argb: UInt32, _ grade: Grade) -> UInt32 {
        let e = grade.effective()
        return pixel(argb, e, exp2(e.exposure))
    }

    /// `detail` is `Clarity.detail` of the source pixel; zero when clarity is off. Matches `GradeShader`.
    static func pixel(_ argb: UInt32, _ p: Grade, _ gain: Float, _ detail: Float = 0) -> UInt32 {
        if p.strength == 0 { return argb }
        let r0 = Float((argb >> 16) & 255) / 255
        let g0 = Float((argb >> 8) & 255) / 255
        let b0 = Float(argb & 255) / 255
        func level(_ x: Float, _ black: Float, _ white: Float) -> Float {
            x + (min(max((x - black) / (white - black), 0), 1) - x) * p.levels
        }
        var r = level(r0, p.blackR, p.whiteR) * (1 + 0.5 * p.red) * (1 + 0.2 * p.temperature) * gain
        var g = level(g0, p.blackG, p.whiteG) * (1 - 0.2 * p.tint) * gain
        var b = level(b0, p.blackB, p.whiteB) * (1 - 0.2 * p.temperature) * gain
        let contrast = 1 + p.contrast + 0.5 * p.haze
        r = (r - 0.5) * contrast + 0.5; g = (g - 0.5) * contrast + 0.5; b = (b - 0.5) * contrast + 0.5
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let shadow = 1 - min(max(luma, 0), 1)
        let lift = p.shadows * 0.2 * shadow * shadow
        r = luma + (r - luma) * (1 + p.saturation) + lift
        g = luma + (g - luma) * (1 + p.saturation) + lift
        b = luma + (b - luma) * (1 + p.saturation) + lift
        r += (min(r, g) - r) * p.coolProtection * 0.5
        let sharpen = p.clarity * 2 * detail
        r += sharpen; g += sharpen; b += sharpen
        func out(_ x: Float, _ original: Float) -> UInt32 {
            UInt32(min(max(((original + (min(max(x, 0), 1) - original) * p.strength) * 255).rounded(), 0), 255))
        }
        return (argb & 0xff00_0000) | out(r, r0) << 16 | out(g, g0) << 8 | out(b, b0)
    }
}

/// Luma minus the mean of four taps `radius` pixels away, matching `GradeShader`.
enum Clarity {
    static func radius(_ width: Int, _ height: Int) -> Int { max(1, Int((Float(min(width, height)) * 0.004).rounded())) }

    /// Display-encoded BT.709 luma in 0...255, one byte per pixel.
    static func luma(_ pixels: [UInt32]) -> [UInt8] {
        pixels.map { (p: UInt32) -> UInt8 in
            let r = Float((p >> 16) & 255), g = Float((p >> 8) & 255), b = Float(p & 255)
            let y: Float = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return UInt8(y.rounded())
        }
    }

    static func detail(_ luma: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ x: Int, _ y: Int, _ radius: Int) -> Float {
        func at(_ dx: Int, _ dy: Int) -> Float {
            Float(luma[min(max(y + dy, 0), height - 1) * width + min(max(x + dx, 0), width - 1)])
        }
        let blur: Float = (at(radius, 0) + at(-radius, 0) + at(0, radius) + at(0, -radius)) / 4
        return (at(0, 0) - blur) / 255
    }
}
