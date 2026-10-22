import AVFoundation
import CoreVideo
import Metal

/// Thread-safe grade snapshot shared with the render thread. Slider changes only replace the value;
/// the player and decoder are never rebuilt.
final class GradeState {
    private let lock = NSLock()
    private var _grade: Grade
    private var _compare = false
    init(_ grade: Grade = Grade()) { _grade = grade }

    var grade: Grade {
        get { lock.lock(); defer { lock.unlock() }; return _grade }
        set { lock.lock(); _grade = newValue; lock.unlock() }
    }
    var compare: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _compare }
        set { lock.lock(); _compare = newValue; lock.unlock() }
    }
}

/// How the source's transfer curve is read by the shader.
enum HdrMode: Int32 { case sdr = 0, hlg = 1, pq = 2 }

/// Carries everything a frame needs, since the compositor class is instantiated by AVFoundation.
final class GradeInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let state: GradeState
    let hdr: HdrMode
    /// Maps display pixels back to the track's natural pixels (inverse of the preferred transform).
    let inverse: CGAffineTransform
    let naturalSize: CGSize
    let displaySize: CGSize

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, state: GradeState, hdr: HdrMode,
         transform: CGAffineTransform, naturalSize: CGSize) {
        self.timeRange = timeRange
        self.trackID = trackID
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.state = state
        self.hdr = hdr
        inverse = transform.inverted()
        self.naturalSize = naturalSize
        displaySize = GradeInstruction.displaySize(naturalSize, transform)
    }

    static func displaySize(_ natural: CGSize, _ transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
}

/// Matches the `Params` struct in the Metal source below (144 bytes).
private struct Params {
    var a = SIMD4<Float>(0, 0, 0, 0)       // red, temperature, tint, exposure
    var b = SIMD4<Float>(0, 0, 0, 0)       // haze, contrast, saturation, shadows
    var black = SIMD4<Float>(0, 0, 0, 0)
    var white = SIMD4<Float>(1, 1, 1, 1)
    var levels: Float = 0
    var strength: Float = 0
    var mode: Int32 = 0
    var coolProtection: Float = 0
    var m0 = SIMD4<Float>(1, 0, 0, 0)      // source x = m0.x * x + m0.y * y + m0.z
    var m1 = SIMD4<Float>(0, 1, 0, 0)
    var displaySize = SIMD2<Float>(1, 1)
    var naturalSize = SIMD2<Float>(1, 1)
    var taps: Int32 = 1
    var pad2 = SIMD3<Int32>(0, 0, 0)
    var clarity: Float = 0
    var radius: Float = 1                  // clarity radius in output pixels
    var pad3 = SIMD2<Float>(0, 0)
}

enum GradeError: Error { case metalUnavailable, textureFailed }

/// Compiled once; each frame only sets uniforms.
final class MetalGrader {
    static let shared: MetalGrader? = try? MetalGrader()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var cache: CVMetalTextureCache?

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw GradeError.metalUnavailable }
        self.device = device
        self.queue = queue
        let library = try device.makeLibrary(source: GradeShader.source, options: nil)
        guard let function = library.makeFunction(name: "grade") else { throw GradeError.metalUnavailable }
        pipeline = try device.makeComputePipelineState(function: function)
        let usage = MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue
        CVMetalTextureCacheCreate(nil, nil, device, [kCVMetalTextureUsage as String: usage] as CFDictionary, &cache)
    }

    private func texture(_ buffer: CVPixelBuffer) throws -> (MTLTexture, CVMetalTexture) {
        let format: MTLPixelFormat = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_64RGBAHalf ? .rgba16Float : .bgra8Unorm
        var cvTexture: CVMetalTexture?
        guard let cache,
              CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, format,
                  CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { throw GradeError.textureFailed }
        return (texture, cvTexture)
    }

    func render(_ instruction: GradeInstruction, source: CVPixelBuffer, output: CVPixelBuffer, completion: @escaping (Bool) -> Void) {
        do {
            let (input, inputKeep) = try texture(source)
            let (target, targetKeep) = try texture(output)
            let hdr = instruction.hdr != .sdr
            let p = instruction.state.grade.effective()
            let t = instruction.inverse
            var params = Params()
            params.a = SIMD4(p.red, p.temperature, p.tint, p.exposure)
            params.b = SIMD4(p.haze, p.contrast, p.saturation, p.shadows)
            params.black = SIMD4(p.blackR, p.blackG, p.blackB, 0)
            params.white = SIMD4(p.whiteR, p.whiteG, p.whiteB, 1)
            // HDR uses only the amount; SDR thumbnail endpoints never enter the HDR curve.
            params.levels = p.levels
            params.strength = instruction.state.compare ? 0 : p.strength
            params.mode = instruction.hdr.rawValue
            params.coolProtection = p.coolProtection
            params.m0 = SIMD4(Float(t.a), Float(t.c), Float(t.tx), 0)
            params.m1 = SIMD4(Float(t.b), Float(t.d), Float(t.ty), 0)
            params.displaySize = SIMD2(Float(instruction.displaySize.width), Float(instruction.displaySize.height))
            params.naturalSize = SIMD2(Float(instruction.naturalSize.width), Float(instruction.naturalSize.height))
            // Downscaling averages a few taps per output pixel instead of aliasing.
            let ratio = max(instruction.displaySize.width / CGFloat(target.width), instruction.displaySize.height / CGFloat(target.height))
            params.taps = Int32(min(max(Int(ratio.rounded(.up)), 1), 4))
            params.clarity = p.clarity
            params.radius = Float(Clarity.radius(target.width, target.height))

            guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else { completion(false); return }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(input, index: 0)
            encoder.setTexture(target, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            let group = MTLSize(width: 16, height: 16, depth: 1)
            let grid = MTLSize(width: (target.width + 15) / 16, height: (target.height + 15) / 16, depth: 1)
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
            encoder.endEncoding()
            buffer.addCompletedHandler { b in
                _ = inputKeep; _ = targetKeep
                completion(b.status == .completed)
            }
            buffer.commit()
        } catch { completion(false) }
    }
}

