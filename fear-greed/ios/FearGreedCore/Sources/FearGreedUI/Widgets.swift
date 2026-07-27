import SwiftUI
import WidgetKit
import FearGreedCore

/// 三个静态组件而非一个可配置组件：MVP 阶段省掉 AppIntent 配置界面，
/// 用户直接在组件库里挑「A股 / 美股 / 双市场」，少一层交互。
public struct CNIndexWidget: Widget {
    public static let kind = "CNIndexWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: IndexTimelineProvider(market: .cn)) { entry in
            FearGreedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("A股 恐慌指数")
        .description("自研七因子情绪指数，0 极度恐慌 / 100 极度贪婪。")
        .supportedFamilies([.systemSmall])
    }
}

public struct USIndexWidget: Widget {
    public static let kind = "USIndexWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: IndexTimelineProvider(market: .us)) { entry in
            FearGreedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("美股 恐慌指数")
        .description("CNN Fear & Greed 指数。")
        .supportedFamilies([.systemSmall])
    }
}

public struct DualMarketWidget: Widget {
    public static let kind = "DualMarketWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: IndexTimelineProvider(market: .cn)) { entry in
            FearGreedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("双市场 恐慌指数")
        .description("A股与美股并排，含 7 日趋势。")
        .supportedFamilies([.systemMedium])
    }
}
