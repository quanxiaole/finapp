import SwiftUI
import FearGreedCore

/// 情绪配色。恐慌偏红、贪婪偏绿，中性用中调灰蓝以免误读为「安全」。
public enum SentimentPalette {

    public static func color(for label: SentimentLabel?) -> Color {
        switch label {
        case .extremeFear: return Color(red: 0.85, green: 0.20, blue: 0.24)
        case .fear: return Color(red: 0.92, green: 0.49, blue: 0.20)
        case .neutral: return Color(red: 0.55, green: 0.58, blue: 0.64)
        case .greed: return Color(red: 0.35, green: 0.70, blue: 0.40)
        case .extremeGreed: return Color(red: 0.13, green: 0.60, blue: 0.31)
        case .unknown, .none: return Color.secondary
        }
    }

    public static func color(forValue value: Double?) -> Color {
        guard let value else { return .secondary }
        return color(for: SentimentLabel(value: value))
    }

    /// 仪表盘底色：从极度恐慌到极度贪婪的连续渐变。
    public static var gaugeGradient: Gradient {
        Gradient(colors: [
            color(for: .extremeFear), color(for: .fear), color(for: .neutral),
            color(for: .greed), color(for: .extremeGreed),
        ])
    }

    /// 变化量配色：涨向贪婪为绿、跌向恐慌为红。
    public static func deltaColor(_ delta: Double?) -> Color {
        guard let delta, delta != 0 else { return .secondary }
        return delta > 0 ? color(for: .greed) : color(for: .fear)
    }
}
