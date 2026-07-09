// swift-tools-version:6.0
// Development harness only.
//
// The shipping product is DriveVerse.xcodeproj (generated from project.yml via
// XcodeGen). This package exists so the platform-independent core logic and its
// test suite can be built and run with `swift test` on macOS — including on a
// machine that has only the Command Line Tools (see scripts/test.sh).
// iOS-only code (MediaPlayer, ActivityKit, AVAudioSession, UIKit) is fenced
// with #if os(iOS) / #if canImport(...) and compiles away here.
import PackageDescription

let package = Package(
    name: "DriveVerseCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .target(
            name: "DriveVerse",
            path: "DriveVerse",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DriveVerseTests",
            dependencies: ["DriveVerse"],
            path: "DriveVerseTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
