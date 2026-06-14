#!/usr/bin/env python3
"""Google Trends collector — persists interest scores to ai_radar.trend_signals (T-363)."""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg2
import yaml
from pytrends.request import TrendReq


def load_config(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def latest_interest(pytrends: TrendReq, term: str, geo: str, window: str) -> int:
    pytrends.build_payload([term], geo=geo, timeframe=window)
    df = pytrends.interest_over_time()
    if df is None or df.empty or term not in df.columns:
        return 0
    series = df[term].dropna()
    if series.empty:
        return 0
    return int(series.iloc[-1])


def fetch_with_retry(
    pytrends: TrendReq,
    term: str,
    geo: str,
    window: str,
    max_retries: int,
) -> int:
    delay = 2.0
    last_err: Exception | None = None
    for attempt in range(1, max_retries + 1):
        try:
            return latest_interest(pytrends, term, geo, window)
        except Exception as exc:  # noqa: BLE001 — pytrends raises varied HTTP errors
            last_err = exc
            if attempt >= max_retries:
                break
            time.sleep(delay)
            delay = min(delay * 2, 30.0)
    raise RuntimeError(f"trends fetch failed for {term!r}: {last_err}") from last_err


def main() -> int:
    config_path = Path(os.environ.get("TRENDS_CONFIG_PATH", "/config/trends-queries.yaml"))
    if not config_path.is_file():
        print(f"config missing: {config_path}", file=sys.stderr)
        return 2

    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL required", file=sys.stderr)
        return 2

    cfg = load_config(config_path)
    geo = str(cfg.get("geo", "US"))
    window = str(cfg.get("time_window", "now 7-d"))
    sleep_s = float(cfg.get("sleep_seconds", 3))
    max_retries = int(cfg.get("max_retries", 3))
    queries = cfg.get("queries") or []
    if not queries:
        print("no queries configured", file=sys.stderr)
        return 2

    pytrends = TrendReq(hl="en-US", tz=360)
    inserted = 0
    errors = 0
    collected_at = datetime.now(timezone.utc)

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            for item in queries:
                term = str(item.get("term", "")).strip()
                if not term:
                    continue
                topic = str(item.get("topic", "general"))
                item_geo = str(item.get("geo", geo))
                item_window = str(item.get("time_window", window))
                try:
                    score = fetch_with_retry(
                        pytrends, term, item_geo, item_window, max_retries
                    )
                    meta = {"topic": topic, "source": "pytrends"}
                    cur.execute(
                        """
                        INSERT INTO ai_radar.trend_signals
                            (term, geo, time_window, interest_score, collected_at, metadata_json)
                        VALUES (%s, %s, %s, %s, %s, %s::jsonb)
                        """,
                        (
                            term,
                            item_geo,
                            item_window,
                            score,
                            collected_at,
                            json.dumps(meta),
                        ),
                    )
                    inserted += 1
                    print(f"ok term={term!r} score={score} geo={item_geo}")
                except Exception as exc:  # noqa: BLE001
                    errors += 1
                    print(f"error term={term!r}: {exc}", file=sys.stderr)
                time.sleep(sleep_s)
        conn.commit()

    print(f"summary inserted={inserted} errors={errors} queries={len(queries)}")
    return 1 if inserted == 0 and errors > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
