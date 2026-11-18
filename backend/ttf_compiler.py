import io
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Tuple

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import SVGPath


def _build_notdef_glyph() -> object:
    pen = TTGlyphPen(None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((400, 700))
    pen.lineTo((400, 0))
    pen.closePath()
    return pen.glyph()


def _svg_to_tt_glyph(svg_path: Path):
    svg_text = svg_path.read_text(encoding="utf-8")
    tt_pen = TTGlyphPen(None)
    cu2qu_pen = Cu2QuPen(tt_pen, max_err=1.0, reverse_direction=False)
    # Flip Y axis: font_y = 880 - canvas_y
    transform_pen = TransformPen(cu2qu_pen, (1, 0, 0, -1, 0, 880))

    try:
        svg = SVGPath.fromstring(svg_text.encode("utf-8"))
        svg.draw(transform_pen)
    except Exception:
        # Fallback: extract path d attributes manually if SVG root has non-standard attributes
        root = ET.fromstring(svg_text)
        paths = []
        for elem in root.iter():
            if elem.tag.endswith("path") and elem.attrib.get("d"):
                paths.append(elem.attrib["d"])
        if paths:
            minimal_svg = (
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">'
                + "".join(f'<path d="{d}"/>' for d in paths)
                + "</svg>"
            )
            svg = SVGPath.fromstring(minimal_svg.encode("utf-8"))
            svg.draw(transform_pen)

    return tt_pen.glyph()


def _parse_weight_class(weight: str | int) -> Tuple[int, str]:
    if isinstance(weight, int):
        w = max(100, min(900, weight))
        style = "Bold" if w >= 700 else "Regular"
        return w, style
    w_str = str(weight).strip().lower()
    mapping = {
        "thin": (100, "Thin"),
        "extralight": (200, "ExtraLight"),
        "light": (300, "Light"),
        "regular": (400, "Regular"),
        "normal": (400, "Regular"),
        "medium": (500, "Medium"),
        "semibold": (600, "SemiBold"),
        "bold": (700, "Bold"),
        "extrabold": (800, "ExtraBold"),
        "black": (900, "Black"),
    }
    if w_str in mapping:
        return mapping[w_str]
    try:
        w = max(100, min(900, int(w_str)))
        return w, ("Bold" if w >= 700 else "Regular")
    except ValueError:
        return 400, "Regular"


def compile_ttf(
    font_name: str,
    weight: str | int,
    completed_chars: List[Dict[str, str]],
    svgs_dir: Path,
    tag: str = "default",
) -> bytes:
    units_per_em = 1000
    ascender = 880
    descender = -120

    weight_class, style_name = _parse_weight_class(weight)

    glyph_order = [".notdef"]
    glyf_table = {".notdef": _build_notdef_glyph()}
    hmtx_table = {".notdef": (500, 100)}
    cmap_table: Dict[int, str] = {}

    for item in completed_chars:
        u_hex = item["unicode_hex"].upper()
        ch = item["char"]
        svg_file = svgs_dir / f"{u_hex}.svg"
        if not svg_file.exists() and tag == "default":
            legacy_file = svgs_dir.parent / f"{u_hex}.svg"
            if legacy_file.exists():
                svg_file = legacy_file
        if not svg_file.exists():
            continue

        glyph_name = f"uni{u_hex}"
        if glyph_name in glyf_table:
            continue

        glyph = _svg_to_tt_glyph(svg_file)
        glyph_order.append(glyph_name)
        glyf_table[glyph_name] = glyph

        codepoint = ord(ch)
        cmap_table[codepoint] = glyph_name

        # Halfwidth ASCII gets 550 advance width, fullwidth/CJK gets 1000
        advance_width = 550 if codepoint < 0x80 else 1000
        lsb = 0
        hmtx_table[glyph_name] = (advance_width, lsb)

    fb = FontBuilder(units_per_em, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap_table)
    fb.setupGlyf(glyf_table)
    fb.setupHorizontalMetrics(hmtx_table)
    fb.setupHorizontalHeader(ascent=ascender, descent=descender)

    ps_name = re.sub(r"[^A-Za-z0-9\-]", "", font_name) or "HandwritingFont"
    fb.setupNameTable(
        {
            "familyName": font_name,
            "styleName": style_name,
            "uniqueFontIdentifier": f"{ps_name}-{style_name}",
            "fullName": f"{font_name} {style_name}",
            "psName": f"{ps_name}-{style_name}",
            "version": "Version 1.0",
        }
    )

    fb.setupOS2(
        sTypoAscender=ascender,
        sTypoDescender=descender,
        sTypoLineGap=0,
        usWinAscent=ascender,
        usWinDescent=abs(descender),
        usWeightClass=weight_class,
    )
    fb.setupPost()
    fb.setupMaxp()

    buf = io.BytesIO()
    fb.font.save(buf)
    return buf.getvalue()
