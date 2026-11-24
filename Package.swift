// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Chibiori",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "ChibioriCore",
            path: "Sources/ChibioriCore"
        ),
        .executableTarget(
            name: "Chibiori",
            dependencies: ["ChibioriCore"],
            path: "Sources/Chibiori"
        ),
        .testTarget(
            name: "ChibioriTests",
            dependencies: ["ChibioriCore"],
            path: "Tests/ChibioriTests"
        )
    ]
)
