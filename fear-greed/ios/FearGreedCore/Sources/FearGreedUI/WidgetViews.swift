import SwiftUI
import WidgetKit
import FearGreedCore

/// Small：单市场仪表盘。
public struct WidgetSmallView: View {
    private let entry: IndexEntry

    public init(entry: IndexEntry) {
        self.entry = entry
    }

    private var presentation: IndexPresentation {
        entry.snapshot.presentation(for: entry.market)
    }

    public var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(entry.market.displayNameZH)
                    .font(.caption.weight(.semibold))
                Spacer()
                if entry.isFromCache || entry.snapshot.index(for: entry.market).stale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            GaugeView(presentation: presentation)
            deltaLine
        }
        .opacity(entry.isPlaceholder ? 0.35 : 1)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    @ViewBuilder
    private var deltaLine: some View {
        if let delta = presentation.deltaFromPrevCloseText {
            Text("较昨收 \(delta)")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(SentimentPalette.deltaColor(presentation.index.changeFromPrevClose))
        } else {
            Text(" ").font(.system(size: 10))
        }
    }
}

/// Medium：双市场并排 + 各自 7 日趋势。
public struct WidgetMediumView: View {
    private let entry: IndexEntry

    public init(entry: IndexEntry) {
        self.entry = entry
    }

    public var body: some View {
        HStack(spacing: 14) {
            ForEach(Market.allCases, id: \.self) { market in
                column(for: market)
            }
        }
        .opacity(entry.isPlaceholder ? 0.35 : 1)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private func column(for market: Market) -> some View {
        let presentation = entry.snapshot.presentation(for: market)
        let tint = SentimentPalette.color(for: presentation.index.label)
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(market.displayNameZH)
                    .font(.caption2.weight(.semibold))
                if entry.isFromCache || presentation.index.stale {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 8))
                }
            }
            .foregroundStyle(.secondary)

            GaugeView(presentation: presentation)
            SparklineView(points: entry.snapshot.recentHistory(for: market, days: 7), tint: tint)
                .frame(height: 18)
            if let delta = presentation.deltaFromPrevCloseText {
                Text("较昨收 \(delta)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(SentimentPalette.deltaColor(presentation.index.changeFromPrevClose))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 由组件尺寸分发到对应视图，并统一加上 iOS 17 要求的容器背景。
public struct FearGreedWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    private let entry: IndexEntry

    public init(entry: IndexEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            switch family {
            case .systemMedium: WidgetMediumView(entry: entry)
            default: WidgetSmallView(entry: entry)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

#Preview("Small", as: .systemSmall) {
    CNIndexWidget()
} timeline: {
    IndexEntry(date: .now, snapshot: PreviewData.snapshot, market: .cn, isPlaceholder: false)
}

#Preview("Medium", as: .systemMedium) {
    DualMarketWidget()
} timeline: {
    IndexEntry(date: .now, snapshot: PreviewData.snapshot, market: .cn, isPlaceholder: false)
}
