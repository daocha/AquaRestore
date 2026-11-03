import AVFoundation
import CoreImage
import UIKit

/// GPU composition only; restoration remains in the existing renderer.
enum ComparisonFrame {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func finish(_ request: AVAsynchronousVideoCompositionRequest, instruction: GradeInstruction,
                       source: CVPixelBuffer, graded: CVPixelBuffer, duration: Double, grader: MetalGrader) {
        guard let original = request.renderContext.newPixelBuffer(), let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: GradeError.textureFailed); return
        }
        let neutral = GradeInstruction(timeRange: instruction.timeRange, trackID: instruction.trackID, state: GradeState(.neutral),
            hdr: instruction.hdr, transform: instruction.inverse.inverted(), naturalSize: instruction.naturalSize)
        grader.render(neutral, source: source, output: original, time: request.compositionTime.seconds) { ok in
            guard ok else { request.finish(with: GradeError.textureFailed); return }
            DispatchQueue.global(qos: .utility).async {
                let width = CVPixelBufferGetWidth(output), height = CVPixelBufferGetHeight(output)
                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                let fraction = request.compositionTime.seconds / max(duration, 0.001)
                let progress = min(1, max(0, (fraction - 0.25) / 0.5))
                let split = CGFloat(width) * progress
                let space = CGColorSpace(name: instruction.hdr == .sdr ? CGColorSpace.itur_709 : CGColorSpace.extendedLinearITUR_2020)!
                var image = CIImage(cvPixelBuffer: graded, options: [.colorSpace: space]).cropped(to: CGRect(x: 0, y: 0, width: split, height: CGFloat(height)))
                    .composited(over: CIImage(cvPixelBuffer: original, options: [.colorSpace: space]))
                if progress > 0 && progress < 1 {
                    image = CIImage(color: .white).cropped(to: CGRect(x: split, y: 0, width: max(1, CGFloat(width)/400), height: CGFloat(height))).composited(over: image)
                }
                if let mark = instruction.comparisonMark { image = CIImage(cgImage: mark).composited(over: image) }
                context.render(image, to: output, bounds: bounds, colorSpace: space)
                request.finish(withComposedVideoFrame: output)
            }
        }
    }
}
