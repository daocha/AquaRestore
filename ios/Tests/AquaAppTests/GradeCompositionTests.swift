import AVFoundation
import XCTest
@testable import AquaRestore

final class GradeCompositionTests: XCTestCase {
    func testCompositionPreservesTimingAndColorMetadata() throws {
        let asset = AVMutableComposition()
        let track = try XCTUnwrap(asset.addMutableTrack(withMediaType: .video, preferredTrackID: 1))
        let size = CGSize(width: 1920, height: 1080)
        let duration = CMTime(value: 10, timescale: 1)
        let frameDuration = CMTime(value: 1, timescale: 30)
        for mode in [HdrMode.sdr, .hlg, .pq] {
            let composition = GradeComposition.make(track: track, trackID: track.trackID, duration: duration,
                state: GradeState(), hdr: mode, transform: .identity, naturalSize: size,
                renderSize: size, frameDuration: frameDuration)
            XCTAssertEqual(composition.renderSize, size)
            XCTAssertEqual(composition.frameDuration, frameDuration)
            XCTAssertEqual(composition.sourceTrackIDForFrameTiming, track.trackID)
            XCTAssertEqual(composition.instructions.count, 1)
            let instruction = try XCTUnwrap(composition.instructions.first as? GradeInstruction)
            XCTAssertEqual(instruction.timeRange.duration, duration)
            XCTAssertEqual((instruction.requiredSourceTrackIDs?.first as? NSNumber)?.int32Value, track.trackID)
            let expectedClass: AVVideoCompositing.Type = mode == .sdr ? GradeCompositor.self : HdrGradeCompositor.self
            let compositor = try XCTUnwrap(composition.customVideoCompositorClass)
            XCTAssertEqual(ObjectIdentifier(compositor), ObjectIdentifier(expectedClass))
            XCTAssertEqual(composition.colorPrimaries,
                mode == .sdr ? AVVideoColorPrimaries_ITU_R_709_2 : AVVideoColorPrimaries_ITU_R_2020)
            let transfer = mode == .sdr ? AVVideoTransferFunction_ITU_R_709_2 :
                (mode == .hlg ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_SMPTE_ST_2084_PQ)
            XCTAssertEqual(composition.colorTransferFunction, transfer)
            XCTAssertEqual(composition.colorYCbCrMatrix,
                mode == .sdr ? AVVideoYCbCrMatrix_ITU_R_709_2 : AVVideoYCbCrMatrix_ITU_R_2020)
        }
    }
}
