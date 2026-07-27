// swift-tools-version: 5.9
import PackageDescription

// 纯逻辑核心层：模型 / 解码 / 展示格式化。
// 不依赖 UIKit / SwiftUI / WidgetKit，因此可在没有 Xcode 的环境用 `swift test` 验证，
// 同时被主 App 与 Widget Extension 两个 target 共享。
let package = Package(
    name: "FearGreedCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FearGreedCore", targets: ["FearGreedCore"]),
        .library(name: "FearGreedUI", targets: ["FearGreedUI"]),
    ],
    targets: [
        .target(name: "FearGreedCore"),
        // 数据层 + SwiftUI 视图 + 小组件视图，App 与 Widget 两个 target 共用。
        // 同时声明 macOS 平台，使其能在只有 Command Line Tools 的机器上编译验证。
        .target(name: "FearGreedUI", dependencies: ["FearGreedCore"]),
        .testTarget(
            name: "FearGreedCoreTests",
            dependencies: ["FearGreedCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FearGreedUITests",
            dependencies: ["FearGreedUI", "FearGreedCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
