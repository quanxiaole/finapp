import Foundation
import WidgetKit
import FearGreedCore

public struct IndexEntry: TimelineEntry, Sendable {
    public let date: Date
    public let snapshot: IndexSnapshot
    /// Small 组件展示哪个市场；Medium 两个都展示，此值仅用于兜底。
    public let market: Market
    /// 占位骨架（尚无真实数据）时为 true，UI 用它做降饱和处理。
    public let isPlaceholder: Bool
    public let isFromCache: Bool

    public init(
        date: Date, snapshot: IndexSnapshot, market: Market,
        isPlaceholder: Bool, isFromCache: Bool = false
    ) {
        self.date = date
        self.snapshot = snapshot
        self.market = market
        self.isPlaceholder = isPlaceholder
        self.isFromCache = isFromCache
    }

    public static func placeholder(market: Market) -> IndexEntry {
        IndexEntry(date: Date(), snapshot: PreviewData.snapshot, market: market, isPlaceholder: true)
    }
}

/// 小组件时间线：每次刷新取一次数据，30 分钟后再来。
///
/// 约 48 次/天，落在系统给单个组件的 40–70 次预算内；系统仍可能因电量或
/// 使用频率进一步节流，所以 `.after` 是「不早于」而非精确保证。
public struct IndexTimelineProvider: TimelineProvider {
    private let market: Market
    private let repository: IndexRepository

    public init(market: Market, repository: IndexRepository = IndexRepository()) {
        self.market = market
        self.repository = repository
    }

    public func placeholder(in context: Context) -> IndexEntry {
        .placeholder(market: market)
    }

    /// 组件库预览：优先用共享缓存里的真实数据，没有才用占位。
    public func getSnapshot(in context: Context, completion: @escaping (IndexEntry) -> Void) {
        if let cached = repository.cached() {
            completion(IndexEntry(
                date: Date(), snapshot: cached.snapshot, market: market,
                isPlaceholder: false, isFromCache: true
            ))
        } else {
            completion(.placeholder(market: market))
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<IndexEntry>) -> Void) {
        Task {
            completion(await makeTimeline(now: Date()))
        }
    }

    /// 抽出来是为了能在没有 WidgetKit `Context`（无法构造）的情况下做单测。
    public func makeTimeline(now: Date) async -> Timeline<IndexEntry> {
        let entry: IndexEntry
        do {
            let load = try await repository.load()
            entry = IndexEntry(
                date: now, snapshot: load.snapshot, market: market,
                isPlaceholder: false, isFromCache: load.isFromCache
            )
        } catch {
            // 取不到就先画占位，交给下一个刷新点重试，不留空组件。
            entry = .placeholder(market: market)
        }
        let next = now.addingTimeInterval(FearGreedEndpoint.widgetRefreshInterval)
        return Timeline(entries: [entry], policy: .after(next))
    }
}
