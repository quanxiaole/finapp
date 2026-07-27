import Foundation
import FearGreedCore

/// 带取回时间的缓存条目。
public struct CachedSnapshot: Sendable, Equatable, Codable {
    public let snapshot: IndexSnapshot
    public let fetchedAt: Date

    public init(snapshot: IndexSnapshot, fetchedAt: Date) {
        self.snapshot = snapshot
        self.fetchedAt = fetchedAt
    }
}

public protocol SnapshotCaching: Sendable {
    func load() -> CachedSnapshot?
    func save(_ cached: CachedSnapshot)
}

/// App Group 共享缓存：主 App 拉到的数据，小组件可直接复用，反之亦然。
///
/// 落地为共享容器里的一个 JSON 文件。若容器不可用（未配置 App Group、
/// 或在 macOS 上跑单测），退回到应用沙盒目录，保证功能不中断。
public struct SharedSnapshotCache: SnapshotCaching {
    private let fileURL: URL

    public init(appGroupID: String = FearGreedEndpoint.appGroupID, fileName: String = "index_snapshot.json") {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        let base = container ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent(fileName)
    }

    /// 供测试注入自定义位置。
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> CachedSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedSnapshot.self, from: data)
    }

    public func save(_ cached: CachedSnapshot) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        // 原子写入，避免小组件正好读到写了一半的文件。
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// 单测用的内存缓存。
public final class InMemorySnapshotCache: SnapshotCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CachedSnapshot?

    public init(initial: CachedSnapshot? = nil) {
        stored = initial
    }

    public func load() -> CachedSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ cached: CachedSnapshot) {
        lock.lock(); defer { lock.unlock() }
        stored = cached
    }
}
