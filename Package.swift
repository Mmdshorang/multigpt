// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macos",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "MultiCodex", targets: ["MultiCodexMenu"]),
    ],
    targets: [
        .executableTarget(
            name: "MultiCodexMenu",
            path: "Sources/MultiCodexMenu",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
