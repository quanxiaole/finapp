"""因子原始值定义（单一事实源）。

回填(backfill.py) 与 实时管道(fetch_cn.py) 共用这些定义，
确保「历史分布」与「当日值」口径一致，分位数才有意义。

每个 series_* 返回 [(YYYY-MM-DD, raw_value)]，已按日期升序、去 warmup。
"""
from __future__ import annotations

import datetime as dt

import akshare as ak
import pandas as pd

from net import with_retry


def _iso(x) -> str:
    """把各种日期表示统一成 YYYY-MM-DD。"""
    if isinstance(x, str):
        s = x.strip()
        if len(s) == 8 and s.isdigit():  # YYYYMMDD
            return f"{s[:4]}-{s[4:6]}-{s[6:]}"
        return s[:10]
    if isinstance(x, (dt.date, dt.datetime)):
        return x.strftime("%Y-%m-%d")
    return pd.to_datetime(x).strftime("%Y-%m-%d")


# --------------------------------------------------------------------------
# 沪深300 日线（动量 + 成交共用），多源容错
# --------------------------------------------------------------------------
def hs300_hist(start: str = "20180101") -> pd.DataFrame:
    end = dt.date.today().strftime("%Y%m%d")

    def _em():
        df = ak.index_zh_a_hist(symbol="000300", period="daily",
                                start_date=start, end_date=end)
        df = df.rename(columns={"日期": "date", "收盘": "close", "成交额": "amount"})
        return df[["date", "close", "amount"]]

    def _sina():
        # 新浪指数日线列: date, open, high, low, close, volume（无成交额 → 用成交量做热度代理）
        df = ak.stock_zh_index_daily(symbol="sh000300")
        if "date" not in df.columns:
            df = df.reset_index().rename(columns={"index": "date"})
        if "amount" not in df.columns:
            df["amount"] = df["volume"]
        return df[["date", "close", "amount"]]

    try:
        df = with_retry(_em, tries=5, label="index_zh_a_hist")
        if df is not None and len(df):
            df["date"] = df["date"].map(_iso)
            return df.reset_index(drop=True)
    except Exception:  # noqa: BLE001
        pass
    df = with_retry(_sina, tries=5, label="stock_zh_index_daily")
    df["date"] = df["date"].map(_iso)
    return df.reset_index(drop=True)


def series_momentum(hs300: pd.DataFrame) -> list[tuple[str, float]]:
    close = hs300["close"].astype(float)
    ma125 = close.rolling(125).mean()
    dev = (close - ma125) / ma125
    out = pd.DataFrame({"date": hs300["date"], "v": dev}).dropna()
    return list(out.itertuples(index=False, name=None))


def series_turnover(hs300: pd.DataFrame) -> list[tuple[str, float]]:
    amount = hs300["amount"].astype(float)
    heat = amount / amount.rolling(60).mean()
    out = pd.DataFrame({"date": hs300["date"], "v": heat}).dropna()
    return list(out.itertuples(index=False, name=None))


# --------------------------------------------------------------------------
# 新高新低：净新高（high120 - low120，近似 52 周）
# --------------------------------------------------------------------------
def series_high_low() -> list[tuple[str, float]]:
    df = with_retry(lambda: ak.stock_a_high_low_statistics(symbol="all"))
    hi = next(c for c in df.columns if "high" in c.lower() and "120" in c)
    lo = next(c for c in df.columns if "low" in c.lower() and "120" in c)
    net = df[hi].astype(float) - df[lo].astype(float)
    out = pd.DataFrame({"date": df["date"].map(_iso), "v": net}).dropna()
    return list(out.itertuples(index=False, name=None))


# --------------------------------------------------------------------------
# 杠杆：沪市融资余额 5 日变化率
# --------------------------------------------------------------------------
def series_leverage() -> list[tuple[str, float]]:
    end = dt.date.today().strftime("%Y%m%d")
    start = (dt.date.today() - dt.timedelta(days=900)).strftime("%Y%m%d")
    df = with_retry(lambda: ak.stock_margin_sse(start_date=start, end_date=end))
    dcol = "信用交易日期"
    vcol = "融资余额"
    df = df[[dcol, vcol]].copy()
    df[dcol] = df[dcol].map(_iso)
    df = df.sort_values(dcol)
    chg = df[vcol].astype(float).pct_change(5)
    out = pd.DataFrame({"date": df[dcol], "v": chg}).dropna()
    return list(out.itertuples(index=False, name=None))


# --------------------------------------------------------------------------
# 波动率：QVIX 收盘
# --------------------------------------------------------------------------
def series_volatility() -> list[tuple[str, float]]:
    df = with_retry(lambda: ak.index_option_50etf_qvix())
    col = "close" if "close" in df.columns else df.columns[-1]
    out = pd.DataFrame({"date": df["date"].map(_iso), "v": df[col].astype(float)}).dropna()
    return list(out.itertuples(index=False, name=None))


# --------------------------------------------------------------------------
# 涨跌停：逐日 涨停/(涨停+跌停)（历史需按交易日循环）
# --------------------------------------------------------------------------
def day_limit_sentiment(yyyymmdd: str) -> float | None:
    """给定交易日（YYYYMMDD），返回 涨停/(涨停+跌停) 比例；无数据返回 None。"""
    zt = with_retry(lambda: ak.stock_zt_pool_em(date=yyyymmdd))
    dt_ = with_retry(lambda: ak.stock_zt_pool_dtgc_em(date=yyyymmdd))
    nz, nd = len(zt) if zt is not None else 0, len(dt_) if dt_ is not None else 0
    if nz + nd == 0:
        return None
    return nz / (nz + nd)


# --------------------------------------------------------------------------
# 市场广度：当日快照（无历史接口，go-forward 累积）
# --------------------------------------------------------------------------
def snapshot_breadth() -> float:
    df = with_retry(lambda: ak.stock_market_activity_legu())
    d = dict(zip(df["item"], df["value"]))
    up, down = float(d["上涨"]), float(d["下跌"])
    return up / (up + down) if (up + down) else 0.5


def trading_days(start: dt.date, end: dt.date) -> list[str]:
    """交易日历（YYYYMMDD），用于涨跌停逐日回填。"""
    cal = with_retry(lambda: ak.tool_trade_date_hist_sina())
    days = pd.to_datetime(cal["trade_date"]).dt.date
    return [d.strftime("%Y%m%d") for d in days if start <= d <= end]
