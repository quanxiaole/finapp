import XCTest
import FearGreedCore
@testable import FearGreedUI

private struct StubFetcher: SnapshotFetching {
    let result: Result<Data, Error>
    func fetch(from url: URL) async throws -> Data { try result.get() }
}

private enum StubError: Error, LocalizedError {
    case offline
    var errorDescription: String? { "网络不可用" }
}

private final class ReloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}

@MainActor
final class DashboardViewModelTests: XCTestCase {

    private func liveData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/live_index", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makeModel(
        result: Result<Data, Error>, cache: SnapshotCaching, counter: ReloadCounter
    ) -> DashboardViewModel {
        let repo = IndexRepository(
            fetcher: StubFetcher(result: result), cache: cache, url: FearGreedEndpoint.indexURL
        )
        return DashboardViewModel(repository: repo, reloadWidgets: { counter.increment() })
    }

    func testRefreshSuccessPublishesSnapshotAndReloadsWidgets() async throws {
        let counter = ReloadCounter()
        let model = makeModel(result: .success(try liveData()), cache: InMemorySnapshotCache(), counter: counter)

        await model.refresh()

        XCTAssertEqual(model.snapshot?.us.value, 39.43)
        XCTAssertNil(model.degradedMessage)
        XCTAssertNil(model.fatalMessage)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(counter.count, 1, "拿到新数据后应刷新小组件时间线")
    }

    func testCachedFallbackShowsDegradedMessageWithoutReloadingWidgets() async throws {
        let counter = ReloadCounter()
        let cache = InMemorySnapshotCache(initial: CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try liveData()), fetchedAt: Date()
        ))
        let model = makeModel(result: .failure(StubError.offline), cache: cache, counter: counter)

        await model.refresh()

        XCTAssertNotNil(model.snapshot, "断网时应显示缓存而非白屏")
        XCTAssertEqual(model.degradedMessage, "刷新失败（网络不可用），显示的是上次数据")
        XCTAssertNil(model.fatalMessage)
        XCTAssertEqual(counter.count, 0, "缓存数据没变，无需重刷小组件")
    }

    func testFirstLaunchOfflineSurfacesFatalMessage() async {
        let counter = ReloadCounter()
        let model = makeModel(result: .failure(StubError.offline), cache: InMemorySnapshotCache(), counter: counter)

        await model.refresh()

        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.fatalMessage, "暂时拿不到数据：网络不可用")
    }

    /// 已有数据时刷新失败不应把界面打回空态。
    func testRefreshFailureKeepsExistingSnapshot() async throws {
        let cache = InMemorySnapshotCache()
        let counter = ReloadCounter()
        let ok = makeModel(result: .success(try liveData()), cache: cache, counter: counter)
        await ok.refresh()

        let failing = makeModel(result: .failure(StubError.offline), cache: cache, counter: counter)
        await failing.refresh()

        XCTAssertNotNil(failing.snapshot)
        XCTAssertNil(failing.fatalMessage)
    }

    func testOnAppearShowsCacheBeforeNetwork() async throws {
        let counter = ReloadCounter()
        let cache = InMemorySnapshotCache(initial: CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try liveData()),
            fetchedAt: Date(timeIntervalSince1970: 1_780_000_000)
        ))
        let model = makeModel(result: .success(try liveData()), cache: cache, counter: counter)

        await model.onAppear()

        XCTAssertNotNil(model.snapshot)
        XCTAssertFalse(model.load?.isFromCache ?? true, "网络成功后应替换为新数据")
    }
}
