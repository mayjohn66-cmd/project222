#!/usr/bin/env python3
"""에셋 규격 검증기 (초안 v0.1)

사용:
  python validate_assets.py <프로젝트 루트> [--extra-items 파일.csv ...] [--report 출력.md]

- 프로젝트 루트에는 art/ 와 data/core/items.csv 가 있어야 한다.
- --extra-items: 아직 items.csv에 합치지 않은 초안 CSV(예: items_materials_draft.csv).
  여기 적힌 icon_path 중 파일이 없는 것도 "필요한 아이콘"으로 보고한다.
- 규칙은 아래 RULES 에서만 고치면 된다(에셋 규격서와 같은 값).
- FAIL 이 하나라도 있으면 종료 코드 1.
"""
import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict

from PIL import Image

# ---------------------------------------------------------------------------
# 규칙 (위에서부터 처음 맞는 접두사가 적용됨). 값은 에셋 규격서 v0.1 과 동일하게 유지할 것.
#   legacy        : 픽셀 통일 전의 기존 그림. 검사하지 않고 "교체 대상"으로만 집계
#   size          : 정확히 이 크기여야 함
#   frame         : 가로·세로가 이 값의 배수여야 함(스프라이트 시트 허용)
#   multiple_of   : 가로·세로가 이 값의 배수가 아니면 WARN (UI 용)
#   max_colors    : 불투명 픽셀의 서로 다른 색 수 상한
#   no_partial_alpha : 알파가 0 또는 255 만 허용(안티앨리어싱 금지)
# ---------------------------------------------------------------------------
RULES = [
    ("legacy-world",        "art/world/",                {"legacy": True}),
    ("legacy-expedition",   "art/expedition/",           {"legacy": True}),
    ("legacy-characters",   "art/characters/",           {"legacy": True}),
    ("legacy-ui-reference", "art/ui/reference_theme/",   {"legacy": True}),
    ("ui",                  "art/ui/",                   {"multiple_of": 8}),
    ("item-icon",           "art/items/",                {"size": (64, 64), "max_colors": 32, "no_partial_alpha": True}),
    ("furniture",           "art/furniture/",            {"frame": 64, "max_colors": 48, "no_partial_alpha": True}),
    ("actor",               "art/player/",               {"frame": 64, "max_colors": 48, "no_partial_alpha": True}),
    ("actor",               "art/monsters/",             {"frame": 64, "max_colors": 48, "no_partial_alpha": True}),
    ("tile",                "art/tiles/",                {"frame": 32, "max_colors": 32, "no_partial_alpha": True}),
]
NAME_RE = re.compile(r"^[a-z0-9_]+\.png$")
VERSION_DIR_RE = re.compile(r"(^|_)v\d+$")


def pick_rule(rel):
    for name, prefix, rule in RULES:
        if rel.startswith(prefix):
            return name, rule
    return "unclassified", {}


