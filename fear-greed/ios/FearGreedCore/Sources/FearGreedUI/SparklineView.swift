import SwiftUI
import FearGreedCore

/// 迷你趋势线。指数天然落在 0–100，故用固定量程，跨市场可直接横向比较。
public struct SparklineView: View {
    private let points: [HistoryPoint]
    private let tint: Color

    public init(points: [HistoryPoint], tint: Color) {
        self.points = points
        self.tint = tint
    }

    /// 纵轴量程。固定 0–100 时，指数常年在窄区间内波动会被压成一条直线，
    /// 故按数据范围自适应并留出边距；50 分中轴只在落入量程内时才画。
    private var range: (lo: Double, hi: Double) {
        let values = points.map { min(max($0.value, 0), 100) }
        guard let min = values.min(), let max = values.max() else { return (0, 100) }
        let padding = Swift.max((max - min) * 0.25, 4)
        return (Swift.max(min - padding, 0), Swift.min(max + padding, 100))
    }

    public var body: some View {
        GeometryReader { geo in
            let path = linePath(in: geo.size)
            let bounds = range
            ZStack {
                if bounds.lo < 50, bounds.hi > 50 {
                    Path { p in
                        let y = geo.size.height * (1 - (50 - bounds.lo) / (bounds.hi - bounds.lo))
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                closedPath(from: path, in: geo.size)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                path.stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let stepX = size.width / CGFloat(points.count - 1)
        let bounds = range
        let span = max(bounds.hi - bounds.lo, 0.001)
        for (i, point) in points.enumerated() {
            let clamped = min(max(point.value, 0), 100)
            let y = size.height * (1 - (clamped - bounds.lo) / span)
            let p = CGPoint(x: CGFloat(i) * stepX, y: y)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        return path
    }

    private func closedPath(from line: Path, in size: CGSize) -> Path {
        guard !line.isEmpty, let last = line.currentPoint else { return Path() }
        var filled = line
        filled.addLine(to: CGPoint(x: last.x, y: size.height))
        filled.addLine(to: CGPoint(x: 0, y: size.height))
        filled.closeSubpath()
        return filled
    }
}

#Preview {
    SparklineView(
        points: (0..<30).map { HistoryPoint(date: "2026-07-\($0)", value: Double(20 + $0)) },
        tint: SentimentPalette.color(for: .fear)
    )
    .frame(height: 60)
    .padding()
}
