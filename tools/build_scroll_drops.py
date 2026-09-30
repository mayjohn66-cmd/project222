#!/usr/bin/env python3
"""레시피 두루마리 드롭 행을 expedition_loot.csv에 다시 만든다.

원본은 data/production/recipe_unlocks.csv 의 difficulty, regions 열이다.
  - difficulty: 이 난이도에서만 그 두루마리가 나온다(min_difficulty = max_difficulty).
  - regions: 두루마리가 나오는 지역(세미콜론 구분). 지역마다 아래 REGION_TABLES의 드롭 테이블에 들어간다.
같은 (테이블, 난이도) 안의 두루마리는 무게를 똑같이 나눈다: 무게 = clamp(TARGET_TOTAL / 개수, MIN_W, MAX_W).
이 도구는 기존 scroll_ 행을 지우고 다시 넣으므로 여러 번 실행해도 결과가 같다.

사용: python tools/build_scroll_drops.py .
"""
import csv
import sys
from collections import Counter, defaultdict
from pathlib import Path

REGION_TABLES = {
    "forest": ["boss_forest", "forest_boss", "forest_treasure"],
    "mine": ["boss_mine", "mine_boss", "mine_treasure"],
    "swamp": ["boss_swamp", "swamp_boss", "swamp_treasure"],
    "hidden_ruins": ["boss_hidden_ruins", "ruins_boss", "ruins_treasure"],
}
TARGET_TOTAL = 60
MIN_W = 5
MAX_W = 20
EXTRA_COLUMNS = ["min_difficulty", "max_difficulty"]


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    unlocks = [
        r for r in csv.DictReader(open(root / "data/production/recipe_unlocks.csv", encoding="utf-8"))
        if r.get("recipe_id")
    ]

    per_table = defaultdict(list)  # 테이블 -> [(두루마리, 난이도)]
    for r in unlocks:
        difficulty = int(r["difficulty"])
        for region in r["regions"].split(";"):
            for table in REGION_TABLES[region.strip()]:
                per_table[table].append((r["scroll_item_id"], difficulty))

    counts = Counter((t, d) for t, v in per_table.items() for _, d in v)

    def weight(table, difficulty):
        return max(MIN_W, min(MAX_W, round(TARGET_TOTAL / counts[(table, difficulty)])))

    path = root / "data/expedition/expedition_loot.csv"
    lines = path.read_text(encoding="utf-8").split("\n")

    header = lines[0].split(",")
    for column in EXTRA_COLUMNS:
        if column not in header:
            header.append(column)
    lines[0] = ",".join(header)
    width = len(header)

    body = []
    for line in lines[1:]:
        cells = line.split(",")
        if len(cells) > 1 and cells[1].startswith("scroll_"):
            continue
        if line.strip() and len(cells) < width:
            line = line + "," * (width - len(cells))
        body.append(line)

    last = {}
    for i, line in enumerate(body):
        table = line.split(",")[0]
        if table in per_table:
            last[table] = i
    insert_after = {i: t for t, i in last.items()}

    out = [lines[0]]
    for i, line in enumerate(body):
        out.append(line)
        if i in insert_after:
            table = insert_after[i]
            for scroll, difficulty in per_table[table]:
                out.append(f"{table},{scroll},{weight(table, difficulty)},1,1,{difficulty},{difficulty}")

    missing = [t for t in per_table if t not in last]
    if missing:
        print("[경고] 드롭 테이블이 CSV에 없음:", ", ".join(missing))

    path.write_text("\n".join(out), encoding="utf-8", newline="")
    print(f"두루마리 행 {sum(len(v) for v in per_table.values())}개 작성 (무게 {MIN_W}~{MAX_W}, 목표 합계 {TARGET_TOTAL})")


if __name__ == "__main__":
    main()
