#!/usr/bin/env python3
"""스토리 장면(story_beats.csv) 검사기. 제미나이 같은 외부 AI가 쓴 초안을 게임 데이터에 넣기 전에 돌린다.

사용법:
  python tools/validate_story.py .                                  # 실제 데이터 검사
  python tools/validate_story.py . docs/drafts/story_beats_draft.csv  # 초안 파일 검사

검사: 열 이름, beat_id 중복, npc_id 존재, 조건 문법(story_conditions.gd와 같은 목록),
선물 형식과 아이디 존재, 대사 비어 있음·길이, repeat_days 숫자.
조건은 알 수 없는 것이 하나라도 있으면 게임에서 항상 거짓이 되므로 오류로 본다.
"""
import csv
import re
import sys
from pathlib import Path

COLUMNS = ["beat_id", "npc_id", "conditions", "gifts", "repeat_days", "lines"]
MAX_LINE_CHARS = 40       # 대사 한 줄(| 로 나뉜 한 칸) 권장 상한. 대화창에 맞춘 값(❓ 확인 필요)
MAX_LINES = 6
MAX_GIFT_QTY = 20


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def check_condition(c, items, furniture):
    if re.fullmatch(r"day>=\d+", c) or c == "expedition_done" or c == "product_stock_empty":
        return None
    if re.fullmatch(r"money<\d+", c):
        return None
    m = re.fullmatch(r"item_below:([a-z0-9_]+):(\d+)", c)
    if m:
        return None if m.group(1) in items else f"없는 아이템 {m.group(1)}"
    m = re.fullmatch(r"furniture_missing:([a-z0-9_]+)", c)
    if m:
        return None if m.group(1) in furniture else f"없는 가구 {m.group(1)}"
    return "알 수 없는 조건(게임에서 항상 거짓)"


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "data/story/story_beats.csv"
    items = {r["id"] for r in read(root / "data/core/items.csv")}
    furniture = {r["id"] for r in read(root / "data/shop/catalogs/furniture_items.csv")}
    npcs = {r["npc_id"] for r in read(root / "data/story/story_npcs.csv")}
    errors, warns = [], []

    with open(target, encoding="utf-8", newline="") as f:
        header = next(csv.reader(f))
    if header != COLUMNS:
        errors.append(f"열 이름이 {COLUMNS} 와 다릅니다: {header}")

    seen = set()
    rows = read(target)
    for n, r in enumerate(rows, start=2):
        tag = f"{target.name}:{n} [{r.get('beat_id', '')}]"
        bid = (r.get("beat_id") or "").strip()
        if not re.fullmatch(r"[a-z0-9_]+", bid):
            errors.append(f"{tag} beat_id는 소문자·숫자·밑줄만")
        if bid in seen:
            errors.append(f"{tag} beat_id 중복")
        seen.add(bid)
        if (r.get("npc_id") or "") not in npcs:
            errors.append(f"{tag} 없는 npc_id: {r.get('npc_id')}")
        for c in filter(None, (r.get("conditions") or "").split(";")):
            why = check_condition(c.strip(), items, furniture)
            if why:
                errors.append(f"{tag} 조건 '{c}': {why}")
        if not (r.get("conditions") or "").strip():
            warns.append(f"{tag} 조건이 없어 항상 나올 수 있음")
        for g in filter(None, (r.get("gifts") or "").split(";")):
            parts = g.strip().split(":")
            if len(parts) != 3 or not parts[2].isdigit():
                errors.append(f"{tag} 선물 형식 '종류:아이디:수량' 아님: {g}")
                continue
            kind, gid, qty = parts[0], parts[1], int(parts[2])
            if kind == "item" and gid not in items:
                errors.append(f"{tag} 없는 아이템 선물: {gid}")
            elif kind == "furniture" and gid not in furniture:
                errors.append(f"{tag} 없는 가구 선물: {gid}")
            elif kind not in ("item", "furniture", "money"):
                errors.append(f"{tag} 선물 종류는 item/furniture/money: {kind}")
            if qty > MAX_GIFT_QTY and kind != "money":
                warns.append(f"{tag} 선물 수량이 많음({qty}): 밸런스 확인")
            if kind == "money":
                warns.append(f"{tag} 돈 선물({qty}): 밸런스는 Claude 확인 필요")
        if not (r.get("repeat_days") or "").strip().lstrip("-").isdigit():
            errors.append(f"{tag} repeat_days는 숫자(0 = 한 번만)")
        lines = [x for x in (r.get("lines") or "").split("|")]
        if not lines or any(not x.strip() for x in lines):
            errors.append(f"{tag} 대사가 비었거나 빈 칸이 있음")
        if len(lines) > MAX_LINES:
            warns.append(f"{tag} 대사 {len(lines)}줄(권장 {MAX_LINES} 이하)")
        for x in lines:
            if len(x) > MAX_LINE_CHARS:
                warns.append(f"{tag} 대사 한 칸이 {len(x)}자(권장 {MAX_LINE_CHARS} 이하): {x[:20]}...")
            if "," in x:
                pass  # CSV 따옴표 처리됨. 문제 없음

    print(f"검사 대상: {target} ({len(rows)}개 장면)")
    for w in warns:
        print("주의:", w)
    for e in errors:
        print("오류:", e)
    print(f"오류 {len(errors)}개, 주의 {len(warns)}개")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
