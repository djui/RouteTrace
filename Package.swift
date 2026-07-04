// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RouteTraceApple",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "RouteTraceShared", targets: ["RouteTraceShared"])
    ],
    targets: [
        .target(
            name: "RouteTraceShared",
            path: "RouteTrace/Shared/Sources/RouteTraceShared"
        ),
        .testTarget(
            name: "RouteTraceTests",
            dependencies: ["RouteTraceShared"],
            path: "RouteTrace/Tests",
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
