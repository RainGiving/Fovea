// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Fovea",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FoveaCore", targets: ["FoveaCore"]),
        .executable(name: "Fovea", targets: ["FoveaApp"])
    ],
    targets: [
        .target(
            name: "FoveaCore",
            path: "Sources/FoveaCore"
        ),
        .executableTarget(
            name: "FoveaApp",
            dependencies: ["FoveaCore"],
            path: "Sources/FoveaApp",
            exclude: [
                "Resources/Fovea.icns",
                "Resources/Info.plist"
            ],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ]
        ),
        .testTarget(
            name: "FoveaCoreTests",
            dependencies: ["FoveaCore"],
            path: "Tests/FoveaCoreTests"
        ),
        .testTarget(
            name: "FoveaAppTests",
            dependencies: ["FoveaApp", "FoveaCore"],
            path: "Tests/FoveaAppTests"
        )
    ]
)
