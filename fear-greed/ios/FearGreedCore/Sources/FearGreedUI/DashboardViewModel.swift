import Foundation
import Observation
import WidgetKit
import FearGreedCore

@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var load: SnapshotLoad?
    public private(set) var isRefreshing = false
    /// 完全拿不到数据（首启断网且无缓存）时才有值。
    public private(set) var fatalMessage: String?

    private let repository: IndexRepository
    private let reloadWidgets: @Sendable () -> Void

    /// nonisolated：让 SwiftUI 视图的默认参数能在非隔离上下文里构造它。
    public nonisolated init(
        repository: IndexRepository = IndexRepository(),
        reloadWidgets: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadAllTimelines()
        }
    ) {
        self.repository = repository
        self.reloadWidgets = reloadWidgets
    }

    public var snapshot: IndexSnapshot? { load?.snapshot }

    /// 网络失败但已用缓存兜底时的提示文案。
    public var degradedMessage: String? {
        guard let load, load.isFromCache, let reason = load.failureReason else { return nil }
        return "刷新失败（\(reason)），显示的是上次数据"
    }

    /// 进入页面：先秒出缓存，再后台刷新，避免白屏等待。
    public func onAppear() async {
        if load == nil, let cached = repository.cached() {
            load = cached
        }
        await refresh()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await repository.load()
            load = result
            fatalMessage = nil
            if !result.isFromCache {
                // 主 App 刚写过共享缓存，让小组件立刻取用新数据。
                reloadWidgets()
            }
        } catch {
            if load == nil {
                fatalMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
