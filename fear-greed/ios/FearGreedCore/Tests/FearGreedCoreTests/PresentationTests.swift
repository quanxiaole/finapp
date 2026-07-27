import XCTest
@testable import FearGreedCore

final class SentimentLabelTests: XCTestCase {

    /// 阈值必须与 pipeline/index_utils.py 的 label_for 一致。
    func testThresholdsMatchPipeline() {
        XCTAssertEqual(SentimentLabel(value: 0), .extremeFear)
        XCTAssertEqual(SentimentLabel(value: 24.9), .extremeFear)
        XCTAssertEqual(SentimentLabel(value: 25), .fear)
        XCTAssertEqual(SentimentLabel(value: 44.9), .fear)
        XCTAssertEqual(SentimentLabel(value: 45), .neutral)
        XCTAssertEqual(SentimentLabel(value: 54.9), .neutral)
        XCTAssertEqual(SentimentLabel(value: 55), .greed)
        XCTAssertEqual(SentimentLabel(value: 74.9), .greed)
        XCTAssertEqual(SentimentLabel(value: 75), .extremeGreed)
        XCTAssertEqual(SentimentLabel(value: 100), .extremeGreed)
    }

    func testDisplayNames() {
        XCTAssertEqual(SentimentLabel.extremeFear.displayNameZH, "极度恐慌")
        XCTAssertEqual(SentimentLabel.extremeGreed.displayNameEN, "Extreme Greed")
        XCTAssertEqual(SentimentLabel.unknown.displayNameZH, "未知")
    }

    func testPolarityOrdering() {
        XCTAssertLessThan(SentimentLabel.extremeFear.polarity, SentimentLabel.fear.polarity)
        XCTAssertLessThan(SentimentLabel.fear.polarity, SentimentLabel.neutral.polarity)
        XCTAssertLessThan(SentimentLabel.neutral.polarity, SentimentLabel.greed.polarity)
        XCTAssertLessThan(SentimentLabel.greed.polarity, SentimentLabel.extremeGreed.polarity)
    }
}

final class PresentationTests: XCTestCase {

    private func makeIndex(
        value: Double? = 39.43, label: SentimentLabel? = .fear, prevClose: Double? = 39.6,
        weekAgo: Double? = 37.23, coverage: Double? = nil, asOf: String? = nil,
        stale: Bool = false
    ) -> MarketIndex {
        MarketIndex(value: value, label: label, prevClose: prevClose, weekAgo: weekAgo,
                    coverage: coverage, asOf: asOf, stale: stale)
    }

    func testFormattedValueRounds() {
        XCTAssertEqual(IndexPresentation(market: .us, index: makeIndex(value: 39.43)).formattedValue, "39")
        XCTAssertEqual(IndexPresentation(market: .us, index: makeIndex(value: 39.6)).formattedValue, "40")
    }

    func testPlaceholderWhenNoValue() {
        let p = IndexPresentation(market: .us, index: makeIndex(value: nil, label: nil))
        XCTAssertEqual(p.formattedValue, "--")
        XCTAssertEqual(p.labelTextZH, "--")
        XCTAssertEqual(p.gaugeFraction, 0)
    }

    func testDeltaTextsSigned() {
        let p = IndexPresentation(market: .us, index: makeIndex())
        // 39.43 - 39.6 = -0.17 → -0.2
        XCTAssertEqual(p.deltaFromPrevCloseText, "-0.2")
        // 39.43 - 37.23 = +2.2
        XCTAssertEqual(p.deltaFromWeekAgoText, "+2.2")
    }

    func testDeltaNilWhenBaselineMissing() {
        let p = IndexPresentation(market: .cn, index: makeIndex(prevClose: nil, weekAgo: nil))
        XCTAssertNil(p.deltaFromPrevCloseText)
        XCTAssertNil(p.deltaFromWeekAgoText)
    }

    func testGaugeFractionClamped() {
        XCTAssertEqual(IndexPresentation(market: .us, index: makeIndex(value: 50)).gaugeFraction, 0.5)
        XCTAssertEqual(IndexPresentation(market: .us, index: makeIndex(value: 150)).gaugeFraction, 1)
        XCTAssertEqual(IndexPresentation(market: .us, index: makeIndex(value: -10)).gaugeFraction, 0)
    }

    func testAdvisoryCombinesSignals() {
        let cn = makeIndex(coverage: 0.65, asOf: "2026-07-24", stale: true)
        let advisory = IndexPresentation(market: .cn, index: cn).advisoryZH
        XCTAssertEqual(advisory, "数据未更新 · 因子覆盖 65% · 截至 2026-07-24")
    }

    func testAdvisoryNilWhenHealthy() {
        let healthy = makeIndex(coverage: 1.0, asOf: nil, stale: false)
        XCTAssertNil(IndexPresentation(market: .us, index: healthy).advisoryZH)
    }

    func testOutdatedDetection() {
        let snapshot = IndexSnapshot(
            schemaVersion: 1, updatedAt: Date(timeIntervalSinceNow: -4 * 3600),
            us: makeIndex(), cn: makeIndex()
        )
        XCTAssertTrue(snapshot.isOutdated())
        XCTAssertFalse(snapshot.isOutdated(tolerance: 5 * 3600))
    }
}

final class EndpointTests: XCTestCase {

    func testIndexURLIsValidAndClean() {
        let url = FearGreedEndpoint.indexURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "raw.githubusercontent.com")
        XCTAssertTrue(url.path.hasSuffix("/fear-greed/pipeline/out/index.json"))
        XCTAssertFalse(FearGreedEndpoint.indexURLString.contains("%20"), "路径不应含转义空格")
        XCTAssertFalse(FearGreedEndpoint.indexURLString.contains("%26"), "路径不应含转义 &")
    }

    /// 30 分钟间隔约合 48 次/天，需落在系统 40–70 次刷新预算内。
    func testWidgetRefreshWithinBudget() {
        let perDay = 24 * 3600 / FearGreedEndpoint.widgetRefreshInterval
        XCTAssertGreaterThanOrEqual(perDay, 40)
        XCTAssertLessThanOrEqual(perDay, 70)
    }
}
