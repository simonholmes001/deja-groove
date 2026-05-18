// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DejaGrooveApp",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "DejaGrooveApp", targets: ["DejaGrooveApp"])
    ],
    dependencies: [
        .package(path: "../DejaGrooveAuth")
    ],
    targets: [
        .target(
            name: "DejaGrooveApp",
            dependencies: [
                .product(name: "DejaGrooveAuth", package: "DejaGrooveAuth")
            ]
        ),
        .testTarget(
            name: "DejaGrooveAppTests",
            dependencies: ["DejaGrooveApp"]
        )
    ]
)
