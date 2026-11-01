import AVFoundation
import CoreVideo
import ImageIO
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
    var clarity: Float = 0
    var radius: Float = 1                  // clarity radius in output pixels
    var pad3 = SIMD2<Float>(0, 0)
}

enum GradeError: Error { case metalUnavailable, textureFailed }

/// Compiled once; each frame only sets uniforms.
final class MetalGrader {
    static let shared: MetalGrader? = {
        do { return try MetalGrader() } catch {
            NSLog("AquaRestore: Metal grader unavailable: \(error)")
            return nil
        }
    }()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let linearize: MTLComputePipelineState
    private let textureLock = NSLock()
    private let linearTextures: NSCache<NSString, AnyObject> = {
        let cache = NSCache<NSString, AnyObject>()
        cache.countLimit = 1
        return cache
    }()
    private var cache: CVMetalTextureCache?

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw GradeError.metalUnavailable }
        self.device = device
        self.queue = queue
        let library = try device.makeLibrary(source: GradeShader.source, options: nil)
        guard let function = library.makeFunction(name: "grade") else { throw GradeError.metalUnavailable }
        pipeline = try device.makeComputePipelineState(function: function)
        guard let conversion = library.makeFunction(name: "linearize") else { throw GradeError.metalUnavailable }
        linearize = try device.makeComputePipelineState(function: conversion)
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

    private func workingTexture(width: Int, height: Int) throws -> MTLTexture {
        textureLock.lock(); defer { textureLock.unlock() }
        let key = "\(width)x\(height)" as NSString
        if let texture = linearTextures.object(forKey: key) as? MTLTexture { return texture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw GradeError.textureFailed }
        linearTextures.setObject(texture, forKey: key, cost: width * height * 8)
        return texture
    }

    func render(_ instruction: GradeInstruction, source: CVPixelBuffer, output: CVPixelBuffer, completion: @escaping (Bool) -> Void) {
        do {
            let (input, inputKeep) = try texture(source)
            let (target, targetKeep) = try texture(output)
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
            params.clarity = p.clarity
            params.radius = Float(Clarity.radius(target.width, target.height))

            let working = instruction.hdr == .sdr ? input : try workingTexture(width: input.width, height: input.height)
            guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else {
                GradeLog.failure("no Metal command buffer or encoder")
                completion(false); return
            }
            if instruction.hdr != .sdr {
                encoder.setComputePipelineState(linearize)
                encoder.setTexture(input, index: 0)
                encoder.setTexture(working, index: 1)
                encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
                encoder.dispatchThreadgroups(MTLSize(width: (input.width + 15) / 16, height: (input.height + 15) / 16, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                // The encoder's default serial dispatch already orders this pass before the grading pass.
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(working, index: 0)
            encoder.setTexture(target, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            let group = MTLSize(width: 16, height: 16, depth: 1)
            let grid = MTLSize(width: (target.width + 15) / 16, height: (target.height + 15) / 16, depth: 1)
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
            encoder.endEncoding()
            buffer.addCompletedHandler { b in
                _ = inputKeep; _ = targetKeep
                if b.status != .completed { GradeLog.failure("command buffer status \(b.status.rawValue): \(String(describing: b.error))") }
                else { FrameProbe.log(source: source, output: output, hdr: instruction.hdr) }
                completion(b.status == .completed)
            }
            buffer.commit()
        } catch {
            GradeLog.failure("Metal render setup failed: \(error)")
            completion(false)
        }
    }
}

/// Logs how bright the first few decoded and graded frames are, so a black preview shows whether the
/// decoder, the grading pass or the display is to blame.
enum FrameProbe {
    private static let lock = NSLock()
    private static var logged = 0
    private static var requested = 0

    /// A new video starts counting again, so every clip gets its own first frames in the log.
    static func reset() { lock.lock(); logged = 0; requested = 0; lock.unlock() }

    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requested }

    static func request(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock(); requested += 1; let mine = requested; lock.unlock()
        if mine <= 3 {
            NSLog("AquaRestore: frame request \(mine) at \(request.compositionTime.seconds)s sources=\(request.sourceTrackIDs) output \(request.renderContext.size)")
        }
    }

    static func log(source: CVPixelBuffer, output: CVPixelBuffer, hdr: HdrMode) {
        lock.lock(); logged += 1; let mine = logged; lock.unlock()
        guard mine <= 3 else { return }
        NSLog("AquaRestore: frame probe \(mine): decoded \(describe(source)), graded \(describe(output)), hdr \(hdr.rawValue)")
        // The first frame of each video is saved as a picture, so a garbled preview can be looked at: the decoded frame
        // and the graded one show which of the two went wrong.
        if mine == 1 { save(source, as: "decoded.png"); save(output, as: "graded.png") }
    }

    /// A half-float value as a Float, without relying on `Float16` (not available on every simulator architecture).
    private static func half(_ bits: UInt16) -> Float {
        let sign: Float = bits & 0x8000 != 0 ? -1 : 1
        let exponent = Int((bits >> 10) & 0x1F), fraction = Float(bits & 0x3FF)
        if exponent == 0 { return sign * fraction * 5.960_464_5e-8 }
        if exponent == 31 { return fraction == 0 ? sign * Float.infinity : Float.nan }
        return sign * (1 + fraction / 1024) * Float(sign: .plus, exponent: exponent - 15, significand: 1)
    }

    /// Saves a small copy of the frame, from either of the two pixel formats the compositor uses (8-bit and half-float).
    private static func save(_ buffer: CVPixelBuffer, as name: String) {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_64RGBAHalf else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        // Small enough to open and share quickly.
        let scale = min(1, 540 / CGFloat(max(width, height)))
        let w = max(1, Int(CGFloat(width) * scale)), h = max(1, Int(CGFloat(height) * scale))
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let sy = min(height - 1, y * height / h)
            for x in 0..<w {
                let sx = min(width - 1, x * width / w)
                let out = (y * w + x) * 4
                if format == kCVPixelFormatType_32BGRA {
                    let p = base.assumingMemoryBound(to: UInt8.self), o = sy * row + sx * 4
                    rgba[out] = p[o + 2]; rgba[out + 1] = p[o + 1]; rgba[out + 2] = p[o]
                } else {
                    let p = base.assumingMemoryBound(to: UInt16.self), o = sy * (row / 2) + sx * 4
                    for c in 0..<3 { rgba[out + c] = UInt8(min(max(half(p[o + c]), 0), 1) * 255) }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent),
              let folder = try? DevFiles.folder("FrameProbe"),
              let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        if CGImageDestinationFinalize(destination) { NSLog("AquaRestore: frame probe picture saved: \(DevFiles.shown(folder.appendingPathComponent(name)))") }
    }

    private static func describe(_ buffer: CVPixelBuffer) -> String {
        let size = "\(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))"
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
            return "\(size) format \(CVPixelBufferGetPixelFormatType(buffer))"
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return "\(size) unreadable" }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var sum = 0, peak = 0, alpha = 0, count = 0
        for gy in 1...8 { for gx in 1...8 {
            let o = (height * gy / 9) * row + (width * gx / 9) * 4
            let v = max(Int(base[o]), Int(base[o + 1]), Int(base[o + 2]))
            sum += (Int(base[o]) + Int(base[o + 1]) + Int(base[o + 2])) / 3; peak = max(peak, v); alpha += Int(base[o + 3]); count += 1
        } }
        return "\(size) mean \(sum / count) peak \(peak) alpha \(alpha / count)"
    }
}

/// Frame failures repeat for every frame, so only the first few reach the log.
enum GradeLog {
    private static let lock = NSLock()
    private static var count = 0

    static func failure(_ message: @autoclosure () -> String) {
        lock.lock(); count += 1; let mine = count; lock.unlock()
        if mine <= 5 { NSLog("AquaRestore: frame grading failed: \(message())") }
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

    private static func fillBlack(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock(); let mine = generation; lock.unlock()
        FrameProbe.request(request)
        queue.async {
            self.lock.lock(); let current = self.generation; self.lock.unlock()
            guard current == mine else { request.finishCancelledRequest(); return }
            guard let instruction = request.videoCompositionInstruction as? GradeInstruction else {
                GradeLog.failure("instruction is \(type(of: request.videoCompositionInstruction)), not GradeInstruction")
                request.finish(with: GradeError.metalUnavailable)
                return
            }
            guard let output = request.renderContext.newPixelBuffer() else {
                GradeLog.failure("render context gave no output buffer (\(request.renderContext.size))")
                request.finish(with: GradeError.textureFailed)
                return
            }
            // Before the video's first frame (action cameras often start a few frames after zero) AVFoundation supplies no
            // source frame. Answer with black: failing the request would stop the player asking for video at all.
            guard let source = request.sourceFrame(byTrackID: instruction.trackID) else {
                Self.fillBlack(output)
                request.finish(withComposedVideoFrame: output)
                return
            }
            guard let grader = MetalGrader.shared else {
                GradeLog.failure("Metal grader unavailable")
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
