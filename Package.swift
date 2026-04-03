// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macos",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "MultiCodex", targets: ["MultiCodex"]),
    ],
    targets: [
        .executableTarget(
            name: "MultiCodex",
            path: "Sources/MultiCodex",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "MultiCodexTests",
            dependencies: ["MultiCodex"],
            path: "Tests/MultiCodexTests"
        ),
    ]
)
