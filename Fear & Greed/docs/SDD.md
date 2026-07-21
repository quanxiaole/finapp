# 恐慌指数 — 系统设计与任务分解 (SDD / WBS)

> 本文件是持续维护的设计 + 任务文档。方案背景与可行性见 [`../one-pager.md`](../one-pager.md)。
> 状态图例：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 已完成

日期：2026-07-21 起 · 范围：M1 数据管道与核心指数（深拆）+ M2–M4 骨架

---

## 0. 架构总览

```
① 算 (GitHub Actions 临时容器, cron 错峰)
   Python + AKShare/CNN → 分位合成 → index.json
        │ commit / upload
        ▼
② 存 (静态托管 + CDN: GitHub Pages / jsDelivr, 接法A)
        │ HTTPS GET (CDN 缓存)
        ▼
③ 取 (iOS App: SwiftUI + WidgetKit, 无后端, 只消费一个 JSON)
```

设计原则：无服务器、零月费、客户端极薄。所有指数计算在管道完成。

---

## 1. 全局任务骨架 (M1 → M4)

```mermaid
graph TD
  M1["M1 数据管道与核心指数"] --> M2["M2 iOS App MVP"]
  M2 --> M3["M3 打磨与上架"]
  M3 --> M4["M4 验证期"]
  M1 --> M1a["M1a 历史回填"]
  M1 --> M1b["M1b 指数计算正式化"]
  M1 --> M1c["M1c 管道产出与调度"]
  M1 --> M1d["M1d CI/CD 与托管"]
  M1a --> M1b --> M1c --> M1d
```

- **M1 数据管道与核心指数**（本文件深拆）— 唯一护城河，最先做。
- **M2 iOS App MVP** — SwiftUI 仪表盘 + Small/Medium Widget + App Group 缓存 + 消费 index.json。验收：真机能显示双市场当前值。
- **M3 打磨与上架** — 历史图表(Swift Charts)、锁屏组件、Tip Jar(StoreKit2)、中英素材、过审。验收：上架美区/港区。
- **M4 验证期** — TestFlight + 正式版，收集 7 日留存 / 自然传播 / 自用 三项指标，4 周后决定是否备案进中国区。

---

## 2. 当前节点深拆：A股核心指数算法 + 数据管道 (M1)

### 2.0 现状基线（已完成）
- `pipeline/fetch_cnn.py` — CNN 抓取，已跑通（当前值 + 90 天历史）。
- `pipeline/fetch_cn.py` — 七因子取数 + 加权合成，实跑覆盖率 100%，含多源容错。
- `pipeline/index_utils.py` — 分位归一化 (`percentile_score`) + 打标签 (`label_for`)。
- `pipeline/main.py` — 编排产出 `out/index.json` + `out/report.json`。
- 环境：`.venv312`（uv 装的独立 Python 3.12；系统仅 3.9，不满足最新 akshare）。

**核心缺口**：`breadth`/`limit_sentiment` 为当日快照（分位窗口=0）、`leverage` 历史仅 22 天、`cn.history` 为空。→ M1a 解阻塞。

### 2.1 因子定义与权重（启发式，v1）

| 因子 | 定义 | 权重 | 方向 |
|---|---|---|---|
| breadth 市场广度 | 沪深涨跌家数比（5 日平滑） | 20% | 正 |
| limit_sentiment 涨跌停 | 涨停 /(涨停+跌停) | 15% | 正 |
| momentum 指数动量 | 沪深300 相对 125 日均线偏离 | 20% | 正 |
| turnover 成交热度 | 两市成交额 / 60 日均值 | 15% | 正 |
| high_low 新高新低 | 净新高（近似 52 周） | 10% | 正 |
| leverage 杠杆情绪 | 融资余额 5 日变化率 | 10% | 正 |
| volatility 波动率 | QVIX（`index_option_50etf_qvix`） | 10% | 反 |

归一化：每因子先算 rolling 2 年历史分位（0–100），反向因子取 `100 - 分位`，再按权重合成；缺失因子按现有权重归一化降级。权重为启发式，App 内如实标注，后续按回测校准。

### 2.2 M1a 历史回填（最高优先级）

逐因子数据源与回填策略（2026-07-21 `probe_sources.py` 实测确认）：

- **涨跌停** `limit_sentiment`：⚠️ 实测 `stock_zt_pool_dtgc_em`（跌停池）**只提供最近约 30 交易日**（更早抛 `ValueError`）。→ 无法回填 2 年，**降为 go-forward 因子**（现只 seed 最近约 30 天，逐日累积）。回填由新到旧、命中上限即停。
- **市场广度** `breadth`：❌ 确认无历史接口（`stock_market_activity_legu` 仅快照）。**决策：go-forward 每日累积快照入库**；后续如需历史可再用全A日线批量重建。
- **go-forward 因子的降级**：`breadth` 与 `limit_sentiment` 在窗口 < 60 日前标 `low_confidence` 并按权重重分配，不阻塞其余 5 个有 2 年历史的因子（合成从第一天即可用，约 65% 覆盖，约 60 交易日后升至 100%）。
- **动量 / 成交** `momentum`/`turnover`：✅ `index_zh_a_hist(000300)` 有多年历史；东财偶发断连 → 必须带重试 + 新浪 `stock_zh_index_daily` 兜底（已实测有效）。
- **新高新低** `high_low`：✅ `stock_a_high_low_statistics(all)` 一次返回 500 行、覆盖 2024-06→2026-07（满 2 年），含 high120/low120。
- **杠杆** `leverage`：✅ `stock_margin_sse` 一次调用返回 504 行满 2 年（沪市，`信用交易日期`+`融资余额`）。深市 `stock_margin_szse` 为可选增强（本次瞬时断连，需重试）。
- **波动率** `volatility`：✅ QVIX `index_option_50etf_qvix` 一次返回 2771 行（2015→2026）。

