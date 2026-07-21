"""M1b 单元测试：分位归一化、打标签、point-in-time 合成。

运行：python test_compute.py   （无需 pytest）
"""
from __future__ import annotations

import pandas as pd

from compute import MIN_WINDOW, composite_for_date, factor_score_asof
from index_utils import clamp, label_for, percentile_score


def test_percentile_basic():
    hist = list(range(1, 101))  # 1..100
    assert percentile_score(hist, 50) == 50.0
    assert percentile_score(hist, 100) == 100.0
    assert percentile_score(hist, 1) == 1.0
    # reverse：高值 → 低分（波动率语义）
    assert percentile_score(hist, 100, reverse=True) == 0.0
    assert percentile_score(hist, 1, reverse=True) == 99.0


def test_clamp_and_label():
    assert clamp(-5) == 0.0 and clamp(150) == 100.0
    assert label_for(10) == "extreme_fear"
    assert label_for(30) == "fear"
    assert label_for(50) == "neutral"
    assert label_for(65) == "greed"
    assert label_for(90) == "extreme_greed"


def _series(vals, start="2020-01-01"):
    idx = pd.date_range(start, periods=len(vals)).strftime("%Y-%m-%d")
    return pd.Series(list(vals), index=idx)


def test_factor_score_asof_window_and_reverse():
    s = _series(range(1, 121))  # 120 天，值 1..120
    last = s.index[-1]
    # 最新值 120 是历史最高 → 正向得满分附近
    r = factor_score_asof(s, last, reverse=False)
    assert r["low_confidence"] is False and r["score"] == 100.0
    # 反向：最高值 → 最低分
    r_rev = factor_score_asof(s, last, reverse=True)
    assert r_rev["score"] == 0.0


def test_low_confidence_below_min_window():
    s = _series(range(1, MIN_WINDOW))  # 少于 MIN_WINDOW
    r = factor_score_asof(s, s.index[-1], reverse=False)
    assert r["low_confidence"] is True and r["score"] is None


def test_composite_redistributes_weight_on_missing():
    # 只提供两个因子，验证权重按覆盖归一化、缺失不报错
    date = "2020-06-01"
    long_vals = range(1, 200)
    smap = {
        "momentum": _series(long_vals),
        "volatility": _series(long_vals),
    }
    # 对齐日期：确保 date 在索引内
    date = smap["momentum"].index[100]
    c = composite_for_date(smap, date)
    assert c is not None
    assert set(c["used_factors"]) == {"momentum", "volatility"}
    assert 0.0 <= c["value"] <= 100.0
    # coverage = 两因子权重和（0.20 + 0.10）
    assert abs(c["coverage"] - 0.30) < 1e-9


def _run():
    tests = [v for k, v in globals().items() if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        t()
        print(f"  ✅ {t.__name__}")
        passed += 1
    print(f"\n{passed}/{len(tests)} 测试通过")


if __name__ == "__main__":
    _run()
