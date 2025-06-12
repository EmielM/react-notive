// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReactNotive",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ReactNotive",
            targets: ["ReactNotive"]
        )
    ],
    targets: [
        .target(
            name: "ReactNotive",
            resources: [
                // Add any resource folders like Assets, JSON, etc. here
                // .process("Assets")
            ]
        ),
        .testTarget(
            name: "ReactNotiveTests",
            dependencies: ["ReactNotive"]
        )
    ]
)