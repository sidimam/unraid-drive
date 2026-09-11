// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UnraidGatewayKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "UnraidGatewayKit", targets: ["UnraidGatewayKit"]),
    ],
    targets: [
        .target(name: "UnraidGatewayKit", path: "Sources/UnraidGatewayKit", resources: [.process("Resources")]),
        .testTarget(name: "UnraidGatewayKitTests", dependencies: ["UnraidGatewayKit"], path: "Tests/UnraidGatewayKitTests"),
    ]
)
