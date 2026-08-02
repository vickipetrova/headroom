// swift-tools-version: 6.0
import PackageDescription

// No `dependencies:` array, and there never will be one — see hard rule 2 in CLAUDE.md. The test
// target uses swift-testing, which ships with the toolchain rather than as a package. That choice is
// load-bearing: the Command Line Tools include Testing.framework but *not* XCTest.framework, and this
// project's contract is that CLT alone is enough to build and test.
let package = Package(
    name: "Headroom",
    // Required, not decorative. SwiftPM rebuilds the target triple's version component from this on
    // Darwin, so the build machine's OS can never leak into the binary. Omit it and the default is
    // macOS 10.13, which would contradict LSMinimumSystemVersion in build.sh's Info.plist.
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HeadroomCore"),
        .executableTarget(name: "Headroom", dependencies: ["HeadroomCore"]),
        .testTarget(name: "HeadroomCoreTests", dependencies: ["HeadroomCore"]),
    ],
    // Matches what `swiftc` does by default, which is what this project compiled with before SPM.
    // Swift 6 mode rejects the static mutable state in Notifier and the cached formatters; moving to
    // .v6 means annotating those, not just flipping this line.
    swiftLanguageModes: [.v5]
)
