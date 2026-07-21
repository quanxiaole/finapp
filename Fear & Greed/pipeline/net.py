"""网络容错：AKShare/东财接口偶发连接重置，统一重试退避。"""
from __future__ import annotations

import time
from typing import Callable, TypeVar

T = TypeVar("T")


def with_retry(fn: Callable[[], T], tries: int = 4, base_delay: float = 1.5,
               label: str = "", no_retry: tuple[type, ...] = (ValueError,)) -> T:
    """指数退避重试。

    no_retry 中的异常类型（默认 ValueError，如「只能获取最近30天」这类
    确定性业务错误）立即抛出、不重试，避免无谓耗时。
    """
    last: Exception | None = None
    for i in range(tries):
        try:
            return fn()
        except no_retry:
            raise
        except Exception as e:  # noqa: BLE001
            last = e
            if i < tries - 1:
                time.sleep(base_delay * (2 ** i))
    assert last is not None
    raise last
