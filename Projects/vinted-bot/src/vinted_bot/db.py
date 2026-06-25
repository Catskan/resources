"""Schema SQLite + helpers de persistence pour tracker l'activité du bot.

Tables :
  - articles            : cache des items du dressing (sync depuis Vinted API)
  - republications      : historique (item_id, timestamp, success)
  - optimizations       : historique propositions/applications LLM
  - daily_counters      : compteur quotidien (date, n_republications, is_off_day)
"""

from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path

from .config import settings

SCHEMA = """
CREATE TABLE IF NOT EXISTS articles (
    id                INTEGER PRIMARY KEY,
    vinted_item_id    INTEGER NOT NULL UNIQUE,
    title             TEXT NOT NULL,
    description       TEXT,
    price_cents       INTEGER,
    last_seen_at      TEXT NOT NULL,
    last_bumped_at    TEXT,
    last_optimized_at TEXT,
    is_active         INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_articles_active ON articles(is_active, last_bumped_at);

CREATE TABLE IF NOT EXISTS republications (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    old_item_id   INTEGER NOT NULL,
    new_item_id   INTEGER,
    ran_at        TEXT NOT NULL,
    success       INTEGER NOT NULL,
    error         TEXT
);
CREATE INDEX IF NOT EXISTS idx_republications_ran_at ON republications(ran_at);

CREATE TABLE IF NOT EXISTS optimizations (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    vinted_item_id INTEGER NOT NULL,
    title_before   TEXT NOT NULL,
    title_after    TEXT NOT NULL,
    desc_before    TEXT,
    desc_after     TEXT,
    proposed_at    TEXT NOT NULL,
    applied_at     TEXT,
    user_action    TEXT
);

CREATE TABLE IF NOT EXISTS daily_counters (
    date              TEXT PRIMARY KEY,
    n_republications  INTEGER NOT NULL DEFAULT 0,
    is_off_day        INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS kv_state (
    key    TEXT PRIMARY KEY,
    value  TEXT NOT NULL
);
"""


def init_db(path: Path | None = None) -> None:
    path = path or settings.db_path
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(path) as conn:
        conn.executescript(SCHEMA)


@contextmanager
def connect(path: Path | None = None):
    """Connexion SQLite avec row_factory + auto-commit en context manager."""
    path = path or settings.db_path
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────
# Articles : sync depuis Vinted
# ─────────────────────────────────────────────────────────────


def upsert_article(
    conn: sqlite3.Connection,
    vinted_item_id: int,
    title: str,
    price_cents: int | None = None,
    is_active: bool = True,
) -> None:
    """Upsert un article. last_seen_at = now."""
    now = datetime.now().isoformat(timespec="seconds")
    conn.execute(
        """
        INSERT INTO articles (vinted_item_id, title, price_cents, last_seen_at, is_active)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(vinted_item_id) DO UPDATE SET
            title         = excluded.title,
            price_cents   = excluded.price_cents,
            last_seen_at  = excluded.last_seen_at,
            is_active     = excluded.is_active
        """,
        (vinted_item_id, title, price_cents, now, 1 if is_active else 0),
    )


def mark_inactive(conn: sqlite3.Connection, vinted_item_ids: list[int]) -> None:
    """Marque comme inactifs des items (= disparus du wardrobe Vinted)."""
    if not vinted_item_ids:
        return
    placeholders = ",".join(["?"] * len(vinted_item_ids))
    conn.execute(
        f"UPDATE articles SET is_active = 0 WHERE vinted_item_id IN ({placeholders})",
        vinted_item_ids,
    )


def list_eligible_articles(
    conn: sqlite3.Connection, min_days_since_bump: int
) -> list[sqlite3.Row]:
    """Articles actifs pas bumped dans les N derniers jours."""
    cutoff = (datetime.now() - timedelta(days=min_days_since_bump)).isoformat(
        timespec="seconds"
    )
    return conn.execute(
        """
        SELECT vinted_item_id, title, last_bumped_at
        FROM articles
        WHERE is_active = 1
          AND (last_bumped_at IS NULL OR last_bumped_at < ?)
        """,
        (cutoff,),
    ).fetchall()


