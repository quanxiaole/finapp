import XCTest
@testable import FearGreedCore

/// 用真实线上 JSON 固件验证解码，并覆盖管道降级时的 null / 缺字段边界。
final class DecodingTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "找不到固件 \(name).json"
        )
        return try Data(contentsOf: url)
    }

    // MARK: - 真实数据

    func testDecodeLiveFixture() throws {
        let snapshot = try SnapshotDecoder.decode(loadFixture("live_index"))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.us.value, 39.43)
        XCTAssertEqual(snapshot.us.label, .fear)
        XCTAssertEqual(snapshot.us.prevClose, 39.6)
        XCTAssertEqual(snapshot.us.weekAgo, 37.23)
        XCTAssertFalse(snapshot.us.stale)
        // 美股无 coverage / as_of
        XCTAssertNil(snapshot.us.coverage)
        XCTAssertNil(snapshot.us.asOf)

        XCTAssertEqual(snapshot.cn.value, 16.18)
        XCTAssertEqual(snapshot.cn.label, .extremeFear)
        XCTAssertEqual(snapshot.cn.coverage, 0.65)
        XCTAssertEqual(snapshot.cn.asOf, "2026-07-24")

        XCTAssertEqual(snapshot.usHistory.count, 67)
        XCTAssertEqual(snapshot.cnHistory.count, 90)
        XCTAssertEqual(snapshot.cnHistory.last, HistoryPoint(date: "2026-07-24", value: 16.18))
    }

    func testUpdatedAtParsesTimezoneOffset() throws {
        let snapshot = try SnapshotDecoder.decode(loadFixture("live_index"))
        // 2026-07-27T13:43:44+08:00 == 2026-07-27T05:43:44Z
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 27
        components.hour = 5; components.minute = 43; components.second = 44
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(snapshot.updatedAt, calendar.date(from: components))
    }

    func testMarketAccessorsAndRecentHistory() throws {
        let snapshot = try SnapshotDecoder.decode(loadFixture("live_index"))
        XCTAssertEqual(snapshot.index(for: .cn), snapshot.cn)
        XCTAssertEqual(snapshot.history(for: .us).count, 67)
        XCTAssertEqual(snapshot.recentHistory(for: .cn, days: 7).count, 7)
        // 取的是最近 7 天，应以最后一天结尾
        XCTAssertEqual(snapshot.recentHistory(for: .cn, days: 7).last, snapshot.cnHistory.last)
    }

    func testRoundTripEncodeDecode() throws {
        let original = try SnapshotDecoder.decode(loadFixture("live_index"))
        let reencoded = try SnapshotDecoder.encode(original)
        XCTAssertEqual(try SnapshotDecoder.decode(reencoded), original)
    }

    // MARK: - 降级 / 边界

    /// 管道抓取失败时 value/label/prev_close/week_ago 全为 null 且 stale=true。
    func testDecodeDegradedNullPayload() throws {
        let json = """
        {
          "schema_version": 1,
          "updated_at": "2026-07-27T13:43:44+08:00",
          "indices": {
            "us": {"value": null, "label": null, "prev_close": null, "week_ago": null, "stale": true},
            "cn": {"value": null, "label": null, "prev_close": null, "week_ago": null,
                   "coverage": null, "as_of": null, "stale": true}
          },
          "history": {"us": [], "cn": []}
        }
        """.data(using: .utf8)!

        let snapshot = try SnapshotDecoder.decode(json)
        XCTAssertNil(snapshot.us.value)
        XCTAssertNil(snapshot.us.label)
        XCTAssertTrue(snapshot.us.stale)
        XCTAssertFalse(snapshot.us.hasValue)
        XCTAssertNil(snapshot.us.changeFromPrevClose)
        XCTAssertFalse(snapshot.cn.isLowConfidence, "coverage 为 null 时不应误判为低置信")
        XCTAssertTrue(snapshot.usHistory.isEmpty)
    }

    /// 管道未来新增等级时不能让整体解码失败。
    func testUnknownLabelFallsBack() throws {
        let json = """
        {"schema_version": 1, "updated_at": "2026-07-27T13:43:44+08:00",
         "indices": {"us": {"value": 50, "label": "euphoria", "stale": false},
                     "cn": {"value": 50, "label": "panic_selling", "stale": false}},
         "history": {"us": [], "cn": []}}
        """.data(using: .utf8)!

        let snapshot = try SnapshotDecoder.decode(json)
        XCTAssertEqual(snapshot.us.label, .unknown)
        XCTAssertEqual(snapshot.cn.label, .unknown)
    }

    /// 缺 stale / 缺 label / 缺 history 时应有合理默认，而非抛错。
    func testMissingFieldsUseDefaults() throws {
        let json = """
        {"updated_at": "2026-07-27T13:43:44+08:00",
         "indices": {"us": {"value": 80}, "cn": {"value": 10}}}
        """.data(using: .utf8)!

        let snapshot = try SnapshotDecoder.decode(json)
        XCTAssertEqual(snapshot.schemaVersion, 1, "缺 schema_version 时默认为 1")
        XCTAssertFalse(snapshot.us.stale, "缺 stale 时默认 false")
        XCTAssertEqual(snapshot.us.label, .extremeGreed, "缺 label 时按数值推导")
        XCTAssertEqual(snapshot.cn.label, .extremeFear)
        XCTAssertTrue(snapshot.cnHistory.isEmpty)
    }

    /// 历史中的坏点应被跳过，而不是让整条历史丢失。
    func testMalformedHistoryPointsAreSkipped() throws {
        let json = """
        {"schema_version": 1, "updated_at": "2026-07-27T13:43:44+08:00",
         "indices": {"us": {"value": 50, "label": "neutral", "stale": false},
                     "cn": {"value": 50, "label": "neutral", "stale": false}},
         "history": {"us": [{"date": "2026-07-20", "value": 41.2},
                            {"date": "2026-07-21", "value": null},
                            {"broken": true},
                            {"date": "2026-07-22", "value": 43.0}],
                     "cn": []}}
        """.data(using: .utf8)!

        let snapshot = try SnapshotDecoder.decode(json)
        XCTAssertEqual(snapshot.usHistory.count, 2, "两个坏点应被跳过")
        XCTAssertEqual(snapshot.usHistory.map(\.date), ["2026-07-20", "2026-07-22"])
    }

    func testInvalidTimestampThrows() {
        let json = """
        {"schema_version": 1, "updated_at": "not-a-date",
         "indices": {"us": {"value": 50}, "cn": {"value": 50}}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try SnapshotDecoder.decode(json))
    }
}
