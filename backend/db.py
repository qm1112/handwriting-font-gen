import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


def get_data_dir() -> Path:
    return Path(os.environ.get("DATA_DIR", "./data")).resolve()


def get_db_path() -> Path:
    return get_data_dir() / "fontgen.db"


def get_svgs_dir() -> Path:
    return get_data_dir() / "svgs"


def get_connection() -> sqlite3.Connection:
    db_path = get_db_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db(charsets: Dict[str, List[Dict[str, str]]]) -> None:
    get_svgs_dir().mkdir(parents=True, exist_ok=True)
    conn = get_connection()
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS characters (
                unicode_hex TEXT PRIMARY KEY,
                char TEXT NOT NULL,
                category TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                strokes_json TEXT,
                updated_at TEXT
            )
            """
        )
        rows = []
        for category, items in charsets.items():
            for item in items:
                rows.append((item["unicode_hex"].upper(), item["char"], category, "pending"))
        conn.executemany(
            """
            INSERT OR IGNORE INTO characters (unicode_hex, char, category, status)
            VALUES (?, ?, ?, ?)
            """,
            rows,
        )
        conn.commit()
    finally:
        conn.close()


def get_char_record(unicode_hex: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    try:
        cur = conn.execute(
            "SELECT unicode_hex, char, category, status, strokes_json, updated_at FROM characters WHERE unicode_hex = ?",
            (unicode_hex.upper(),),
        )
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def upsert_char_completed(
    unicode_hex: str,
    char: str,
    category: str,
    strokes_json: str,
) -> str:
    now = datetime.now(timezone.utc).isoformat()
    conn = get_connection()
    try:
        conn.execute(
            """
            INSERT INTO characters (unicode_hex, char, category, status, strokes_json, updated_at)
            VALUES (?, ?, ?, 'completed', ?, ?)
            ON CONFLICT(unicode_hex) DO UPDATE SET
                status = 'completed',
                strokes_json = excluded.strokes_json,
                updated_at = excluded.updated_at
            """,
            (unicode_hex.upper(), char, category, strokes_json, now),
        )
        conn.commit()
        return now
    finally:
        conn.close()


def get_all_statuses() -> Dict[str, Dict[str, Any]]:
    conn = get_connection()
    try:
        cur = conn.execute("SELECT unicode_hex, status, updated_at FROM characters")
        return {
            row["unicode_hex"]: {"status": row["status"], "updated_at": row["updated_at"]}
            for row in cur.fetchall()
        }
    finally:
        conn.close()


def get_completed_chars() -> List[Dict[str, Any]]:
    conn = get_connection()
    try:
        cur = conn.execute(
            "SELECT unicode_hex, char, category, strokes_json, updated_at FROM characters WHERE status = 'completed'"
        )
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()
