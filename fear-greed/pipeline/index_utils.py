"""指数归一化与打标签工具。"""
from __future__ import annotations

from typing import Sequence


def clamp(x: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, x))


def percentile_score(series: Sequence[float], value: float, reverse: bool = False) -> float:
    """把 value 映射为它在 series 历史里的分位数（0–100）。

    reverse=True 用于「越高越恐慌」的因子（如波动率），令高值 → 低分。
    这是 CNN / 主流 A股实现共用的做法：避免绝对阈值调参。
    """
    hist = [v for v in series if v is not None]
    if not hist:
        return 50.0
    below = sum(1 for v in hist if v <= value)
    pct = 100.0 * below / len(hist)
    return clamp(100.0 - pct if reverse else pct)


LABELS = [
    (25, "extreme_fear"),
    (45, "fear"),
    (55, "neutral"),
    (75, "greed"),
    (101, "extreme_greed"),
]


def label_for(value: float) -> str:
    for threshold, name in LABELS:
        if value < threshold:
            return name
    return "extreme_greed"
