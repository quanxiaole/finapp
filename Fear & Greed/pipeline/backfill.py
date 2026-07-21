"""M1a 历史回填：把各因子历史写入 factors.db。

- 单次调用即得全历史的因子（动量/成交/新高新低/杠杆/波动率）：一把拉全、幂等 upsert。
- 涨跌停：按交易日循环，跳过已入库日期（断点续跑），限频 + 重试。
- 市场广度：无历史接口，仅追加当日快照（go-forward 累积）。

用法：
  python backfill.py                 # 单调用因子全回填 + 涨跌停默认最近 500 交易日
  python backfill.py --limit-td 30   # 涨跌停只回填最近 30 交易日（快速验证/增量）
  python backfill.py --skip-limit    # 跳过涨跌停逐日回填
"""
from __future__ import annotations

import argparse
import datetime as dt
import time

import factor_defs as fd
import storage as st


def backfill_single_call(conn) -> None:
    hs = fd.hs300_hist()  # 动量/成交共用一次拉取
    jobs = {
        "momentum": lambda: fd.series_momentum(hs),
        "turnover": lambda: fd.series_turnover(hs),
        "high_low": fd.series_high_low,
        "leverage": fd.series_leverage,
        "volatility": fd.series_volatility,
    }
    for name, fn in jobs.items():
        try:
            rows = fn()
            n = st.upsert_many(conn, name, rows)
            m = st.refresh_meta(conn, name)
            print(f"  ✅ {name:<16} 写入 {n:>5} 行  span {m['first_date']}→{m['last_date']}")
        except Exception as e:  # noqa: BLE001
            print(f"  ❌ {name:<16} {e!r}")


def backfill_limit_sentiment(conn, limit_td: int, sleep: float = 0.3) -> None:
    end = dt.date.today()
    start = end - dt.timedelta(days=int(limit_td * 1.7) + 30)  # 交易日≈日历日*0.7
    try:
        days = fd.trading_days(start, end)[-limit_td:]
    except Exception as e:  # noqa: BLE001
        print(f"  ❌ 交易日历获取失败: {e!r}")
        return

    have = st.existing_dates(conn, "limit_sentiment")
    todo = [d for d in days if f"{d[:4]}-{d[4:6]}-{d[6:]}" not in have]
    print(f"  涨跌停：目标 {len(days)} 交易日，已有 {len(days)-len(todo)}，待回填 {len(todo)}")
    print("  注意：跌停股池接口仅提供最近约 30 交易日 → limit_sentiment 实为 go-forward 因子")

    done = 0
    # 由新到旧回填；命中「历史不可得」(ValueError) 即停止，避免无谓请求
    for ymd in reversed(todo):
        iso = f"{ymd[:4]}-{ymd[4:6]}-{ymd[6:]}"
        try:
            ratio = fd.day_limit_sentiment(ymd)
            if ratio is not None:
                st.upsert(conn, "limit_sentiment", iso, ratio)
                done += 1
        except ValueError as e:
            print(f"    ⏹ 到达接口历史上限（{iso}）：{e}")
            break
        except Exception as e:  # noqa: BLE001
            print(f"    ⚠️ {iso} 网络跳过: {e!r}")
        time.sleep(sleep)
    conn.commit()
    m = st.refresh_meta(conn, "limit_sentiment", note="跌停池30日上限→go-forward累积")
    print(f"  ✅ limit_sentiment 新增 {done} 行，现有 {m['rows']} 行  "
          f"span {m['first_date']}→{m['last_date']}")


def backfill_breadth_today(conn) -> None:
    """广度无历史，追加当日快照（go-forward）。"""
    try:
        ratio = fd.snapshot_breadth()
        today = dt.date.today().strftime("%Y-%m-%d")
        st.upsert(conn, "breadth", today, ratio)
        m = st.refresh_meta(conn, "breadth", note="go-forward 累积，无历史回填")
        print(f"  ✅ breadth 追加当日快照 {today}={ratio:.3f}（累积 {m['rows']} 行）")
    except Exception as e:  # noqa: BLE001
        print(f"  ❌ breadth {e!r}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit-td", type=int, default=500, help="涨跌停回填最近 N 交易日")
    ap.add_argument("--skip-limit", action="store_true")
    ap.add_argument("--sleep", type=float, default=0.3)
    args = ap.parse_args()

    conn = st.connect()
    st.init_db(conn)

    print("[1/3] 单调用因子全回填")
    backfill_single_call(conn)

    print("[2/3] 市场广度当日快照")
    backfill_breadth_today(conn)

    if not args.skip_limit:
        print(f"[3/3] 涨跌停逐日回填（最近 {args.limit_td} 交易日）")
        backfill_limit_sentiment(conn, args.limit_td, sleep=args.sleep)
    else:
        print("[3/3] 跳过涨跌停回填")

    print("\n=== 回填覆盖率 ===")
    for m in st.coverage(conn):
        print(f"  {m['factor']:<16} rows={m['rows']:>5}  {m['first_date']} → {m['last_date']}")
    conn.close()


if __name__ == "__main__":
    main()
