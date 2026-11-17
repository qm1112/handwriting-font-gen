import json
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Dict, List, Optional, Union
from urllib.parse import quote

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from charset_gen import generate_charsets
from db import (
    get_all_statuses,
    get_char_record,
    get_completed_chars,
    get_svgs_dir,
    init_db,
    upsert_char_completed,
)
from ttf_compiler import compile_ttf

BASE_DIR = Path(__file__).resolve().parent
CHARSETS_PATH = BASE_DIR / "charsets.json"

CHARSETS_DATA: Dict[str, List[Dict[str, str]]] = {}
CHAR_LOOKUP: Dict[str, Dict[str, str]] = {}


def _load_charsets() -> Dict[str, List[Dict[str, str]]]:
    if CHARSETS_PATH.exists():
        data = json.loads(CHARSETS_PATH.read_text(encoding="utf-8"))
    else:
        data = generate_charsets(CHARSETS_PATH)
    return data


@asynccontextmanager
async def lifespan(app: FastAPI):
    global CHARSETS_DATA, CHAR_LOOKUP
    CHARSETS_DATA = _load_charsets()
    CHAR_LOOKUP = {}
    for category, items in CHARSETS_DATA.items():
        for item in items:
            u_hex = item["unicode_hex"].upper()
            if u_hex not in CHAR_LOOKUP:
                CHAR_LOOKUP[u_hex] = {
                    "unicode_hex": u_hex,
                    "char": item["char"],
                    "category": category,
                }
    init_db(CHARSETS_DATA)
    yield


app = FastAPI(title="Handwriting Font Generator API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class SaveCharRequest(BaseModel):
    strokes_json: Union[str, List[Any], Dict[str, Any]]
    merged_svg_path: str


class ExportTTFRequest(BaseModel):
    font_name: str = "MyHandwritingFont"
    weight: Union[str, int] = "regular"


@app.get("/api/charsets")
def api_get_charsets():
    info = {
        category: {"count": len(items)}
        for category, items in CHARSETS_DATA.items()
    }
    return {
        "info": info,
        "charsets": CHARSETS_DATA,
    }


@app.get("/api/progress")
def api_get_progress():
    statuses = get_all_statuses()
    groups: Dict[str, Dict[str, Any]] = {}
    characters: List[Dict[str, Any]] = []
    seen = set()

    for category, items in CHARSETS_DATA.items():
        total = len(items)
        completed = 0
        for item in items:
            u_hex = item["unicode_hex"].upper()
            st = statuses.get(u_hex, {"status": "pending", "updated_at": None})
            if st["status"] == "completed":
                completed += 1
            if u_hex not in seen:
                seen.add(u_hex)
                characters.append(
                    {
                        "unicode_hex": u_hex,
                        "char": item["char"],
                        "category": category,
                        "status": st["status"],
                        "updated_at": st["updated_at"],
                    }
                )
        groups[category] = {
            "total": total,
            "completed": completed,
            "percentage": round((completed / total) * 100, 2) if total > 0 else 0.0,
        }

    return {
        "groups": groups,
        "characters": characters,
    }


@app.get("/api/char/{unicode_hex}")
def api_get_char(unicode_hex: str):
    u_hex = unicode_hex.upper()
    record = get_char_record(u_hex)
    if not record:
        info = CHAR_LOOKUP.get(u_hex)
        if not info:
            raise HTTPException(status_code=404, detail=f"Character {u_hex} not found")
        record = {
            "unicode_hex": u_hex,
            "char": info["char"],
            "category": info["category"],
            "status": "pending",
            "strokes_json": None,
            "updated_at": None,
        }

    svg_file = get_svgs_dir() / f"{u_hex}.svg"
    svg_path: Optional[str] = str(svg_file) if svg_file.exists() else None
    strokes = record["strokes_json"]
    if isinstance(strokes, str):
        try:
            strokes = json.loads(strokes)
        except json.JSONDecodeError:
            pass

    return {
        "unicode_hex": record["unicode_hex"],
        "char": record["char"],
        "category": record["category"],
        "status": record["status"],
        "strokes_json": strokes,
        "svg_path": svg_path,
        "updated_at": record["updated_at"],
    }


def _build_svg_document(merged_svg_path: str) -> str:
    raw = merged_svg_path.strip()
    if raw.startswith("<svg"):
        return raw
    if raw.startswith("<path"):
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">\n'
            f"  {raw}\n"
            "</svg>\n"
        )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">\n'
        f'  <path d="{raw}" fill="#000000" />\n'
        "</svg>\n"
    )


@app.post("/api/char/{unicode_hex}")
def api_save_char(unicode_hex: str, payload: SaveCharRequest):
    u_hex = unicode_hex.upper()
    info = CHAR_LOOKUP.get(u_hex)
    if info:
        ch = info["char"]
        category = info["category"]
    else:
        try:
            ch = chr(int(u_hex, 16))
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Invalid unicode_hex: {unicode_hex}")
        category = "custom"

    strokes_str = (
        payload.strokes_json
        if isinstance(payload.strokes_json, str)
        else json.dumps(payload.strokes_json, ensure_ascii=False)
    )

    svgs_dir = get_svgs_dir()
    svgs_dir.mkdir(parents=True, exist_ok=True)
    svg_file = svgs_dir / f"{u_hex}.svg"
    svg_content = _build_svg_document(payload.merged_svg_path)
    svg_file.write_text(svg_content, encoding="utf-8")

    updated_at = upsert_char_completed(
        unicode_hex=u_hex,
        char=ch,
        category=category,
        strokes_json=strokes_str,
    )

    return {
        "ok": True,
        "unicode_hex": u_hex,
        "char": ch,
        "status": "completed",
        "svg_path": str(svg_file),
        "updated_at": updated_at,
    }


@app.post("/api/export/ttf")
def api_export_ttf(payload: ExportTTFRequest):
    completed = get_completed_chars()
    if not completed:
        raise HTTPException(status_code=400, detail="No completed characters available for export")

    ttf_bytes = compile_ttf(
        font_name=payload.font_name,
        weight=payload.weight,
        completed_chars=completed,
        svgs_dir=get_svgs_dir(),
    )

    filename = f"{payload.font_name}.ttf"
    encoded_filename = quote(filename)
    return Response(
        content=ttf_bytes,
        media_type="font/ttf",
        headers={
            "Content-Disposition": f"attachment; filename=\"font.ttf\"; filename*=UTF-8''{encoded_filename}"
        },
    )


def _mount_frontend():
    candidates = [
        (BASE_DIR.parent / "frontend" / "dist").resolve(),
        (BASE_DIR / "static").resolve(),
    ]
    static_dir = next((p for p in candidates if p.is_dir()), None)
    if static_dir is None:
        return

    assets_dir = static_dir / "assets"
    if assets_dir.is_dir():
        app.mount("/assets", StaticFiles(directory=str(assets_dir)), name="assets")

    @app.get("/{full_path:path}")
    def spa_fallback(full_path: str):
        target = (static_dir / full_path).resolve()
        if full_path and target.is_file() and static_dir in target.parents:
            return FileResponse(str(target))
        index_file = static_dir / "index.html"
        if index_file.is_file():
            return FileResponse(str(index_file))
        raise HTTPException(status_code=404, detail="Not Found")


_mount_frontend()
