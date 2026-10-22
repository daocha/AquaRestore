import Foundation

/// Color statistics behind a recommendation.
struct Analysis: Equatable {
    let grade: Grade
    let confidence: Float
    let cast: String
    let redLoss: Float
}

/// Public stand-in for the private grading core: a basic gray-world estimate.
enum AutoGrade {
    /// Pixels are 0xAARRGGBB, as in `ColorGrade`.
    static func analyze(_ frames: [[UInt32]], hdr: Bool = false) -> Analysis {
        precondition(!frames.isEmpty)
        var r: Double = 0, g: Double = 0, b: Double = 0
        var valid = 0, visible = 0
        for frame in frames {
            for argb in frame where (argb >> 24) > 127 {
                visible += 1
                let pr = Float((argb >> 16) & 255) / 255, pg = Float((argb >> 8) & 255) / 255, pb = Float(argb & 255) / 255
                // Skip near-black noise and clipped highlights.
                let top = max(pr, pg, pb)
                if top < 0.04 || top > 0.97 { continue }
                r += Double(pr); g += Double(pg); b += Double(pb); valid += 1
            }
        }
        if valid == 0 { return Analysis(grade: .neutral, confidence: 0, cast: "insufficient", redLoss: 0) }
        let mr = Float(r / Double(valid)), mg = Float(g / Double(valid)), mb = Float(b / Double(valid))
        let surviving = max(mg, mb, 0.03)
        let loss = min(max((surviving - mr) / surviving, 0), 1)
        var grade = Grade.neutral
        grade.red = min(loss * 0.8, 0.8)
        grade.temperature = min(max((mb - mr) / surviving * 0.4, 0), 0.4)
        grade.tint = min(max((mg - mb) / surviving * 0.5, 0), 0.4)
        grade.contrast = 0.05
        grade.saturation = 0.1 * loss
        grade.strength = 0.8
        let cast = loss < 0.1 ? "balanced" : mg > mb ? "green" : "blue"
        return Analysis(grade: grade, confidence: Float(valid) / Float(max(1, visible)), cast: cast, redLoss: loss)
    }
}