- 落地存储：`pipeline/data/factors.db`（SQLite），一因子一表（见 2.5 schema）。
- 回填脚本 `pipeline/backfill.py`：交易日循环 + 限频 sleep + 重试（网络错误退避、`ValueError` 不重试）+ 断点续跑（已入库日期跳过）；产出每因子覆盖率报告。
- **验收（实际达成）**：5 个因子有 2 年+ 历史（momentum/turnover 十余年、volatility 2015 起、high_low 500 日、leverage 587 日）；2 个 go-forward 因子（breadth/limit_sentiment）有明确记录与降级说明。

### 2.3 M1b 指数计算正式化
- 分位数改为读取 `factors.db`（rolling 2 年），替换现有快照线性映射。
- 加权合成 + 缺失降级（保留现逻辑，补单元测试覆盖 `percentile_score`/`label_for`/`compose`）。
- 冷启动/异常/stale 规则成文：历史 < N 日的因子标 `low_confidence`，不参与或降权。
- **验收**：`out/index.json` 的 `cn.history` 能产出近 90 天日频序列；用历史大跌/大涨日目视对照合理。

### 2.4 M1c 管道产出与调度
- 定稿 `index.json` schema（补齐 `cn.prev_close/week_ago/history`），与 iOS 端字段对齐。
- 错峰调度：A股盘中（09:30–15:00 CST）每 30–60 分钟刷宽度/动量/成交；盘后日结；美股时段（约 21:30–05:00 CST）刷 CNN。写成 cron 规格。
- 数据质量告警：抓取失败、因子缺失、数值越界 → 日志 + `stale`/`low_confidence` 标记。
- **验收**：单文件 < 50KB，字段与 one-pager 2.2 节 JSON 一致。

### 2.5 存储 schema（SQLite）

```
每因子一表，统一结构：
CREATE TABLE factor_<name> (
  trade_date TEXT PRIMARY KEY,   -- YYYY-MM-DD
  raw_value  REAL NOT NULL,      -- 因子原始值
  updated_at TEXT NOT NULL       -- 入库时间
);
-- 元数据表记录每因子回填覆盖情况
CREATE TABLE meta (
  factor TEXT PRIMARY KEY,
  first_date TEXT, last_date TEXT, rows INTEGER, note TEXT
);
```

### 2.6 M1d CI/CD 与静态托管（接法 A 优先）
- `.github/workflows/pipeline.yml`：cron 错峰（07:35 UTC A股盘后 / 22:05 UTC 美股盘后）→ setup-python 3.12 → 装依赖 → `python main.py` → commit `pipeline/out/index.json` + `pipeline/data/factors.db` 回仓库。
- `factors.db` 一并提交：保留 go-forward 因子（breadth/limit_sentiment）的每日累积，避免重建丢失。
- 对外 URL（零配置，公开仓库即可）：
  - jsDelivr：`https://cdn.jsdelivr.net/gh/<user>/<repo>@main/pipeline/out/index.json`
  - 或 GitHub Pages（需开 Pages）。
- 保活：每日 commit 天然规避「公开仓库 60 天无活动自动禁用」。
- **本地验收（已完成）**：CI 入口命令 `python main.py` 本地实跑通过（增量幂等、US+CN 合成、90 天历史、无告警）；YAML 合法。
- **待远端激活**：需把仓库推到 GitHub（当前仅本地 git，无 remote）后，Actions 才会真正按 cron 运行并 push。

---

## 3. 不在当前范围
- iOS 代码（M2 起）、Tip Jar、上架素材、港股 Phase 2、APNs 推送。
- 权重回测调参（v1 用启发式，M1b 仅做合理性校验，不做最优化）。

## 4. 任务清单（对应 plan todos）
- [x] M1a 逐因子数据源与回填可行性核实（`probe_sources.py`）
- [x] M1a SQLite 存储 schema（`storage.py`）
- [x] M1a backfill.py + 回填（5 因子 2 年+；breadth/limit go-forward）
- [x] M1b 分位数改读回填库 + 测试（`compute.py` + `test_compute.py` 5/5）
- [x] M1b 产出 cn.history 90 天 + 合理性校验（`validate.py`，corr=+0.78）
- [x] M1c index.json schema + 错峰调度 + 数据质量告警（`main.py`）
- [x] M1d GitHub Actions + 静态托管（`.github/workflows/pipeline.yml`，本地验收通过）

## 5. 模块索引
- `pipeline/storage.py` — SQLite 存储（一因子一表 + meta）
- `pipeline/net.py` — 网络重试（网络错误退避、ValueError 不重试）
- `pipeline/factor_defs.py` — 因子原始值单一定义源（回填/实时共用）
- `pipeline/backfill.py` — 历史回填（限频/重试/断点续跑/go-forward）
- `pipeline/compute.py` — as-of 滚动分位合成引擎
- `pipeline/fetch_cnn.py` — CNN Fear & Greed 抓取
- `pipeline/main.py` — 生产入口（增量→合成→index.json + 质量报告）
- `pipeline/validate.py` — 指数合理性校验
- `pipeline/test_compute.py` — 单元测试
- `pipeline/probe_sources.py` — 数据源可行性探测
