"""美股 CNN Fear & Greed 抓取。

非官方端点，需伪装浏览器 UA。返回当前值 + 近 90 天历史。
客户端永不直连——只有本管道抓取。
"""
from __future__ import annotations

import datetime as dt

import requests

BASE_URL = "https://production.dataviz.cnn.io/index/fearandgreed/graphdata"
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Origin": "https://www.cnn.com",
    "Referer": "https://www.cnn.com/",
}


def fetch_cnn(history_days: int = 90, timeout: int = 20) -> dict:
    """抓取 CNN Fear & Greed。

    Returns dict: {value, label, prev_close, week_ago, history:[{date,value}], stale}
    抓取失败会抛异常，交由上层做 stale 兜底。
    """
    start = (dt.date.today() - dt.timedelta(days=history_days + 10)).isoformat()
    resp = requests.get(f"{BASE_URL}/{start}", headers=HEADERS, timeout=timeout)
    resp.raise_for_status()
    payload = resp.json()

    now = payload["fear_and_greed"]
    hist_raw = payload.get("fear_and_greed_historical", {}).get("data", [])

    history = []
    for entry in hist_raw:
        d = dt.datetime.fromtimestamp(entry["x"] / 1000, tz=dt.timezone.utc).date()
        history.append({"date": d.isoformat(), "value": round(float(entry["y"]), 2)})
    history.sort(key=lambda r: r["date"])
    history = history[-history_days:]

    return {
        "value": round(float(now["score"]), 2),
        "label": _normalize_label(now.get("rating", "")),
        "prev_close": round(float(now.get("previous_close", now["score"])), 2),
        "week_ago": round(float(now.get("previous_1_week", now["score"])), 2),
        "month_ago": round(float(now.get("previous_1_month", now["score"])), 2),
        "history": history,
        "stale": False,
    }


def _normalize_label(rating: str) -> str:
    return rating.strip().lower().replace(" ", "_") or "neutral"


if __name__ == "__main__":
    import json

    print(json.dumps(fetch_cnn(), ensure_ascii=False, indent=2)[:2000])
