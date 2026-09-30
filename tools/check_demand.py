#!/usr/bin/env python3
"""손님 유형별 수요 데이터 점검 도구.

- customer_types.csv 의 모든 유형에 수요 행(customer_demands.csv)이 있는지
- 수요 행의 카테고리·품목이 실제로 있고 판매 가능한지(품목 행)
- 이벤트 CSV의 유형 ID가 실제 유형인지
- 유형마다 "재고가 없을 때"의 품목별 기대 비율 상위를 출력한다(희귀도 가중치 적용, 카테고리 안은 균등 뽑기).

사용: python tools/check_demand.py .
"""
import csv
import sys
from collections import defaultdict
from pathlib import Path

RARITY_WEIGHTS = {0: 100.0, 1: 100.0, 2: 60.0, 3: 30.0}  # GameConfig.DEMAND_RARITY_WEIGHTS 와 같게


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values()))]


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    items = {r["id"]: r for r in read(root / "data/core/items.csv")}
    sellable = {i for i, r in items.items() if r["sellable"].lower() == "true"}
    by_category = defaultdict(list)
    for i in sellable:
        by_category[items[i]["category"]].append(i)

    types = read(root / "data/shop/catalogs/customer_types.csv")
    type_ids = {t["customer_type_id"] for t in types}
    demands = defaultdict(list)
    problems = 0

    for r in read(root / "data/shop/catalogs/customer_demands.csv"):
        t, kind, target, weight = r["customer_type_id"], r["target_type"], r["target_id"], float(r["weight"])
        if t not in type_ids:
            print(f"[오류] 수요 행의 손님 유형이 없음: {t}")
            problems += 1
        if kind == "item" and target not in sellable:
            print(f"[오류] {t}: 판매할 수 없거나 없는 품목: {target}")
            problems += 1
        if kind == "category" and not by_category.get(target):
            print(f"[경고] {t}: 판매 가능한 품목이 없는 카테고리(무시됨): {target}")
        demands[t].append((kind, target, weight))

    for name in ("store_event_customer_modifiers.csv", "store_event_demands.csv"):
        for r in read(root / "data/shop/events" / name):
            if r["customer_type_id"] not in type_ids:
                print(f"[오류] {name}: 손님 유형이 없음: {r['customer_type_id']}")
                problems += 1

    total_type_weight = sum(float(t["weight"]) for t in types)

    for t in types:
        tid = t["customer_type_id"]
        rows = demands.get(tid, [])
        if not rows:
            print(f"[오류] 수요 행이 없는 손님 유형: {tid}")
            problems += 1
            continue

        usable = [(k, x, w) for k, x, w in rows if k == "item" or by_category.get(x)]
        total = sum(w for _, _, w in usable)
        share = defaultdict(float)
        for kind, target, weight in usable:
            if kind == "item":
                share[target] += weight / total
            else:
                ids = by_category[target]
                ws = {i: RARITY_WEIGHTS[int(items[i].get("rarity") or 0)] for i in ids}
                s = sum(ws.values())
                for i in ids:
                    share[i] += weight / total * ws[i] / s

        top = sorted(share.items(), key=lambda kv: -kv[1])[:6]
        pct = float(t["weight"]) / total_type_weight * 100
        print(f"\n{t['display_name']} ({tid}) — 손님 비율 {pct:.0f}%")
        print("  " + ", ".join(f"{items[i]['name']} {v * 100:.0f}%" for i, v in top))

    print(f"\n문제 {problems}개")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
