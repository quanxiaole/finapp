import Foundation

/// 展示层格式化。刻意不依赖 SwiftUI —— 只产出语义化文案与数值，
/// 由 App / Widget 各自决定配色与排版，这样核心层可在无 Xcode 环境测试。
public struct IndexPresentation: Sendable, Equatable {
    public let market: Market
    public let index: MarketIndex

    public init(market: Market, index: MarketIndex) {
        self.market = market
        self.index = index
    }

    private static let placeholder = "--"

    /// 主展示数值，取整（与 CNN 展示风格一致）。
    public var formattedValue: String {
        guard let value = index.value else { return Self.placeholder }
        return String(Int(value.rounded()))
    }

    public var labelTextZH: String {
        index.label?.displayNameZH ?? Self.placeholder
    }

    public var labelTextEN: String {
        index.label?.displayNameEN ?? Self.placeholder
    }

    /// 仪表盘指针位置，0...1。
    public var gaugeFraction: Double {
        guard let value = index.value else { return 0 }
        return min(max(value / 100.0, 0), 1)
    }

    public var deltaFromPrevCloseText: String? {
        Self.signedText(index.changeFromPrevClose)
    }

    public var deltaFromWeekAgoText: String? {
        Self.signedText(index.changeFromWeekAgo)
    }

    private static func signedText(_ delta: Double?) -> String? {
        guard let delta else { return nil }
        let rounded = (delta * 10).rounded() / 10
        if rounded == 0 { return "0" }
        return String(format: "%+.1f", rounded)
    }

    /// 数据可信度提示：陈旧、因子未满、指数交易日滞后。
    public var advisoryZH: String? {
        var notes: [String] = []
        if index.stale { notes.append("数据未更新") }
        if index.isLowConfidence, let coverage = index.coverage {
            notes.append("因子覆盖 \(Int((coverage * 100).rounded()))%")
        }
        if market == .cn, let asOf = index.asOf {
            notes.append("截至 \(asOf)")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }
}

extension IndexSnapshot {
    public func presentation(for market: Market) -> IndexPresentation {
        IndexPresentation(market: market, index: index(for: market))
    }

    /// "刚刚更新" / "12 分钟前" 之类的相对时间。
    public func freshnessText(now: Date = Date(), locale: Locale = Locale(identifier: "zh_CN")) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: updatedAt, relativeTo: now)
    }

    /// 数据是否超出预期新鲜度（默认 3 小时），用于提示而非阻断展示。
    public func isOutdated(now: Date = Date(), tolerance: TimeInterval = 3 * 3600) -> Bool {
        now.timeIntervalSince(updatedAt) > tolerance
    }
}
