import XCTest
import FearGreedCore
@testable import FearGreedUI

private struct StubFetcher: SnapshotFetching {
    let result: Result<Data, Error>
    func fetch(from url: URL) async throws -> Data {
        try result.get()
    }
}

private enum StubError: Error, LocalizedError {
    case offline
    var errorDescription: String? { "网络不可用" }
}

final class IndexRepositoryTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_785_000_000)

    private func liveData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/live_index", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makeRepo(
        result: Result<Data, Error>, cache: SnapshotCaching
    ) -> IndexRepository {
        IndexRepository(
            fetcher: StubFetcher(result: result), cache: cache,
            url: FearGreedEndpoint.indexURL, now: { [fixedNow] in fixedNow }
        )
    }

    func testSuccessfulLoadReturnsFreshAndWritesCache() async throws {
        let cache = InMemorySnapshotCache()
        let repo = makeRepo(result: .success(try liveData()), cache: cache)

        let load = try await repo.load()
        XCTAssertFalse(load.isFromCache)
        XCTAssertNil(load.failureReason)
        XCTAssertEqual(load.fetchedAt, fixedNow)
        XCTAssertEqual(load.snapshot.us.value, 39.43)
        XCTAssertEqual(cache.load()?.snapshot, load.snapshot, "成功后应写入共享缓存")
    }

    /// 断网时必须回退缓存，而不是白屏。
    func testNetworkFailureFallsBackToCache() async throws {
        let stored = CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try liveData()),
            fetchedAt: Date(timeIntervalSince1970: 1_784_000_000)
        )
        let cache = InMemorySnapshotCache(initial: stored)
        let repo = makeRepo(result: .failure(StubError.offline), cache: cache)

        let load = try await repo.load()
        XCTAssertTrue(load.isFromCache)
        XCTAssertEqual(load.failureReason, "网络不可用")
        XCTAssertEqual(load.fetchedAt, stored.fetchedAt, "应保留原始取回时间以便展示")
        XCTAssertEqual(load.snapshot.cn.value, 16.18)
    }

    /// 首启即断网、无任何缓存时才允许报错。
    func testNetworkFailureWithoutCacheThrows() async {
        let repo = makeRepo(result: .failure(StubError.offline), cache: InMemorySnapshotCache())
        do {
            _ = try await repo.load()
            XCTFail("应抛出 offlineWithoutCache")
        } catch let error as SnapshotLoadError {
            XCTAssertEqual(error, .offlineWithoutCache("网络不可用"))
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
    }

    /// 服务端返回坏 JSON 时，也应走缓存兜底而非崩溃。
    func testMalformedPayloadFallsBackToCache() async throws {
        let stored = CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try liveData()), fetchedAt: fixedNow
        )
        let cache = InMemorySnapshotCache(initial: stored)
        let repo = makeRepo(result: .success(Data("<html>502</html>".utf8)), cache: cache)

        let load = try await repo.load()
        XCTAssertTrue(load.isFromCache)
        XCTAssertNotNil(load.failureReason)
    }

    func testCachedOnlyDoesNotHitNetwork() throws {
        let stored = CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try liveData()), fetchedAt: fixedNow
        )
        let repo = makeRepo(result: .failure(StubError.offline), cache: InMemorySnapshotCache(initial: stored))
        let load = try XCTUnwrap(repo.cached())
        XCTAssertTrue(load.isFromCache)
        XCTAssertEqual(load.fetchedAt, fixedNow)
    }

    func testCachedOnlyReturnsNilWhenEmpty() {
        let repo = makeRepo(result: .failure(StubError.offline), cache: InMemorySnapshotCache())
        XCTAssertNil(repo.cached())
    }
}

final class SharedSnapshotCacheTests: XCTestCase {

    func testFileCacheRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fg-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cache = SharedSnapshotCache(fileURL: tmp)
        XCTAssertNil(cache.load(), "空缓存应返回 nil")

        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/live_index", withExtension: "json"))
        let entry = CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try Data(contentsOf: url)),
            fetchedAt: Date(timeIntervalSince1970: 1_785_000_000)
        )
        cache.save(entry)

        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.snapshot, entry.snapshot)
        XCTAssertEqual(loaded.fetchedAt.timeIntervalSince1970, entry.fetchedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCorruptedFileIsIgnored() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fg-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("garbage".utf8).write(to: tmp)

        XCTAssertNil(SharedSnapshotCache(fileURL: tmp).load(), "损坏缓存不应导致崩溃")
    }

    /// App Group 未配置（如单测环境）时应静默退回本地目录而非崩溃。
    func testFallsBackWhenAppGroupUnavailable() {
        let cache = SharedSnapshotCache(appGroupID: "group.invalid.does.not.exist")
        XCTAssertNil(cache.load())
    }
}
