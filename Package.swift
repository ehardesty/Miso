// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Miso",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Miso", targets: ["Miso"])],
    targets: [
        .target(name: "MisoCore"),
        .target(
            name: "MisoPlatform",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),
        .executableTarget(
            name: "Miso",
            dependencies: ["MisoCore", "MisoPlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "MisoCoreTests", dependencies: ["MisoCore"])
    ]
)
