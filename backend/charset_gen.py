import json
from pathlib import Path
from typing import Dict, List


def _char_entry(ch: str) -> Dict[str, str]:
    return {
        "unicode_hex": f"{ord(ch):04X}",
        "char": ch,
    }


def extract_gb2312_hanzi() -> tuple[List[str], List[str]]:
    """Extract Level 1 (3755) and Level 2 (3008) Hanzi from GB2312."""
    level1: List[str] = []
    # Level 1: qu 16..55 (0xB0..0xD7), wei 1..94 (0xA1..0xFE)
    # Qu 55 only has wei 1..89 (0xA1..0xF9)
    for qu in range(16, 56):
        b1 = 0xA0 + qu
        max_wei = 89 if qu == 55 else 94
        for wei in range(1, max_wei + 1):
            b2 = 0xA0 + wei
            ch = bytes([b1, b2]).decode("gb2312")
            level1.append(ch)

    level2: List[str] = []
    # Level 2: qu 56..87 (0xD8..0xF7), wei 1..94 (0xA1..0xFE)
    for qu in range(56, 88):
        b1 = 0xA0 + qu
        for wei in range(1, 95):
            b2 = 0xA0 + wei
            ch = bytes([b1, b2]).decode("gb2312")
            level2.append(ch)

    return level1, level2


def generate_charsets(output_path: Path | None = None) -> Dict[str, List[Dict[str, str]]]:
    level1, level2 = extract_gb2312_hanzi()

    # basic_50: 50 basic test characters including "永" and high-frequency chars
    basic_chars_str = (
        "永一二三四五六七八九十"
        "上下左右中大小人口手"
        "日月水火木金土天地风"
        "云雨雪山川花鸟鱼虫马"
        "的是在不了有和人这中"
    )
    # Deduplicate while preserving order, then ensure exact 50 chars
    seen = set()
    basic_chars: List[str] = []
    for ch in basic_chars_str:
        if ch not in seen:
            seen.add(ch)
            basic_chars.append(ch)
    for ch in level1:
        if len(basic_chars) >= 50:
            break
        if ch not in seen:
            seen.add(ch)
            basic_chars.append(ch)

    level1_3500 = level1[:3500]
    gb2312_ext = level1[3500:] + level2  # 255 + 3008 = 3263

    # punct_ascii: Fullwidth Chinese punctuation + halfwidth ASCII letters, digits, punctuation (~150)
    zh_punct = (
        "，。！？“”‘’《》〈〉、；：（）【】「」『』"
        "—…·～￥％＃＠＆＊＋－＝／＼｜＿"
        "〔〕〖〗〝〞︰﹐﹒﹔﹕﹖﹗﹙﹚﹛﹜﹝﹞"
    )
    ascii_chars = (
        "0123456789"
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "abcdefghijklmnopqrstuvwxyz"
        " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    )
    punct_seen = set()
    punct_ascii: List[str] = []
    for ch in zh_punct + ascii_chars:
        if ch not in punct_seen:
            punct_seen.add(ch)
            punct_ascii.append(ch)

    data = {
        "basic_50": [_char_entry(ch) for ch in basic_chars],
        "level1_3500": [_char_entry(ch) for ch in level1_3500],
        "gb2312_ext": [_char_entry(ch) for ch in gb2312_ext],
        "punct_ascii": [_char_entry(ch) for ch in punct_ascii],
    }

    if output_path is not None:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    return data


if __name__ == "__main__":
    out = Path(__file__).resolve().parent / "charsets.json"
    result = generate_charsets(out)
    for k, v in result.items():
        print(f"{k}: {len(v)} chars")
    print(f"Saved to {out}")