def update_bumped_at(
    conn: sqlite3.Connection, old_id: int, new_id: int | None = None
) -> None:
    """Met à jour last_bumped_at après un bump réussi. Si new_id, remplace old_id."""
    now = datetime.now().isoformat(timespec="seconds")
    if new_id is not None and new_id != old_id:
        # On a republié : l'ancien item_id n'existe plus, le nouveau prend le relais
        conn.execute(
            """
            UPDATE articles
            SET vinted_item_id = ?, last_bumped_at = ?, last_seen_at = ?
            WHERE vinted_item_id = ?
            """,
            (new_id, now, now, old_id),
        )
    else:
        conn.execute(
            "UPDATE articles SET last_bumped_at = ?, last_seen_at = ? WHERE vinted_item_id = ?",
            (now, now, old_id),
        )


# ─────────────────────────────────────────────────────────────
# Republications : historique
# ─────────────────────────────────────────────────────────────


def record_republication(
    conn: sqlite3.Connection,
    old_item_id: int,
    new_item_id: int | None,
    success: bool,
    error: str | None = None,
) -> None:
    now = datetime.now().isoformat(timespec="seconds")
    conn.execute(
        """
        INSERT INTO republications (old_item_id, new_item_id, ran_at, success, error)
        VALUES (?, ?, ?, ?, ?)
        """,
        (old_item_id, new_item_id, now, 1 if success else 0, error),
    )


def get_last_successful_bump_time(conn: sqlite3.Connection) -> datetime | None:
    """Datetime du dernier bump réussi (toutes confondues)."""
    row = conn.execute(
        "SELECT ran_at FROM republications WHERE success = 1 ORDER BY ran_at DESC LIMIT 1"
    ).fetchone()
    if not row:
        return None
    return datetime.fromisoformat(row["ran_at"])


# ─────────────────────────────────────────────────────────────
# Daily counters
# ─────────────────────────────────────────────────────────────


def get_or_create_today_counter(conn: sqlite3.Connection, today: str | None = None) -> sqlite3.Row:
    """Récupère (ou crée) la row du daily_counter pour aujourd'hui.

    À la création, tire au sort si is_off_day (proba = OFF_DAYS_PER_WEEK / 7).
    """
    import random

    today = today or datetime.now().date().isoformat()
    row = conn.execute(
        "SELECT date, n_republications, is_off_day FROM daily_counters WHERE date = ?",
        (today,),
    ).fetchone()
    if row:
        return row

    proba_off = settings.bump_off_days_per_week / 7.0
    is_off = 1 if random.random() < proba_off else 0
    conn.execute(
        "INSERT INTO daily_counters (date, n_republications, is_off_day) VALUES (?, 0, ?)",
        (today, is_off),
    )
    return conn.execute(
        "SELECT date, n_republications, is_off_day FROM daily_counters WHERE date = ?",
        (today,),
    ).fetchone()


def increment_today_counter(conn: sqlite3.Connection) -> int:
    """Incrémente le compteur du jour. Retourne la nouvelle valeur."""
    today = datetime.now().date().isoformat()
    get_or_create_today_counter(conn, today)
    conn.execute(
        "UPDATE daily_counters SET n_republications = n_republications + 1 WHERE date = ?",
        (today,),
    )
    row = conn.execute(
        "SELECT n_republications FROM daily_counters WHERE date = ?", (today,)
    ).fetchone()
    return row["n_republications"]


# ─────────────────────────────────────────────────────────────
# Key-value state (last sync, etc.)
# ─────────────────────────────────────────────────────────────


def kv_get(conn: sqlite3.Connection, key: str) -> str | None:
    row = conn.execute("SELECT value FROM kv_state WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else None


def kv_set(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute(
        """
        INSERT INTO kv_state (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
        (key, value),
    )
