import SwiftUI
import FearGreedCore

/// 半圆仪表盘：底色为恐慌→贪婪的渐变弧，实色弧与指针指向当前值。
///
/// 角度约定用 SwiftUI 的屏幕坐标系（y 向下）：0° 指向右，270° 指向正上方。
/// 弧从 165° 扫到 375°（即 15°），共 210°，两端略低于水平线。
public struct GaugeView: View {
    private let fraction: Double
    private let value: String
    private let label: String?
    private let tint: Color

    private static let arcStart: Double = 165
    private static let arcSweep: Double = 210

    public init(fraction: Double, value: String, label: String?, tint: Color) {
        self.fraction = min(max(fraction, 0), 1)
        self.value = value
        self.label = label
        self.tint = tint
    }

    public init(presentation: IndexPresentation, showsLabel: Bool = true) {
        self.init(
            fraction: presentation.gaugeFraction,
            value: presentation.formattedValue,
            label: showsLabel ? presentation.labelTextZH : nil,
            tint: SentimentPalette.color(for: presentation.index.label)
        )
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // 弧含描边后要正好填满画布：圆心取 0.76h，半径 0.704h 时
            // 弧顶 (cy - r - lw/2) 与弧两端 (cy + 0.26r + lw/2) 刚好贴边；
            // 画布过窄时改由宽度约束，宁可上方留白也不让弧溢出到下方文字。
            let radius = min(size.height * 0.704, size.width * 0.463)
            let center = CGPoint(x: size.width / 2, y: size.height * 0.76)
            let lineWidth = max(radius * 0.16, 4)

            ZStack {
                GaugeArc(center: center, radius: radius)
                    .stroke(
                        AngularGradient(
                            gradient: SentimentPalette.gaugeGradient,
                            center: UnitPoint(x: 0.5, y: center.y / max(size.height, 1)),
                            startAngle: .degrees(Self.arcStart),
                            endAngle: .degrees(Self.arcStart + Self.arcSweep)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .opacity(0.28)

                GaugeArc(center: center, radius: radius)
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                knob(center: center, radius: radius, size: lineWidth * 0.62)

                readout(center: center, radius: radius)
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { "\($0)，指数 \(value)" } ?? "指数 \(value)")
    }

    /// 用弧上的圆点标记当前值，而不是从圆心出发的指针 —— 指针会横穿中间的数字。
    @ViewBuilder
    private func knob(center: CGPoint, radius: CGFloat, size: CGFloat) -> some View {
        let radians = (Self.arcStart + Self.arcSweep * fraction) * .pi / 180
        Circle()
            .fill(.white)
            .overlay(Circle().fill(tint).padding(size * 0.28))
            .frame(width: size * 2, height: size * 2)
            .position(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            )
            .shadow(color: .black.opacity(0.18), radius: size * 0.3, y: size * 0.12)
    }

    @ViewBuilder
    private func readout(center: CGPoint, radius: CGFloat) -> some View {
        VStack(spacing: radius * 0.02) {
            Text(value)
                .font(.system(size: radius * 0.44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let label {
                Text(label)
                    .font(.system(size: radius * 0.17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: radius * 1.4)
        // 落在弧的内侧，与弧线保持间距。
        .position(x: center.x, y: center.y - radius * 0.34)
    }
}

struct GaugeArc: Shape {
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: center, radius: radius,
            startAngle: .degrees(165), endAngle: .degrees(375),
            clockwise: false
        )
        return path
    }
}

#Preview {
    HStack(spacing: 16) {
        GaugeView(fraction: 0.16, value: "16", label: "极度恐慌", tint: SentimentPalette.color(for: .extremeFear))
        GaugeView(fraction: 0.39, value: "39", label: "恐慌", tint: SentimentPalette.color(for: .fear))
        GaugeView(fraction: 0.82, value: "82", label: "极度贪婪", tint: SentimentPalette.color(for: .extremeGreed))
    }
    .padding()
    .frame(height: 140)
}
