// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RightCmd",
    platforms: [
        // The app targets macOS 26 (Tahoe). The core library has no platform
        // dependencies and compiles anywhere Foundation is available.
        .macOS("26.0")
    ],
    products: [
        .executable(name: "RightCmd", targets: ["RightCmd"]),
        .library(name: "RightCmdCore", targets: ["RightCmdCore"]),
        .library(name: "SpaceSwitchKit", targets: ["SpaceSwitchKit"]),
    ],
    targets: [
        // Pure logic: matching, the hold-and-type state machine, key
        // classification, settings. No AppKit, no CoreGraphics. Fully unit tested.
        .target(
            name: "RightCmdCore",
            path: "Sources/RightCmdCore"
        ),
        // C: locate a window's Space via private SkyLight calls (resolved at runtime) and
        // jump there instantly with a synthetic Dock swipe. Adapted from
        // InstantSpaceSwitcher (MIT); see Sources/SpaceSwitchKit/LICENSE-InstantSpaceSwitcher.
        .target(
            name: "SpaceSwitchKit",
            path: "Sources/SpaceSwitchKit",
            exclude: ["LICENSE-InstantSpaceSwitcher"],
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
        // Thin AppKit shell: event tap, keyboard layout translation, app
        // activation, overlay panel, status menu, settings window.
        .executableTarget(
            name: "RightCmd",
            dependencies: ["RightCmdCore", "SpaceSwitchKit"],
            path: "Sources/RightCmd"
        ),
        .testTarget(
            name: "RightCmdCoreTests",
            dependencies: ["RightCmdCore"],
            path: "Tests/RightCmdCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
