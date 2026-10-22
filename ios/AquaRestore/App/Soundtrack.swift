import AVFoundation
import MediaToolbox

/// Volume, 0–200%, applied in the audio pipeline. Above 100% it clips instead of wrapping, and it can
/// change live while the player runs.
final class GainBox {
    var gain: Float
    init(_ gain: Float = 1) { self.gain = gain }
}

private final class TapContext {
    let box: GainBox
    var isFloat = true
    var bits: UInt32 = 32
    init(_ box: GainBox) { self.box = box }
}

enum GainTap {
    static func make(_ box: GainBox) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(TapContext(box)).toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.isFloat = format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
                context.bits = format.pointee.mBitsPerChannel
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let gain = context.box.gain
                if gain == 1 { return }
                for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                    guard let data = buffer.mData else { continue }
                    if context.isFloat && context.bits == 32 {
                        let samples = data.assumingMemoryBound(to: Float.self)
                        for i in 0..<Int(buffer.mDataByteSize) / 4 { samples[i] = Gain.apply(samples[i], gain) }
                    } else if !context.isFloat && context.bits == 16 {
                        let samples = data.assumingMemoryBound(to: Int16.self)
                        for i in 0..<Int(buffer.mDataByteSize) / 2 { samples[i] = Gain.apply(samples[i], gain) }
                    }
                }
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr else { return nil }
        return tap
    }

    static func parameters(_ track: AVAssetTrack, _ box: GainBox) -> AVMutableAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = make(box)
        return parameters
    }
}

enum Soundtrack {
    static func inspect(_ url: URL) async throws -> MusicTrack {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        let ms = Int64((duration.seconds * 1000).rounded())
        guard !tracks.isEmpty, duration.isNumeric, ms > 0 else { throw MediaProblem("noAudio") }
        return MusicTrack(url: url, name: url.lastPathComponent, durationMs: ms)
    }

    /// Loudness per slot (0–1, normalized to the loudest), decoded from the real audio for the music bar.
    static func envelope(_ track: MusicTrack, slots: Int = 120) async throws -> [Float] {
        let asset = AVURLAsset(url: track.url)
        guard let audio = try await asset.loadTracks(withMediaType: .audio).first else { throw MediaProblem("noAudio") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44100,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MediaProblem("noAudio") }
        var sums = [Double](repeating: 0, count: slots)
        var counts = [Int](repeating: 0, count: slots)
        let durationUs = Double(max(1, track.durationMs * 1000))
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let seconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let slot = min(max(Int(seconds * 1_000_000 * Double(slots) / durationUs), 0), slots - 1)
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length / 2 * 2, destination: $0.baseAddress!) }
            // Every 8th 16-bit sample is plenty for a visual envelope.
            var i = 0
            while i < data.count { sums[slot] += Double(abs(Int(data[i]))); counts[slot] += 1; i += 8 }
        }
        let levels = (0..<slots).map { counts[$0] == 0 ? Float(0) : Float(sums[$0] / Double(counts[$0])) }
        let loudest = levels.max().flatMap { $0 > 0 ? $0 : nil } ?? 1
        return levels.map { min(1, $0 / loudest) }
    }
}
