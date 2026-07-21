"""M1b 合理性校验：把自研 A股指数与沪深300 对照，检查方向与极值是否合理。

判据（非精确择时，只验证无符号错误/明显异常）：
  1. 取值恒在 0–100；
  2. 与沪深300 近 20 日收益率 同期正相关（上涨→偏贪婪）；
  3. 指数最低的日子应落在阶段性低点附近、最高的落在高点附近（人工目视）。
运行：python validate.py
"""
from __future__ import annotations

import pandas as pd

import compute
import factor_defs as fd
import storage as st


def main() -> None:
    conn = st.connect()
    st.init_db(conn)
    cn = compute.build_cn(conn, history_days=250)
    conn.close()

    hist = pd.DataFrame(cn["history"])
    hist["date"] = pd.to_datetime(hist["date"])
    hist = hist.set_index("date").sort_index()
    print(f"CN 指数序列: {len(hist)} 天  {hist.index[0].date()} → {hist.index[-1].date()}")
    print(f"  取值范围: min={hist['value'].min():.1f}  max={hist['value'].max():.1f}"
          f"  mean={hist['value'].mean():.1f}")
    assert hist["value"].between(0, 100).all(), "越界！"
    print("  ✅ 取值均在 0–100")

    # 沪深300 对照
    hs = fd.hs300_hist()
    hs["date"] = pd.to_datetime(hs["date"])
    hs = hs.set_index("date").sort_index()
    hs["ret20"] = hs["close"].astype(float).pct_change(20)

    join = hist.join(hs[["close", "ret20"]], how="inner").dropna()
    corr = join["value"].corr(join["ret20"])
    print(f"\n  corr(指数, 沪深300 近20日收益) = {corr:+.3f}  "
          f"({'✅ 正相关，方向正确' if corr > 0 else '❌ 方向可疑'})")

    print("\n  指数最低 5 天（应接近阶段低点）:")
    for d, r in join.nsmallest(5, "value").iterrows():
        print(f"    {d.date()}  指数={r['value']:.1f}  HS300={r['close']:.0f}")
    print("  指数最高 5 天（应接近阶段高点）:")
    for d, r in join.nlargest(5, "value").iterrows():
        print(f"    {d.date()}  指数={r['value']:.1f}  HS300={r['close']:.0f}")


if __name__ == "__main__":
    main()
