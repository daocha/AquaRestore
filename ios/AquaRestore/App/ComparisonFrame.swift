import AVFoundation
import CoreImage
import UIKit

/// Composes decoded textures directly; no per-frame seeking, bitmap extraction or CPU pixel copies.
enum ComparisonFrame {
    private static let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    private static let queue = DispatchQueue(label: "AquaRestore.comparison.compose", qos: .utility)

    static func originalImage(_ image: CIImage, instruction: GradeInstruction, size: CGSize) -> CIImage {
        let natural = instruction.naturalSize, display = instruction.displaySize
        // Track transforms use top-left coordinates; Core Image uses bottom-left coordinates.
        let toNatural = CGAffineTransform(scaleX: natural.width / image.extent.width, y: natural.height / image.extent.height)
        let toTop = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: natural.height)
        let toBottom = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: display.height)
        let transform = toNatural.concatenating(toTop).concatenating(instruction.inverse.inverted()).concatenating(toBottom)
            .concatenating(CGAffineTransform(scaleX: size.width / display.width, y: size.height / display.height))
        return image.transformed(by: transform)
    }

    static func finish(_ request: AVAsynchronousVideoCompositionRequest, instruction: GradeInstruction,
                       source: CVPixelBuffer, graded: CVPixelBuffer, duration: Double, grader: MetalGrader) {
        guard let output = request.renderContext.newPixelBuffer() else { request.finish(with: GradeError.textureFailed); return }
        let size = CGSize(width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output))
        if instruction.hdr == .sdr {
            let original = originalImage(CIImage(cvPixelBuffer: source), instruction: instruction, size: size)
            compose(request, instruction: instruction, original: original, graded: graded, output: output, duration: duration)
        } else {
            // Preserve the renderer's HDR transfer handling for the unadjusted half too.
            guard let original = request.renderContext.newPixelBuffer() else { request.finish(with: GradeError.textureFailed); return }
            let neutral = GradeInstruction(timeRange: instruction.timeRange, trackID: instruction.trackID, state: GradeState(.neutral),
                hdr: instruction.hdr, transform: instruction.inverse.inverted(), naturalSize: instruction.naturalSize)
            grader.render(neutral, source: source, output: original, time: request.compositionTime.seconds) { ok in
                guard ok else { request.finish(with: GradeError.textureFailed); return }
                compose(request, instruction: instruction, original: CIImage(cvPixelBuffer: original), graded: graded, output: output, duration: duration)
            }
        }
    }
    private static func compose(_ request: AVAsynchronousVideoCompositionRequest, instruction: GradeInstruction,
                                original: CIImage, graded: CVPixelBuffer, output: CVPixelBuffer, duration: Double) {
        queue.async {
            let width = CGFloat(CVPixelBufferGetWidth(output)), height = CGFloat(CVPixelBufferGetHeight(output))
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let progress = min(1, max(0, (request.compositionTime.seconds / max(duration, 0.001) - 0.25) / 0.5))
            let split = width * CGFloat(progress)
            var image = CIImage(cvPixelBuffer: graded).cropped(to: CGRect(x: 0, y: 0, width: split, height: height)).composited(over: original)
            if progress > 0 && progress < 1 {
                image = CIImage(color: .white).cropped(to: CGRect(x: split, y: 0, width: max(1, width/400), height: height)).composited(over: image)
            }
            if let mark = instruction.comparisonMark { image = CIImage(cgImage: mark).composited(over: image) }
            context.render(image, to: output, bounds: bounds, colorSpace: nil)
            request.finish(withComposedVideoFrame: output)
        }
    }
}
