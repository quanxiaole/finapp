import Foundation
import FearGreedCore

/// 一次加载的结果：数据本身 + 它是新拉的还是缓存兜底的。
public struct SnapshotLoad: Sendable, Equatable {
    public let snapshot: IndexSnapshot
    public let fetchedAt: Date
    public let isFromCache: Bool
    /// 网络失败但成功回退到缓存时，记录失败原因供 UI 提示。
    public let failureReason: String?

    public init(snapshot: IndexSnapshot, fetchedAt: Date, isFromCache: Bool, failureReason: String? = nil) {
        self.snapshot = snapshot
        self.fetchedAt = fetchedAt
        self.isFromCache = isFromCache
        self.failureReason = failureReason
    }
}

public enum SnapshotLoadError: Error, LocalizedError, Equatable {
    case offlineWithoutCache(String)

    public var errorDescription: String? {
        switch self {
        case .offlineWithoutCache(let reason):
            return "暂时拿不到数据：\(reason)"
        }
    }
}

public protocol SnapshotFetching: Sendable {
    func fetch(from url: URL) async throws -> Data
}

public struct URLSessionSnapshotFetcher: SnapshotFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = FearGreedEndpoint.requestTimeout
        // 走 ETag 校验：命中则 304，避免拿到 URLCache 里的过期副本。
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return data
    }
}

/// 取数编排：网络优先，失败回退共享缓存，两者皆无才报错。
public actor IndexRepository {
    private let fetcher: SnapshotFetching
    private let cache: SnapshotCaching
    private let url: URL
    private let now: @Sendable () -> Date

    public init(
        fetcher: SnapshotFetching = URLSessionSnapshotFetcher(),
        cache: SnapshotCaching = SharedSnapshotCache(),
        url: URL = FearGreedEndpoint.indexURL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.url = url
        self.now = now
    }

    /// 只读缓存，不发网络请求。小组件的 placeholder / snapshot 用它秒出。
    public nonisolated func cached() -> SnapshotLoad? {
        guard let cached = cache.load() else { return nil }
        return SnapshotLoad(snapshot: cached.snapshot, fetchedAt: cached.fetchedAt, isFromCache: true)
    }

    public func load() async throws -> SnapshotLoad {
        do {
            let data = try await fetcher.fetch(from: url)
            let snapshot = try SnapshotDecoder.decode(data)
            let fetchedAt = now()
            cache.save(CachedSnapshot(snapshot: snapshot, fetchedAt: fetchedAt))
            return SnapshotLoad(snapshot: snapshot, fetchedAt: fetchedAt, isFromCache: false)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            guard let cached = cache.load() else {
                throw SnapshotLoadError.offlineWithoutCache(reason)
            }
            return SnapshotLoad(
                snapshot: cached.snapshot, fetchedAt: cached.fetchedAt,
                isFromCache: true, failureReason: reason
            )
        }
    }
}
