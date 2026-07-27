"""M1b A股指数计算引擎：读回填库，做 point-in-time 滚动 2 年分位合成。

- 每个因子在日期 d 的得分 = d 当日原始值在「截至 d 的最近 2 年窗口」内的分位数
  （point-in-time，避免前视偏差）。
- 反向因子（波动率）取 100 - 分位。
- 窗口不足 MIN_WINDOW 的因子标 low_confidence，不参与合成（权重重分配）。
- 产出当前值 + 近 90 天 cn.history 序列。
"""
from __future__ import annotations

import sqlite3
from typing import Optional

import pandas as pd

import storage as st
from index_utils import label_for

WINDOW = 504          # 滚动 2 年（交易日）
MIN_WINDOW = 60       # 低于此窗口视为置信不足
MAX_STALENESS = 7     # 因子最新观测距参考日超过 N 天则视为缺失（容忍 T+1/周末）


def load_series(conn: sqlite3.Connection, factor: str) -> pd.Series:
    rows = st.read_series(conn, factor)
    if not rows:
        return pd.Series(dtype=float)
    s = pd.Series({d: v for d, v in rows}).sort_index()
    return s


def _pct_asof(window_vals: pd.Series, value: float, reverse: bool) -> float:
    n = len(window_vals)
    below = int((window_vals <= value).sum())
    pct = 100.0 * below / n
    return max(0.0, min(100.0, 100.0 - pct if reverse else pct))


def _days_between(a: str, b: str) -> int:
    from datetime import date

    ya, ma, da = map(int, a.split("-"))
    yb, mb, db = map(int, b.split("-"))
    return abs((date(yb, mb, db) - date(ya, ma, da)).days)


def factor_score_asof(series: pd.Series, date: str, reverse: bool) -> Optional[dict]:
    """as-of 语义：取截至 d（含）的最近一次观测，算其在滚动窗口内的分位。

    - 因子最新观测距 d 超过 MAX_STALENESS 天 → 视为缺失（None）。
    - 窗口不足 MIN_WINDOW → low_confidence（不参与合成）。
    这样能容忍 T+1（融资）、期权休市（QVIX）等发布滞后。
    """
    upto = series.loc[:date]
    if upto.empty:
        return None
    last_date = str(upto.index[-1])
    if _days_between(last_date, date) > MAX_STALENESS:
        return None
    window = upto.iloc[-WINDOW:]
    n = len(window)
    if n < MIN_WINDOW:
        return {"score": None, "window": n, "low_confidence": True}
    value = float(upto.iloc[-1])
    return {
        "score": round(_pct_asof(window, value, reverse), 2),
        "window": n,
        "low_confidence": False,
    }


def composite_for_date(series_map: dict[str, pd.Series], date: str) -> Optional[dict]:
    used, contrib, low_conf = [], [], []
    total_w = 0.0
    acc = 0.0
    for factor, (weight, reverse) in st.FACTOR_META.items():
        s = series_map.get(factor)
        if s is None or s.empty:
            continue
        r = factor_score_asof(s, date, reverse)
        if r is None:
            continue
        if r["low_confidence"] or r["score"] is None:
            low_conf.append(factor)
            continue
        used.append(factor)
        acc += r["score"] * weight
        total_w += weight
        contrib.append({"factor": factor, "score": r["score"], "window": r["window"]})
    if not used or total_w == 0:
        return None
    value = round(acc / total_w, 2)
    return {
        "value": value,
        "label": label_for(value),
        "coverage": round(total_w, 3),
        "used_factors": used,
        "low_confidence_factors": low_conf,
        "contrib": contrib,
    }


def build_cn(conn: sqlite3.Connection, history_days: int = 90) -> dict:
    series_map = {f: load_series(conn, f) for f in st.FACTORS}

    # 参考交易日：用动量序列（最密、最长）作为日期轴
    axis = series_map.get("momentum")
    if axis is None or axis.empty:
        return {"value": None, "label": None, "stale": True, "history": []}
    ref_dates = list(axis.index)[-(history_days + 5):]

    history = []
    for d in ref_dates:
        c = composite_for_date(series_map, d)
        if c is not None:
            history.append({"date": d, "value": c["value"], "label": c["label"]})
    history = history[-history_days:]

    if not history:
        return {"value": None, "label": None, "stale": True, "history": []}

    latest_date = history[-1]["date"]
    latest = composite_for_date(series_map, latest_date)
    prev_close = history[-2]["value"] if len(history) >= 2 else None
    week_ago = history[-6]["value"] if len(history) >= 6 else None

    return {
        "value": latest["value"],
        "label": latest["label"],
        "prev_close": prev_close,
        "week_ago": week_ago,
        "coverage": latest["coverage"],
        "used_factors": latest["used_factors"],
        "low_confidence_factors": latest["low_confidence_factors"],
        "as_of": latest_date,
        "stale": False,
        "history": [{"date": h["date"], "value": h["value"]} for h in history],
    }


if __name__ == "__main__":
    import json

    conn = st.connect()
    st.init_db(conn)
    cn = build_cn(conn)
    conn.close()
    summary = {k: cn[k] for k in cn if k != "history"}
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"history points: {len(cn['history'])}")
    if cn["history"]:
        print("head:", cn["history"][0], " tail:", cn["history"][-1])
