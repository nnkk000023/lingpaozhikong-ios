// swift-tools-version: 5.10
// LingpaoCore：零跑 iOS 原生重制版跨平台核心层（模型、加密签名、网络协议、BLE 与车模数学管线）

import PackageDescription

let package = Package(
    name: "LingpaoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LingpaoCore",
            targets: ["LingpaoCore"]
        )
    ],
    targets: [
        .target(
            name: "LingpaoCore",
            path: "Sources/LingpaoCore"
        ),
        .testTarget(
            name: "LingpaoCoreTests",
            dependencies: ["LingpaoCore"],
            path: "Tests/LingpaoCoreTests"
        )
    ]
)
