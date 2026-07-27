import Foundation

/// 数据分发配置（决策见 docs/SDD.md 2.7）。
///
/// 用 raw.githubusercontent（`cache-control: max-age=300`）而非 jsDelivr
/// （`max-age=604800`，客户端会缓存 7 天，小组件将长期显示过期数据）。
public enum FearGreedEndpoint {
    public static let indexURLString =
        "https://raw.githubusercontent.com/quanxiaole/finapp/main/fear-greed/pipeline/out/index.json"

    public static var indexURL: URL {
        guard let url = URL(string: indexURLString) else {
            preconditionFailure("内置数据源 URL 非法: \(indexURLString)")
        }
        return url
    }

    /// App Group 标识，供主 App 与 Widget 共享缓存（M2b 在两个 target 上勾选同一 ID）。
    public static let appGroupID = "group.com.quanxiaole.feargreed"

    /// 共享缓存中存放快照的键。
    public static let cacheKey = "cached_index_snapshot"

    /// 小组件时间线刷新间隔；约 48 次/天，落在系统 40–70 次预算内。
    public static let widgetRefreshInterval: TimeInterval = 30 * 60

    /// 网络请求超时。
    public static let requestTimeout: TimeInterval = 15
}
