import XCTest
import WidgetKit
import FearGreedCore
@testable import FearGreedUI

private struct StubFetcher: SnapshotFetching {
    let result: Result<Data, Error>
    func fetch(from url: URL) async throws -> Data { try result.get() }
}

private enum StubError: Error { case offline }

final class WidgetTimelineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    private func liveData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/live_index", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makeProvider(
        result: Result<Data, Error>, cache: SnapshotCaching = InMemorySnapshotCache()
    ) -> IndexTimelineProvider {
        IndexTimelineProvider(
            market: .cn,
            repository: IndexRepository(
                fetcher: StubFetcher(result: result), cache: cache, url: FearGreedEndpoint.indexURL
            )
        )
    }

    func testTimelineCarriesDataAndSchedulesNextRefresh() async throws {
        let timeline = await makeProvider(result: .success(try liveData())).makeTimeline(now: now)

        XCTAssertEqual(timeline.entries.count, 1)
        let entry = try XCTUnwrap(timeline.entries.first)
        XCTAssertFalse(entry.isPlaceholder)
        XCTAssertFalse(entry.isFromCache)
        XCTAssertEqual(entry.snapshot.cn.value, 16.18)
        XCTAssertEqual(entry.date, now)
        XCTAssertEqual(timeline.policy, .after(now.addingTimeInterval(30 * 60)))
    }

    /// 取不到数据时也必须给出时间线，否则组件会一直空着不再重试。
    func testFailureStillSchedulesRetry() async {
        let timeline = await makeProvider(result: .failure(StubError.offline)).makeTimeline(now: now)

        XCTAssertEqual(timeline.entries.count, 1)
        XCTAssertTrue(timeline.entries[0].isPlaceholder)
        XCTAssertEqual(timeline.policy, .after(now.addingTimeInterval(30 * 60)))
    }

    func testFallsBackToCacheAndMarksIt() async throws {
        let cache = InMemorySnapshotCache(initial: CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try liveData()), fetchedAt: now
        ))
        let timeline = await makeProvider(result: .failure(StubError.offline), cache: cache)
            .makeTimeline(now: now)

        let entry = try XCTUnwrap(timeline.entries.first)
        XCTAssertFalse(entry.isPlaceholder, "有缓存就该显示真实数值")
        XCTAssertTrue(entry.isFromCache, "需标记为缓存以便 UI 显示时钟图标")
    }

    func testPlaceholderUsesPreviewData() {
        let entry = IndexEntry.placeholder(market: .us)
        XCTAssertTrue(entry.isPlaceholder)
        XCTAssertNotNil(entry.snapshot.us.value, "占位骨架也要有数值，避免系统截图出现空白")
    }

    func testGetSnapshotPrefersCacheOverPlaceholder() throws {
        let cache = InMemorySnapshotCache(initial: CachedSnapshot(
            snapshot: try SnapshotDecoder.decode(try liveData()), fetchedAt: now
        ))
        let provider = makeProvider(result: .failure(StubError.offline), cache: cache)

        let expectation = expectation(description: "snapshot")
        var received: IndexEntry?
        provider.getSnapshot(in: makeContext()) { entry in
            received = entry
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(received?.isPlaceholder, false)
        XCTAssertEqual(received?.snapshot.cn.value, 16.18)
    }

    /// WidgetKit 的 Context 无公开构造器，用 unsafeBitCast 造一个仅供 getSnapshot 走通路径。
    /// getSnapshot 的实现并不读取 context 内容，因此这样是安全的。
    private func makeContext() -> TimelineProviderContext {
        let bytes = [UInt8](repeating: 0, count: MemoryLayout<TimelineProviderContext>.size)
        return bytes.withUnsafeBytes { $0.load(as: TimelineProviderContext.self) }
    }
}
