import Foundation

/// 市场标识。
public enum Market: String, Codable, Sendable, CaseIterable {
    case us
    case cn

    public var displayNameZH: String {
        switch self {
        case .us: return "美股"
        case .cn: return "A股"
        }
    }

    public var displayNameEN: String {
        switch self {
        case .us: return "US"
        case .cn: return "China A"
        }
    }

    /// 指数来源说明，用于「方法论透明」展示。
    public var sourceNoteZH: String {
        switch self {
        case .us: return "CNN Fear & Greed"
        case .cn: return "自研七因子指数"
        }
    }
}

/// 单个市场的指数快照。
///
/// 管道在降级时会把 `value`/`label`/`prevClose`/`weekAgo` 写成 null
/// （见 `pipeline/main.py` 的 stale 兜底与历史不足分支），故全部为可选。
public struct MarketIndex: Codable, Sendable, Equatable {
    public let value: Double?
    public let label: SentimentLabel?
    public let prevClose: Double?
    public let weekAgo: Double?
    /// 仅 A股：参与合成的因子权重覆盖率（1.0 为全部因子可用）。
    public let coverage: Double?
    /// 仅 A股：指数对应的交易日（因子有 T+1 滞后，可能早于 updatedAt）。
    public let asOf: String?
    public let stale: Bool

    enum CodingKeys: String, CodingKey {
        case value, label, coverage, stale
        case prevClose = "prev_close"
        case weekAgo = "week_ago"
        case asOf = "as_of"
    }

    public init(
        value: Double?, label: SentimentLabel?, prevClose: Double? = nil,
        weekAgo: Double? = nil, coverage: Double? = nil, asOf: String? = nil,
        stale: Bool = false
    ) {
        self.value = value
        self.label = label
        self.prevClose = prevClose
        self.weekAgo = weekAgo
        self.coverage = coverage
        self.asOf = asOf
        self.stale = stale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(Double.self, forKey: .value)
        prevClose = try c.decodeIfPresent(Double.self, forKey: .prevClose)
        weekAgo = try c.decodeIfPresent(Double.self, forKey: .weekAgo)
        coverage = try c.decodeIfPresent(Double.self, forKey: .coverage)
        asOf = try c.decodeIfPresent(String.self, forKey: .asOf)
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale) ?? false

        // label 缺失时按数值兜底推导，保证有值就有等级可展示。
        if let decoded = try c.decodeIfPresent(SentimentLabel.self, forKey: .label) {
            label = decoded
        } else if let value {
            label = SentimentLabel(value: value)
        } else {
            label = nil
        }
    }

    /// 是否有可展示的数值。
    public var hasValue: Bool { value != nil }

    /// 相对昨收的变化量。
    public var changeFromPrevClose: Double? {
        guard let value, let prevClose else { return nil }
        return value - prevClose
    }

    /// 相对一周前的变化量。
    public var changeFromWeekAgo: Double? {
        guard let value, let weekAgo else { return nil }
        return value - weekAgo
    }

    /// 因子覆盖不全（A股 go-forward 因子尚在累积）时为 true。
    public var isLowConfidence: Bool {
        guard let coverage else { return false }
        return coverage < 0.999
    }
}

/// 历史序列中的一个点。
public struct HistoryPoint: Codable, Sendable, Equatable {
    public let date: String
    public let value: Double

    public init(date: String, value: Double) {
        self.date = date
        self.value = value
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public var day: Date? { Self.dayFormatter.date(from: date) }
}
