// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DejaGrooveApp",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "DejaGrooveApp", targets: ["DejaGrooveApp"])
    ],
    targets: [
        .target(
            name: "DejaGrooveApp"
        ),
        .testTarget(
            name: "DejaGrooveAppTests",
            dependencies: ["DejaGrooveApp"]
        )
    ]
)
