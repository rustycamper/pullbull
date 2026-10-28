// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PullBullKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PullBullKit", targets: ["PullBullKit"])
    ],
    targets: [
        .target(name: "PullBullKit"),
        .testTarget(
            name: "PullBullKitTests",
            dependencies: ["PullBullKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
