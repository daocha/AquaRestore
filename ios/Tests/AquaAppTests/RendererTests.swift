import XCTest
import Metal
@testable import AquaRestore

final class RendererTests: XCTestCase {
    func testRotationStoredWithoutItsOffsetStillLandsOnTheFrame() {
        let natural = CGSize(width: 640, height: 480)
        // A quarter turn with no translation puts the picture to the left of the frame; players correct for that.
        let turned = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        let frame = CGRect(origin: .zero, size: natural).applying(GradeInstruction.normalized(turned, natural))
        XCTAssertEqual(frame.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.width, 480, accuracy: 1e-9)
        XCTAssertEqual(frame.height, 640, accuracy: 1e-9)
    }

    func testTransformsThatAlreadyFitAreLeftAlone() {
        let natural = CGSize(width: 640, height: 480)
        let offset = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 480, ty: 0)
        XCTAssertEqual(GradeInstruction.normalized(offset, natural), offset)
        XCTAssertEqual(GradeInstruction.normalized(.identity, natural), .identity)
    }

    func testShaderMatchesRendererEntryPoints() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let library = try device.makeLibrary(source: GradeShader.source, options: nil)
        for name in ["grade", "linearize"] {
            let function = try XCTUnwrap(library.makeFunction(name: name))
            _ = try device.makeComputePipelineState(function: function)
        }
        XCTAssertNotNil(MetalGrader.shared)
    }
}
