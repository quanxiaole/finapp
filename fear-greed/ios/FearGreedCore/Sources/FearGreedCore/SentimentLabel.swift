import Foundation

/// 情绪等级。阈值与数据管道 `pipeline/index_utils.py` 的 `label_for` 保持一致。
public enum SentimentLabel: String, Codable, Sendable, CaseIterable {
    case extremeFear = "extreme_fear"
    case fear
    case neutral
    case greed
    case extremeGreed = "extreme_greed"
    /// 管道新增等级或字段异常时的兜底，避免解码整体失败。
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SentimentLabel(rawValue: raw) ?? .unknown
    }

    /// 由数值推导等级；用于管道未给 label 时的本地兜底。
    public init(value: Double) {
        switch value {
        case ..<25: self = .extremeFear
        case ..<45: self = .fear
        case ..<55: self = .neutral
        case ..<75: self = .greed
        default: self = .extremeGreed
        }
    }

    public var displayNameZH: String {
        switch self {
        case .extremeFear: return "极度恐慌"
        case .fear: return "恐慌"
        case .neutral: return "中性"
        case .greed: return "贪婪"
        case .extremeGreed: return "极度贪婪"
        case .unknown: return "未知"
        }
    }

    public var displayNameEN: String {
        switch self {
        case .extremeFear: return "Extreme Fear"
        case .fear: return "Fear"
        case .neutral: return "Neutral"
        case .greed: return "Greed"
        case .extremeGreed: return "Extreme Greed"
        case .unknown: return "Unknown"
        }
    }

    /// -1（极度恐慌）→ +1（极度贪婪），供 UI 映射配色。
    public var polarity: Double {
        switch self {
        case .extremeFear: return -1.0
        case .fear: return -0.5
        case .neutral: return 0.0
        case .greed: return 0.5
        case .extremeGreed: return 1.0
        case .unknown: return 0.0
        }
    }
}