def load_items(csv_path):
    """id -> icon_path(상대경로) 매핑."""
    out = {}
    if not os.path.exists(csv_path):
        return out
    with open(csv_path, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            icon = (row.get("icon_path") or "").strip()
            out[row["id"]] = icon.replace("res://", "") if icon else ""
    return out


def check_image(path, rule):
    """(FAIL 사유 목록, WARN 사유 목록) 반환."""
    fails, warns = [], []
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if "size" in rule and (w, h) != rule["size"]:
        fails.append(f"크기 {w}x{h} (기대 {rule['size'][0]}x{rule['size'][1]})")
    if "frame" in rule and (w % rule["frame"] or h % rule["frame"]):
        fails.append(f"크기 {w}x{h} 는 {rule['frame']}의 배수가 아님")
    if "multiple_of" in rule and (w % rule["multiple_of"] or h % rule["multiple_of"]):
        warns.append(f"크기 {w}x{h} 는 {rule['multiple_of']}의 배수가 아님")
    cols = im.getcolors(maxcolors=w * h) or []
    partial = sum(c for c, px in cols if 0 < px[3] < 255)
    colors = len({px[:3] for c, px in cols if px[3] > 0})
    if rule.get("no_partial_alpha") and partial:
        fails.append(f"반투명 픽셀 {partial}개 (안티앨리어싱 금지)")
    if "max_colors" in rule and colors > rule["max_colors"]:
        fails.append(f"색 {colors}개 (상한 {rule['max_colors']})")
    return fails, warns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--extra-items", action="append", default=[])
    ap.add_argument("--report", default=None)
    args = ap.parse_args()
    root = args.root
    art = os.path.join(root, "art")
    if not os.path.isdir(art):
        sys.exit(f"art/ 폴더가 없음: {art}")

    items = load_items(os.path.join(root, "data/core/items.csv"))
    extra = {}
    for p in args.extra_items:
        extra.update(load_items(p))
    known_ids = set(items) | set(extra)

    per_rule = defaultdict(Counter)   # 규칙별 PASS/WARN/FAIL/LEGACY 집계
    fail_lines, warn_lines = [], []
    version_dirs = set()
    existing = set()

    for dirpath, _, files in os.walk(art):
        for fn in sorted(files):
            if not fn.lower().endswith(".png"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            existing.add(rel)
            for seg in rel.split("/")[:-1]:
                if VERSION_DIR_RE.search(seg):
                    version_dirs.add("/".join(rel.split("/")[: rel.split("/").index(seg) + 1]))
            name, rule = pick_rule(rel)
            if rule.get("legacy"):
                per_rule[name]["LEGACY"] += 1
                continue
            fails, warns = [], []
            if not NAME_RE.match(fn):
                fails.append("파일명은 소문자·숫자·밑줄만 (예: forest_herb.png)")
            try:
                f2, w2 = check_image(full, rule)
                fails += f2
                warns += w2
            except Exception as e:  # 깨진 파일
                fails.append(f"이미지를 열 수 없음: {e}")
            if rel.startswith("art/items/") and os.path.splitext(fn)[0] not in known_ids:
                warns.append("items.csv 에 없는 ID (안 쓰는 아이콘일 수 있음)")
            if fails:
                per_rule[name]["FAIL"] += 1
                fail_lines.append(f"- `{rel}` — " + "; ".join(fails))
            elif warns:
                per_rule[name]["WARN"] += 1
                warn_lines.append(f"- `{rel}` — " + "; ".join(warns))
            else:
                per_rule[name]["PASS"] += 1

    # 아이콘 커버리지: CSV 가 가리키는 파일이 실제로 있는가
    missing = []
    for src, table in (("items.csv", items), ("추가 CSV", extra)):
        for item_id, icon in table.items():
            if icon and icon not in existing:
                missing.append((item_id, icon, src))

    lines = ["# 에셋 검증 리포트", ""]
    lines.append("## 요약 (규칙별)")
    lines.append("")
    lines.append("| 규칙 | PASS | WARN | FAIL | 교체 대상(LEGACY) |")
    lines.append("|---|---|---|---|---|")
    total = Counter()
    for name in sorted(per_rule):
        c = per_rule[name]
        total.update(c)
        lines.append(f"| {name} | {c['PASS']} | {c['WARN']} | {c['FAIL']} | {c['LEGACY']} |")
    lines.append(f"| **합계** | {total['PASS']} | {total['WARN']} | {total['FAIL']} | {total['LEGACY']} |")
    lines.append("")
    lines.append(f"## 누락된 아이콘 ({len(missing)}개)")
    lines.append("")
    for item_id, icon, src in sorted(missing):
        lines.append(f"- `{item_id}` → `{icon}` ({src})")
    if not missing:
        lines.append("- 없음")
    lines.append("")
    lines.append(f"## FAIL ({len(fail_lines)}개)")
    lines.append("")
    lines += fail_lines or ["- 없음"]
    lines.append("")
    lines.append(f"## WARN ({len(warn_lines)}개)")
    lines.append("")
    lines += warn_lines or ["- 없음"]
    lines.append("")
    lines.append(f"## 버전 폴더 ({len(version_dirs)}개) — 버전 관리는 git 으로 대체 권장")
    lines.append("")
    lines += [f"- `{d}/`" for d in sorted(version_dirs)] or ["- 없음"]
    text = "\n".join(lines) + "\n"

    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.write(text)
    print(text)
    sys.exit(1 if total["FAIL"] else 0)


if __name__ == "__main__":
    main()
