import SwiftUI
import FearGreedCore

/// 单市场卡片：仪表盘 + 昨收/上周对比 + 7 日趋势 + 可信度提示。
public struct MarketCardView: View {
    private let presentation: IndexPresentation
    private let history: [HistoryPoint]

    public init(presentation: IndexPresentation, history: [HistoryPoint]) {
        self.presentation = presentation
        self.history = history
    }

    private var tint: Color { SentimentPalette.color(for: presentation.index.label) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            GaugeView(presentation: presentation)
                .frame(maxWidth: .infinity)
            deltaRow
            if history.count > 1 {
                SparklineView(points: history, tint: tint)
                    .frame(height: 44)
            }
            if let advisory = presentation.advisoryZH {
                advisoryRow(advisory)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(presentation.market.displayNameZH)
                .font(.headline)
            Spacer()
            Text(presentation.market.sourceNoteZH)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var deltaRow: some View {
        HStack(spacing: 20) {
            deltaItem(title: "较昨收", text: presentation.deltaFromPrevCloseText,
                      delta: presentation.index.changeFromPrevClose)
            deltaItem(title: "较上周", text: presentation.deltaFromWeekAgoText,
                      delta: presentation.index.changeFromWeekAgo)
            Spacer()
        }
    }

    private func deltaItem(title: String, text: String?, delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text ?? "--")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SentimentPalette.deltaColor(delta))
        }
        .accessibilityElement(children: .combine)
    }

    private func advisoryRow(_ advisory: String) -> some View {
        Label(advisory, systemImage: presentation.index.stale ? "exclamationmark.triangle" : "info.circle")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

#Preview {
    MarketCardView(
        presentation: IndexPresentation(
            market: .cn,
            index: MarketIndex(value: 16.18, label: .extremeFear, prevClose: 23.82,
                               weekAgo: 19.16, coverage: 0.65, asOf: "2026-07-24")
        ),
        history: (0..<30).map { HistoryPoint(date: "2026-06-\($0)", value: Double(35 - $0 / 2)) }
    )
    .padding()
    .frame(width: 360)
}
