"""因子历史本地存储 (SQLite)。

一因子一表：factor_<name>(trade_date PK, raw_value, updated_at)
外加 meta 表记录每因子回填覆盖情况。用于 rolling 分位数计算与断点续跑。
"""
from __future__ import annotations

import datetime as dt
import os
import sqlite3
from typing import Iterable, Optional

DB_PATH = os.path.join(os.path.dirname(__file__), "data", "factors.db")

# 因子名 -> (权重, 是否反向)。总权重 = 1.0（见 SDD 2.1）
FACTOR_META: dict[str, tuple[float, bool]] = {
    "breadth": (0.20, False),
    "limit_sentiment": (0.15, False),
    "momentum": (0.20, False),
    "turnover": (0.15, False),
    "high_low": (0.10, False),
    "leverage": (0.10, False),
    "volatility": (0.10, True),
}
FACTORS = list(FACTOR_META)


def _table(factor: str) -> str:
    if factor not in FACTOR_META:
        raise ValueError(f"未知因子: {factor}")
    return f"factor_{factor}"


def connect() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL;")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    for f in FACTORS:
        conn.execute(
            f"CREATE TABLE IF NOT EXISTS {_table(f)} ("
            "  trade_date TEXT PRIMARY KEY,"
            "  raw_value  REAL NOT NULL,"
            "  updated_at TEXT NOT NULL"
            ")"
        )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS meta ("
        "  factor TEXT PRIMARY KEY, first_date TEXT, last_date TEXT,"
        "  rows INTEGER, note TEXT, refreshed_at TEXT"
        ")"
    )
    conn.commit()


def upsert(conn: sqlite3.Connection, factor: str, trade_date: str, value: float) -> None:
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    conn.execute(
        f"INSERT INTO {_table(factor)}(trade_date, raw_value, updated_at) VALUES(?,?,?) "
        "ON CONFLICT(trade_date) DO UPDATE SET raw_value=excluded.raw_value, "
        "updated_at=excluded.updated_at",
        (trade_date, float(value), now),
    )


def upsert_many(conn: sqlite3.Connection, factor: str,
                rows: Iterable[tuple[str, float]]) -> int:
    n = 0
    for d, v in rows:
        if v is None:
            continue
        upsert(conn, factor, d, v)
        n += 1
    conn.commit()
    return n


def existing_dates(conn: sqlite3.Connection, factor: str) -> set[str]:
    cur = conn.execute(f"SELECT trade_date FROM {_table(factor)}")
    return {r[0] for r in cur.fetchall()}


def read_series(conn: sqlite3.Connection, factor: str,
                limit: Optional[int] = None) -> list[tuple[str, float]]:
    """按日期升序返回 (date, value)。limit 取最近 N 条。"""
    q = f"SELECT trade_date, raw_value FROM {_table(factor)} ORDER BY trade_date"
    rows = conn.execute(q).fetchall()
    if limit is not None:
        rows = rows[-limit:]
    return [(r[0], r[1]) for r in rows]


def refresh_meta(conn: sqlite3.Connection, factor: str, note: str = "") -> dict:
    cur = conn.execute(
        f"SELECT MIN(trade_date), MAX(trade_date), COUNT(*) FROM {_table(factor)}"
    )
    first, last, rows = cur.fetchone()
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    conn.execute(
        "INSERT INTO meta(factor, first_date, last_date, rows, note, refreshed_at) "
        "VALUES(?,?,?,?,?,?) ON CONFLICT(factor) DO UPDATE SET "
        "first_date=excluded.first_date, last_date=excluded.last_date, "
        "rows=excluded.rows, note=excluded.note, refreshed_at=excluded.refreshed_at",
        (factor, first, last, rows or 0, note, now),
    )
    conn.commit()
    return {"factor": factor, "first_date": first, "last_date": last, "rows": rows or 0}


def coverage(conn: sqlite3.Connection) -> list[dict]:
    out = []
    for f in FACTORS:
        out.append(refresh_meta(conn, f))
    return out
