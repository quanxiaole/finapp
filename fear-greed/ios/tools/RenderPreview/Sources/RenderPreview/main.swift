import AppKit
import SwiftUI
import FearGreedCore
import FearGreedUI

// 用法：RenderPreview <index.json 路径> <输出目录>
let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandler.fail("用法: RenderPreview <index.json> <输出目录>")
}

enum FileHandler {
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

let jsonURL = URL(fileURLWithPath: args[1])
let outputDir = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

guard let data = try? Data(contentsOf: jsonURL),
      let snapshot = try? SnapshotDecoder.decode(data) else {
    FileHandler.fail("无法读取或解析 \(jsonURL.path)")
}

@MainActor
func render(_ view: some View, size: CGSize, to name: String) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandler.fail("渲染失败: \(name)")
    }
    let url = outputDir.appendingPathComponent(name)
    do {
        try png.write(to: url)
        print("✅ \(name)  \(Int(size.width))×\(Int(size.height))  \(png.count) bytes")
    } catch {
        FileHandler.fail("写入失败 \(url.path): \(error)")
    }
}

/// 主 App 卡片区（DashboardView 的内容部分，去掉需要网络的 NavigationStack 外壳）。
struct DashboardPreview: View {
    let snapshot: IndexSnapshot

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Market.allCases, id: \.self) { market in
                MarketCardView(
                    presentation: snapshot.presentation(for: market),
                    history: snapshot.recentHistory(for: market, days: 30)
                )
            }
            Text("更新于 \(snapshot.freshnessText())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(white: 0.97))
    }
}

/// 管道降级时的样子：数值为 null + stale，用来确认不会白屏或塌陷。
let degraded = IndexSnapshot(
    schemaVersion: 1, updatedAt: snapshot.updatedAt,
    us: MarketIndex(value: nil, label: nil, stale: true),
    cn: MarketIndex(value: nil, label: nil, coverage: 0.28, asOf: "2026-07-22", stale: true)
)

MainActor.assumeIsolated {
    render(DashboardPreview(snapshot: snapshot), size: CGSize(width: 393, height: 760),
           to: "dashboard.png")

    render(DashboardPreview(snapshot: degraded), size: CGSize(width: 393, height: 560),
           to: "dashboard_degraded.png")

    render(
        WidgetSmallView(entry: IndexEntry(date: .now, snapshot: PreviewData.snapshot, market: .us, isPlaceholder: true))
            .padding(12)
            .background(Color(white: 1.0)),
        size: CGSize(width: 170, height: 170), to: "widget_placeholder.png"
    )

    render(
        WidgetSmallView(entry: IndexEntry(date: .now, snapshot: snapshot, market: .cn, isPlaceholder: false))
            .padding(12)
            .background(Color(white: 1.0)),
        size: CGSize(width: 170, height: 170), to: "widget_small.png"
    )

    render(
        WidgetMediumView(entry: IndexEntry(date: .now, snapshot: snapshot, market: .cn, isPlaceholder: false))
            .padding(12)
            .background(Color(white: 1.0)),
        size: CGSize(width: 364, height: 170), to: "widget_medium.png"
    )
}
