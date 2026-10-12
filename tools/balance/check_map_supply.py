#!/usr/bin/env python3
"""보물 지도 공급량 점검: 보스 처치 1회당 지도가 나올 확률(난이도별).

지도 희귀도는 0이라 희귀 확률 배율을 받지 않는다. 두루마리를 다 배우면 다른 항목이
줄어 확률이 올라가므로 '배운 것 없음'과 '전부 배움' 두 경우를 보여 준다.
사용: python tools/balance/check_map_supply.py .
"""
import csv
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
items = {r["id"]: r for r in csv.DictReader(open(root / "data/core/items.csv", encoding="utf-8"))}
rare_mult = {int(r["difficulty"]): float(r["rare_chance_mult"])
             for r in csv.DictReader(open(root / "data/expedition/expedition_difficulty.csv", encoding="utf-8"))}
rows = list(csv.DictReader(open(root / "data/expedition/expedition_loot.csv", encoding="utf-8")))

print("표: 보스 1회 처치 시 보물 지도 확률")
# 보스 표를 loot CSV에서 모두 찾는다(유적 보스는 지도를 소비하는 곳이라 제외).
BOSS_TABLES = sorted({r["table_id"] for r in rows if r["table_id"].endswith("_boss") and r["table_id"] != "ruins_boss"})
for table in BOSS_TABLES:
    for d in sorted(rare_mult):
        cells = []
        for learned in (False, True):
            total = map_w = 0.0
            for r in rows:
                if r["table_id"] != table:
                    continue
                lo = int(r["min_difficulty"] or 1)
                hi = int(r["max_difficulty"] or 9999)
                if not lo <= d <= hi or (learned and r["item_id"].startswith("scroll_")):
                    continue
                w = float(r["weight"])
                if int(items[r["item_id"]]["rarity"]) >= 2:
                    w *= rare_mult[d]
                total += w
                if r["item_id"] == "treasure_map":
                    map_w = w
            cells.append(f"{100 * map_w / total:.0f}%")
        print(f"  {table} 난이도{d}: 배운 것 없음 {cells[0]} / 전부 배움 {cells[1]}")
