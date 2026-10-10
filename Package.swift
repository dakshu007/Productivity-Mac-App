// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowBreak",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlowBreak", targets: ["FlowBreak"]),
        .library(name: "FlowBreakCore", targets: ["FlowBreakCore"]),
    ],
    targets: [
        // Platform-independent logic: timer state machine, persistence, statistics,
        // reminder planning, usage recording. Foundation only, fully unit tested.
        .target(name: "FlowBreakCore", path: "Sources/FlowBreakCore"),
        // The native macOS app: AppKit menu-bar shell + SwiftUI views.
        .executableTarget(
            name: "FlowBreak",
            dependencies: ["FlowBreakCore"],
            path: "Sources/FlowBreak"
        ),
        .testTarget(
            name: "FlowBreakCoreTests",
            dependencies: ["FlowBreakCore"],
            path: "Tests/FlowBreakCoreTests"
        ),
    ]
)
