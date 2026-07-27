import SwiftUI
import FearGreedCore

/// 主界面：双市场仪表盘 + 下拉刷新。
public struct DashboardView: View {
    @State private var model: DashboardViewModel

    public init(model: DashboardViewModel = DashboardViewModel()) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("恐慌与贪婪")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                    .accessibilityLabel("刷新")
                }
            }
        }
        .task { await model.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.snapshot {
            VStack(spacing: 16) {
                if let degraded = model.degradedMessage {
                    banner(degraded, systemImage: "wifi.exclamationmark")
                }
                marketCards(snapshot)
                footer(snapshot)
            }
        } else if let fatal = model.fatalMessage {
            emptyState(message: fatal)
        } else {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    /// 宽度够就并排，iPhone 竖屏自动改为上下堆叠。
    @ViewBuilder
    private func marketCards(_ snapshot: IndexSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Market.allCases, id: \.self) { market in
                    card(snapshot, market).frame(minWidth: 300)
                }
            }
            VStack(spacing: 16) {
                ForEach(Market.allCases, id: \.self) { market in
                    card(snapshot, market)
                }
            }
        }
    }

    private func card(_ snapshot: IndexSnapshot, _ market: Market) -> some View {
        MarketCardView(
            presentation: snapshot.presentation(for: market),
            history: snapshot.recentHistory(for: market, days: 30)
        )
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    private func footer(_ snapshot: IndexSnapshot) -> some View {
        VStack(spacing: 6) {
            Text("更新于 \(snapshot.freshnessText())")
                .font(.caption)
                .foregroundStyle(.secondary)
            // 方法论详情页在 M3 完善，这里先把入口和口径说清楚。
            Text("美股取 CNN Fear & Greed；A股为自研七因子指数，0 = 极度恐慌，100 = 极度贪婪。")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    private func emptyState(message: String) -> some View {
        ContentUnavailableView {
            Label("暂无数据", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { Task { await model.refresh() } }
        }
        .frame(minHeight: 320)
    }
}

#Preview {
    DashboardView()
}
