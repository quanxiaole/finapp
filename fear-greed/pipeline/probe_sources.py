"""M1a 可行性核实：逐个探测每因子的历史数据源，报告可得性、日期跨度、行数。

只读探测，不落库。运行：python probe_sources.py
"""
from __future__ import annotations

import datetime as dt
import traceback

import akshare as ak


def _span(df, date_col_candidates=("date", "trade_date", "日期", "统计日期")):
    for c in date_col_candidates:
        if c in df.columns:
            s = df[c].astype(str)
            return f"{s.iloc[0]} → {s.iloc[-1]}", c
    return "(无日期列)", None


def probe(name: str, fn):
    print(f"\n### {name}")
    try:
        df = fn()
        n = len(df)
        cols = list(df.columns)
        span, dcol = _span(df)
        print(f"  ✅ rows={n}  date_col={dcol}  span={span}")
        print(f"     cols={cols[:12]}")
        return n
    except Exception as e:  # noqa: BLE001
        print(f"  ❌ {e!r}")
        traceback.print_exc(limit=1)
        return 0


def past_trading_day(days_ago: int) -> str:
    d = dt.date.today() - dt.timedelta(days=days_ago)
    while d.weekday() >= 5:
        d -= dt.timedelta(days=1)
    return d.strftime("%Y%m%d")


def main():
    d5 = past_trading_day(5)
    print(f"探测历史交易日样本: {d5}")

    # 涨跌停逐日
    probe(f"stock_zt_pool_em(date={d5}) 涨停池", lambda: ak.stock_zt_pool_em(date=d5))
    probe(f"stock_zt_pool_dtgc_em(date={d5}) 跌停池", lambda: ak.stock_zt_pool_dtgc_em(date=d5))

    # 融资余额 2 年
    end = dt.date.today().strftime("%Y%m%d")
    start = (dt.date.today() - dt.timedelta(days=760)).strftime("%Y%m%d")
    probe("stock_margin_sse(2年) 沪市两融汇总",
          lambda: ak.stock_margin_sse(start_date=start, end_date=end))
    probe(f"stock_margin_szse(date={d5}) 深市两融", lambda: ak.stock_margin_szse(date=d5))

    # 波动率
    probe("index_option_50etf_qvix QVIX", lambda: ak.index_option_50etf_qvix())

    # 新高新低
    probe("stock_a_high_low_statistics(all)", lambda: ak.stock_a_high_low_statistics(symbol="all"))

    # 动量/成交（沪深300 历史）
    probe("index_zh_a_hist 000300",
          lambda: ak.index_zh_a_hist(symbol="000300", period="daily",
                                     start_date="20220101", end_date=end))

    # 广度历史——候选源探测
    probe("stock_market_activity_legu 活跃度(快照)", lambda: ak.stock_market_activity_legu())
    # 全A实时快照（用于go-forward 广度累积）
    probe("stock_zh_a_spot_em 全A快照(仅当日)", lambda: ak.stock_zh_a_spot_em())


if __name__ == "__main__":
    main()