/// Grades every frame on the GPU. One instance serves a whole player or export.
class GradeCompositor: NSObject, AVVideoCompositing {
    class var pixelFormat: OSType { kCVPixelFormatType_32BGRA }

    private let queue = DispatchQueue(label: "AquaRestore.compositor", qos: .userInitiated)
    private var generation = 0
    private let lock = NSLock()

    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [Self.pixelFormat], kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: Self.pixelFormat, kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    var supportsWideColorSourceFrames: Bool { true }
    var supportsHDRSourceFrames: Bool { true }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func cancelAllPendingVideoCompositionRequests() {
        lock.lock(); generation += 1; lock.unlock()
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock(); let mine = generation; lock.unlock()
        queue.async {
            self.lock.lock(); let current = self.generation; self.lock.unlock()
            guard current == mine else { request.finishCancelledRequest(); return }
            guard let instruction = request.videoCompositionInstruction as? GradeInstruction,
                  let source = request.sourceFrame(byTrackID: instruction.trackID),
                  let output = request.renderContext.newPixelBuffer(),
                  let grader = MetalGrader.shared else {
                request.finish(with: GradeError.metalUnavailable)
                return
            }
            grader.render(instruction, source: source, output: output) { ok in
                if ok { request.finish(withComposedVideoFrame: output) } else { request.finish(with: GradeError.textureFailed) }
            }
        }
    }
}

/// HDR sources are composited in half-float RGBA so highlights above SDR white survive.
final class HdrGradeCompositor: GradeCompositor {
    override class var pixelFormat: OSType { kCVPixelFormatType_64RGBAHalf }
}

/// Builds the video composition that grades `track` live, for both the preview and the export.
enum GradeComposition {
    static func make(track: AVAssetTrack, trackID: CMPersistentTrackID, duration: CMTime, state: GradeState,
                     hdr: HdrMode, transform: CGAffineTransform, naturalSize: CGSize,
                     renderSize: CGSize, frameDuration: CMTime) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = hdr == .sdr ? GradeCompositor.self : HdrGradeCompositor.self
        composition.renderSize = renderSize
        composition.frameDuration = frameDuration
        // Follow actual source sample times, including variable frame rate. frameDuration is only
        // the fallback for empty edits; a Custom fps cap is applied later by FrameCadence.
        composition.sourceTrackIDForFrameTiming = trackID
        composition.instructions = [GradeInstruction(timeRange: CMTimeRange(start: .zero, duration: duration), trackID: trackID,
                                                     state: state, hdr: hdr, transform: transform, naturalSize: naturalSize)]
        switch hdr {
        case .sdr:
            composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        case .hlg:
            composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
            composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        case .pq:
            composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            composition.colorTransferFunction = AVVideoTransferFunction_SMPTE_ST_2084_PQ
            composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        }
        return composition
    }
}
