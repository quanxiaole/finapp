import Foundation
import FearGreedCore

/// 占位与预览用的静态数据。小组件在拿到真实数据前必须先渲染出骨架，
/// 用真实量级的数字可以避免系统截图时出现明显的空白态。
public enum PreviewData {
    public static let snapshot: IndexSnapshot = {
        let us = MarketIndex(value: 39.43, label: .fear, prevClose: 39.6, weekAgo: 37.23)
        let cn = MarketIndex(
            value: 16.18, label: .extremeFear, prevClose: 23.82, weekAgo: 19.16,
            coverage: 0.65, asOf: "2026-07-24"
        )
        return IndexSnapshot(
            schemaVersion: 1, updatedAt: Date(timeIntervalSince1970: 1_785_000_000),
            us: us, cn: cn,
            usHistory: history(from: 45, drift: -0.2),
            cnHistory: history(from: 30, drift: -0.5)
        )
    }()

    private static func history(from start: Double, drift: Double) -> [HistoryPoint] {
        (0..<30).map { i in
            let value = min(max(start + drift * Double(i) + Double((i * 7) % 5) - 2, 2), 98)
            return HistoryPoint(date: String(format: "2026-06-%02d", i % 28 + 1), value: value)
        }
    }
}
