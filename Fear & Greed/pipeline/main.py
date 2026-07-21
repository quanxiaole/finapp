"""生产数据管道入口：增量更新 → 合成 → 产出 index.json + 质量报告。

流程：
  1. 增量回填当日数据入 factors.db（单调用因子刷新 + 广度当日 + 涨跌停补最近缺口）
  2. 抓 CNN（失败则沿用上次值并标 stale）
  3. 读库合成 A股指数 + 90 天历史
  4. 数据质量检查（stale / low_confidence / 覆盖率 / 文件大小）
  5. 写 out/index.json + out/report.json；异常以非零退出码供 CI 告警

用法：
  python main.py                 # 日常增量运行
  python main.py --full-backfill # 触发一次完整回填（限频较久）
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os

import backfill as bf
import compute
import storage as st
from fetch_cnn import fetch_cnn

OUT_DIR = os.path.join(os.path.dirname(__file__), "out")
INDEX_PATH = os.path.join(OUT_DIR, "index.json")
REPORT_PATH = os.path.join(OUT_DIR, "report.json")

MAX_BYTES = 50 * 1024
MIN_COVERAGE = 0.5  # A股因子覆盖率低于此值 → 告警


def _load_prev_index() -> dict:
    if os.path.exists(INDEX_PATH):
        try:
            with open(INDEX_PATH, encoding="utf-8") as fp:
                return json.load(fp)
        except Exception:  # noqa: BLE001
            return {}
    return {}


def incremental_update(conn, full: bool) -> None:
    bf.backfill_single_call(conn)
    bf.backfill_breadth_today(conn)
    bf.backfill_limit_sentiment(conn, limit_td=500 if full else 10, sleep=0.25)


def build_us(prev: dict, warnings: list[str]) -> dict:
    try:
        us = fetch_cnn()
        return {
            "value": us["value"], "label": us["label"],
            "prev_close": us["prev_close"], "week_ago": us["week_ago"],
            "stale": False, "history": us["history"],
        }
    except Exception as e:  # noqa: BLE001
        warnings.append(f"CNN 抓取失败，沿用上次值: {e!r}")
        prev_us = prev.get("indices", {}).get("us", {})
        prev_hist = prev.get("history", {}).get("us", [])
        return {
            "value": prev_us.get("value"), "label": prev_us.get("label"),
            "prev_close": prev_us.get("prev_close"), "week_ago": prev_us.get("week_ago"),
            "stale": True, "history": prev_hist,
        }


def quality_checks(index: dict, warnings: list[str]) -> list[str]:
    us = index["indices"]["us"]
    cn = index["indices"]["cn"]

    if us.get("stale"):
        warnings.append("US 指数为 stale")
    if us.get("value") is not None and not (0 <= us["value"] <= 100):
        warnings.append(f"US 数值越界: {us['value']}")

    if cn.get("value") is None:
        warnings.append("CN 指数合成失败（无可用因子）")
    else:
        if not (0 <= cn["value"] <= 100):
            warnings.append(f"CN 数值越界: {cn['value']}")
        if cn.get("coverage", 0) < MIN_COVERAGE:
            warnings.append(f"CN 因子覆盖率过低: {cn.get('coverage')}")
        if cn.get("low_confidence_factors"):
            warnings.append(f"CN 低置信因子: {cn['low_confidence_factors']}")

    size = len(json.dumps(index, ensure_ascii=False).encode("utf-8"))
    if size > MAX_BYTES:
        warnings.append(f"index.json 超过 {MAX_BYTES}B: {size}B")
    return warnings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--full-backfill", action="store_true")
    ap.add_argument("--skip-update", action="store_true",
                    help="跳过增量回填，直接用现有库合成（调试用）")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    now = dt.datetime.now(dt.timezone(dt.timedelta(hours=8)))
    warnings: list[str] = []
    prev = _load_prev_index()

    conn = st.connect()
    st.init_db(conn)
    if not args.skip_update:
        incremental_update(conn, full=args.full_backfill)

    cn = compute.build_cn(conn)
    coverage = st.coverage(conn)
    conn.close()

    us = build_us(prev, warnings)

    index = {
        "schema_version": 1,
        "updated_at": now.isoformat(timespec="seconds"),
        "indices": {
            "us": {k: us[k] for k in ("value", "label", "prev_close", "week_ago", "stale")},
            "cn": {
                "value": cn.get("value"), "label": cn.get("label"),
                "prev_close": cn.get("prev_close"), "week_ago": cn.get("week_ago"),
                "coverage": cn.get("coverage"),
                "as_of": cn.get("as_of"), "stale": cn.get("stale", False),
            },
        },
        "history": {
            "us": us.get("history", [])[-90:],
            "cn": cn.get("history", []),
        },
    }

    quality_checks(index, warnings)

    report = {
        "generated_at": now.isoformat(timespec="seconds"),
        "warnings": warnings,
        "cn_used_factors": cn.get("used_factors"),
        "cn_low_confidence": cn.get("low_confidence_factors"),
        "factor_coverage": coverage,
    }

    with open(INDEX_PATH, "w", encoding="utf-8") as fp:
        json.dump(index, fp, ensure_ascii=False, indent=2)
    with open(REPORT_PATH, "w", encoding="utf-8") as fp:
        json.dump(report, fp, ensure_ascii=False, indent=2)

    print(f"US: {index['indices']['us']['value']} ({index['indices']['us']['label']})"
          f" stale={index['indices']['us']['stale']}")
    print(f"CN: {index['indices']['cn']['value']} ({index['indices']['cn']['label']})"
          f" coverage={index['indices']['cn']['coverage']} as_of={index['indices']['cn']['as_of']}")
    print(f"history: us={len(index['history']['us'])} cn={len(index['history']['cn'])}")
    if warnings:
        print("⚠️ 告警:")
        for w in warnings:
            print(f"   - {w}")

    # 两个市场都拿不到值 → 非零退出，触发 CI 告警
    both_dead = index["indices"]["us"]["value"] is None and index["indices"]["cn"]["value"] is None
    return 1 if both_dead else 0


if __name__ == "__main__":
    raise SystemExit(main())
