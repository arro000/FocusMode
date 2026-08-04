// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusMode",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FocusMode", targets: ["FocusMode"])
    ],
    targets: [
        .executableTarget(
            name: "FocusMode",
            path: "Sources/FocusMode",
            resources: [.process("Resources")]
        )
    ]
)
