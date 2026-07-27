import Foundation

/// 一次数据拉取的完整快照，对应管道产出的 index.json（schema_version = 1）。
public struct IndexSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let updatedAt: Date
    public let us: MarketIndex
    public let cn: MarketIndex
    public let usHistory: [HistoryPoint]
    public let cnHistory: [HistoryPoint]

    public init(
        schemaVersion: Int, updatedAt: Date, us: MarketIndex, cn: MarketIndex,
        usHistory: [HistoryPoint] = [], cnHistory: [HistoryPoint] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.us = us
        self.cn = cn
        self.usHistory = usHistory
        self.cnHistory = cnHistory
    }

    // JSON 是 indices.{us,cn} / history.{us,cn} 的嵌套结构，需手写容器。
    enum RootKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case indices, history
    }

    enum MarketKeys: String, CodingKey {
        case us, cn
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        schemaVersion = try root.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        let raw = try root.decode(String.self, forKey: .updatedAt)
        guard let parsed = DateParsing.timestamp(from: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .updatedAt, in: root,
                debugDescription: "无法解析时间戳: \(raw)"
            )
        }
        updatedAt = parsed

        let indices = try root.nestedContainer(keyedBy: MarketKeys.self, forKey: .indices)
        us = try indices.decode(MarketIndex.self, forKey: .us)
        cn = try indices.decode(MarketIndex.self, forKey: .cn)

        if let history = try? root.nestedContainer(keyedBy: MarketKeys.self, forKey: .history) {
            usHistory = Self.decodeHistory(from: history, key: .us)
            cnHistory = Self.decodeHistory(from: history, key: .cn)
        } else {
            usHistory = []
            cnHistory = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: RootKeys.self)
        try root.encode(schemaVersion, forKey: .schemaVersion)
        try root.encode(DateParsing.string(from: updatedAt), forKey: .updatedAt)
        var indices = root.nestedContainer(keyedBy: MarketKeys.self, forKey: .indices)
        try indices.encode(us, forKey: .us)
        try indices.encode(cn, forKey: .cn)
        var history = root.nestedContainer(keyedBy: MarketKeys.self, forKey: .history)
        try history.encode(usHistory, forKey: .us)
        try history.encode(cnHistory, forKey: .cn)
    }

    /// 单个坏点不应让整条历史失败，逐条解码并跳过异常项。
    private static func decodeHistory(
        from container: KeyedDecodingContainer<MarketKeys>, key: MarketKeys
    ) -> [HistoryPoint] {
        guard let points = try? container.decode([FailableDecodable<HistoryPoint>].self, forKey: key)
        else { return [] }
        return points.compactMap(\.value)
    }

    public func index(for market: Market) -> MarketIndex {
        switch market {
        case .us: return us
        case .cn: return cn
        }
    }

    public func history(for market: Market) -> [HistoryPoint] {
        switch market {
        case .us: return usHistory
        case .cn: return cnHistory
        }
    }

    /// 取最近 n 天历史，供小组件迷你趋势图使用。
    public func recentHistory(for market: Market, days: Int) -> [HistoryPoint] {
        Array(history(for: market).suffix(days))
    }
}

// MARK: - 解码工具

/// 包装一层，使数组中单个元素解码失败时可被跳过而非中断整体。
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public enum DateParsing {
    /// 管道写出的是带时区偏移的 ISO8601（如 2026-07-27T13:43:44+08:00）。
    /// 同时容忍带小数秒的变体。
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func timestamp(from string: String) -> Date? {
        plain.date(from: string) ?? withFractional.date(from: string)
    }

    public static func string(from date: Date) -> String {
        plain.string(from: date)
    }
}

// MARK: - 解码入口

public enum SnapshotDecoder {
    public static func decode(_ data: Data) throws -> IndexSnapshot {
        try JSONDecoder().decode(IndexSnapshot.self, from: data)
    }

    public static func encode(_ snapshot: IndexSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }
}
