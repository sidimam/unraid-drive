// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UnraidGatewayKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "UnraidGatewayKit", targets: ["UnraidGatewayKit"]),
    ],
    targets: [
        .target(name: "UnraidGatewayKit", path: "Sources/UnraidGatewayKit"),
        .testTarget(name: "UnraidGatewayKitTests", dependencies: ["UnraidGatewayKit"], path: "Tests/UnraidGatewayKitTests"),
    ]
)
