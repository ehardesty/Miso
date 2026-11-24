// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Miso",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Miso", targets: ["Miso"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "MisoCore"),
        .target(
            name: "MisoPlatform",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),
        .executableTarget(
            name: "Miso",
            dependencies: ["MisoCore", "MisoPlatform", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MisoCoreTests", dependencies: ["MisoCore"]),
        .testTarget(name: "MisoTests", dependencies: ["Miso", "MisoCore"])
    ]
)
