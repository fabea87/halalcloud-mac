// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HalalCloud",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HalalCloud", targets: ["HalalCloud"])
    ],
    targets: [
        .target(
            name: "HalalCloudCore",
            path: "Sources/HalalCloudCore"
        ),
        .executableTarget(
            name: "HalalCloud",
            dependencies: ["HalalCloudCore"],
            path: "Sources/HalalCloud"
        ),
        .testTarget(
            name: "HalalCloudCoreTests",
            dependencies: ["HalalCloudCore"],
            path: "Tests/HalalCloudCoreTests"
        )
    ]
)
