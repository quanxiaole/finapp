// swift-tools-version: 5.9
import PackageDescription

// 开发期工具：把 FearGreedUI 的视图离屏渲染成 PNG。
// 目的是在没有 Xcode / 模拟器的机器上也能对 UI 做可视化验收。
// 独立成包，避免 AppKit 依赖污染要被 iOS target 引用的 FearGreedCore 包。
let package = Package(
    name: "RenderPreview",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../FearGreedCore")],
    targets: [
        .executableTarget(
            name: "RenderPreview",
            dependencies: [
                .product(name: "FearGreedUI", package: "FearGreedCore"),
                .product(name: "FearGreedCore", package: "FearGreedCore"),
            ]
        )
    ]
)
