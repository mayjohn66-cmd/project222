#!/usr/bin/env python3
"""장비 강화 비용 점검 도구.

- 강화 단계마다 필요한 재료와 그 재료의 판매가 합계(가치)를 보여 준다.
- 유적 재료는 유적 원정 1회(난이도 1)에 기대로 몇 개 나오는지 계산해서, 단계·장비별로 원정이 몇 회 필요한지 보여 준다.
  (기대 계산은 칸 종류 가중치와 이벤트가 가리키는 드롭 테이블을 따른다. 난이도 보상 배율과 희귀 확률 배율은 넣지 않았다.)
- 강화 비용 표에 빠진 단계나 없는 재료가 있으면 알려 준다.

사용: python tools/check_enhancement.py .
"""
import csv
import sys
from collections import defaultdict
from pathlib import Path

REGION = "hidden_ruins"


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values()))]


def expected_per_run(root, items):
    tiers = {int(r["difficulty"]): r for r in read(root / "data/expedition/expedition_difficulty.csv")}
    mid_rooms = int(tiers[1]["room_count"]) - 1  # 마지막 방은 보스

    node_w = {r["node_type"]: float(r["weight"]) for r in read(root / "data/expedition/expedition_map_nodes.csv") if r["region_id"] == REGION}
    node_total = sum(node_w.values())

    events = [r for r in read(root / "data/expedition/expedition_events.csv") if r["region_id"] == REGION]
    enemies = {r["id"]: r["loot_table"] for r in read(root / "data/expedition/enemies.csv")}
    loot = defaultdict(list)
    for r in read(root / "data/expedition/expedition_loot.csv"):
        if r["item_id"].startswith("scroll_"):
            continue
        loot[r["table_id"]].append(r)

    def roll(table):
        rows = loot.get(table, [])
        total = sum(float(r["weight"]) for r in rows)
        out = defaultdict(float)
        for r in rows:
            out[r["item_id"]] += float(r["weight"]) / total * (int(r["min_amount"]) + int(r["max_amount"])) / 2
        return out

    def event_table(node_type):
        event = next(e for e in events if e["node_type"] == node_type)
        if event["result_type"] == "loot":
            return event["target_id"]
        return enemies[event["target_id"]]

    result = defaultdict(float)
    for node_type, w in node_w.items():
        if node_type in ("boss", "start"):
            continue
        for item, amount in roll(event_table(node_type)).items():
            result[item] += mid_rooms * w / node_total * amount
    for item, amount in roll(event_table("boss")).items():
        result[item] += amount
    return result


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    items = {r["id"]: r for r in read(root / "data/core/items.csv")}
    equipment = {r["item_id"]: r for r in read(root / "data/expedition/expedition_equipment.csv")}
    costs = defaultdict(lambda: defaultdict(dict))
    for r in read(root / "data/expedition/equipment_enhancement_costs.csv"):
        costs[r["enhancement_group"]][int(r["target_level"])][r["material_id"]] = int(r["amount"])

    yields = expected_per_run(root, items)
    ruins_items = {i for i, r in items.items() if r["id"] in {"ancient_fragment", "rune_dust", "worn_coin", "rune_stone", "sealed_scroll", "ancient_relic"}}
    problems = 0

    print("유적 원정 1회(난이도 1) 기대 획득:", ", ".join(f"{items[i]['name']} {v:.2f}" for i, v in sorted(yields.items(), key=lambda kv: kv[0])))

    for item_id, eq in equipment.items():
        max_level = int(eq["max_enhancement_level"])
        group = eq["enhancement_group"]
        if not max_level:
            continue
        print(f"\n{items[item_id]['name']} ({item_id}) — 그룹 {group}, 최대 +{max_level}")
        need_ruins = defaultdict(int)
        for level in range(1, max_level + 1):
            level_costs = costs[group].get(level)
            if not level_costs:
                print(f"  [오류] +{level} 비용 없음")
                problems += 1
                continue
            value = 0
            parts = []
            for material, amount in level_costs.items():
                if material not in items:
                    print(f"  [오류] +{level}: 없는 재료 {material}")
                    problems += 1
                    continue
                value += int(items[material]["price"]) * amount
                parts.append(f"{items[material]['name']} {amount}")
                if material in ruins_items:
                    need_ruins[material] += amount
            print(f"  +{level}: {', '.join(parts)}  (재료 가치 {value})")
        if need_ruins:
            runs = max(need / yields[m] for m, need in need_ruins.items())
            detail = ", ".join(f"{items[m]['name']} {n}개({n / yields[m]:.1f}회)" for m, n in need_ruins.items())
            print(f"  유적 재료 합계: {detail} → 병목 기준 약 {runs:.1f}회")

    print(f"\n문제 {problems}개")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
