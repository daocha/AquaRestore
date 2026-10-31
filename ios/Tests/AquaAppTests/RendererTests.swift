import XCTest
import Metal
@testable import AquaRestore

final class RendererTests: XCTestCase {
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
