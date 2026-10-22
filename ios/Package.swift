// swift-tools-version:5.9
import PackageDescription

// The platform-independent logic (grading, recommendations, export sizing, music windows) lives in
// AquaRestore/Core. The app target compiles the same files, and this package lets them be tested with `swift test`.
let package = Package(
    name: "AquaCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    targets: [
        .target(name: "AquaCore", path: "AquaRestore/Core"),
        .testTarget(name: "AquaCoreTests", dependencies: ["AquaCore"], path: "Tests/AquaCoreTests"),
    ]
)
