// swift-tools-version:5.9
import PackageDescription

// Tools-version 5.9 keeps Swift 5 language mode (lenient concurrency) even on the
// Swift 6.2 toolchain — this avoids fighting strict-concurrency errors around the
// PhotoKit completion handlers that hop back to the main actor.
let package = Package(
    name: "PhotoFilter",
    platforms: [
        .macOS(.v14) // .v14 required for SwiftUI .onKeyPress / .defaultSize and modern PhotoKit
    ],
    targets: [
        .executableTarget(
            name: "PhotoFilter",
            path: "Sources/PhotoFilter"
        )
    ]
)
