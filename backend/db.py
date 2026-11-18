import os
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


def sanitize_tag(tag: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_-]", "", (tag or "").strip())
    return safe or "default"


def get_data_dir() -> Path:
    return Path(os.environ.get("DATA_DIR", "./data")).resolve()


def get_db_path() -> Path:
    return get_data_dir() / "fontgen.db"


def get_svgs_dir(tag: str = "default") -> Path:
    return get_data_dir() / "svgs" / sanitize_tag(tag)


def resolve_svg_path(unicode_hex: str, tag: str = "default") -> Optional[Path]:
    u_hex = unicode_hex.upper()
    tagged_path = get_svgs_dir(tag) / f"{u_hex}.svg"
    if tagged_path.exists():
        return tagged_path
    if sanitize_tag(tag) == "default":
        legacy_path = get_data_dir() / "svgs" / f"{u_hex}.svg"
        if legacy_path.exists():
            return legacy_path
    return None


def get_connection() -> sqlite3.Connection:
    db_path = get_db_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db(charsets: Dict[str, List[Dict[str, str]]]) -> None:
    get_svgs_dir("default").mkdir(parents=True, exist_ok=True)
    conn = get_connection()
    try:
        table_exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='characters'"
        ).fetchone()

        if table_exists:
            cols = [
                row["name"]
                for row in conn.execute("PRAGMA table_info(characters)").fetchall()
            ]
            if "tag" not in cols:
                conn.execute("ALTER TABLE characters RENAME TO characters_old")
                conn.execute(
                    """
                    CREATE TABLE characters (
                        tag TEXT NOT NULL DEFAULT 'default',
                        unicode_hex TEXT NOT NULL,
                        char TEXT NOT NULL,
                        category TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'pending',
                        strokes_json TEXT,
                        updated_at TEXT,
                        UNIQUE(tag, unicode_hex)
                    )
                    """
                )
                conn.execute(
                    """
                    INSERT INTO characters (tag, unicode_hex, char, category, status, strokes_json, updated_at)
                    SELECT 'default', unicode_hex, char, category, status, strokes_json, updated_at
                    FROM characters_old
                    """
                )
                conn.execute("DROP TABLE characters_old")
        else:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS characters (
                    tag TEXT NOT NULL DEFAULT 'default',
                    unicode_hex TEXT NOT NULL,
                    char TEXT NOT NULL,
                    category TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    strokes_json TEXT,
                    updated_at TEXT,
                    UNIQUE(tag, unicode_hex)
                )
                """
            )

        rows = []
        for category, items in charsets.items():
            for item in items:
                rows.append(("default", item["unicode_hex"].upper(), item["char"], category, "pending"))
        conn.executemany(
            """
            INSERT OR IGNORE INTO characters (tag, unicode_hex, char, category, status)
            VALUES (?, ?, ?, ?, ?)
            """,
            rows,
        )
        conn.commit()
    finally:
        conn.close()


def get_char_record(unicode_hex: str, tag: str = "default") -> Optional[Dict[str, Any]]:
    safe_tag = sanitize_tag(tag)
    conn = get_connection()
    try:
        cur = conn.execute(
            "SELECT tag, unicode_hex, char, category, status, strokes_json, updated_at FROM characters WHERE tag = ? AND unicode_hex = ?",
            (safe_tag, unicode_hex.upper()),
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
    tag: str = "default",
) -> str:
    safe_tag = sanitize_tag(tag)
    now = datetime.now(timezone.utc).isoformat()
    conn = get_connection()
    try:
        conn.execute(
            """
            INSERT INTO characters (tag, unicode_hex, char, category, status, strokes_json, updated_at)
            VALUES (?, ?, ?, ?, 'completed', ?, ?)
            ON CONFLICT(tag, unicode_hex) DO UPDATE SET
                status = 'completed',
                strokes_json = excluded.strokes_json,
                updated_at = excluded.updated_at
            """,
            (safe_tag, unicode_hex.upper(), char, category, strokes_json, now),
        )
        conn.commit()
        return now
    finally:
        conn.close()


def get_all_statuses(tag: str = "default") -> Dict[str, Dict[str, Any]]:
    safe_tag = sanitize_tag(tag)
    conn = get_connection()
    try:
        cur = conn.execute(
            "SELECT unicode_hex, status, updated_at FROM characters WHERE tag = ?",
            (safe_tag,),
        )
        return {
            row["unicode_hex"]: {"status": row["status"], "updated_at": row["updated_at"]}
            for row in cur.fetchall()
        }
    finally:
        conn.close()


def get_completed_chars(tag: str = "default") -> List[Dict[str, Any]]:
    safe_tag = sanitize_tag(tag)
    conn = get_connection()
    try:
        cur = conn.execute(
            "SELECT tag, unicode_hex, char, category, strokes_json, updated_at FROM characters WHERE tag = ? AND status = 'completed'",
            (safe_tag,),
        )
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()


def list_tags() -> List[Dict[str, Any]]:
    conn = get_connection()
    try:
        cur = conn.execute(
            "SELECT tag, COUNT(*) as count FROM characters WHERE status IN ('completed', 'done') GROUP BY tag"
        )
        tag_counts: Dict[str, int] = {row["tag"]: row["count"] for row in cur.fetchall()}
        if "default" not in tag_counts:
            tag_counts["default"] = 0
        return [
            {"tag": tag_name, "completed": count}
            for tag_name, count in sorted(tag_counts.items(), key=lambda x: (x[0] != "default", x[0]))
        ]
    finally:
        conn.close()
