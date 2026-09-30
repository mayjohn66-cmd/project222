#!/usr/bin/env python3
"""손님 대분류·소분류와 수요 데이터 점검 도구.

- customer_groups.csv(대분류)와 customer_types.csv(소분류)의 연결, 계절·시간대 가중치 형식
- customer_demands.csv: 대분류 수요 + 소분류 수정(같은 대상은 덮어쓰기, 0이면 제거)의 품목·카테고리가 실제로 있고 판매 가능한지
- 이벤트 CSV의 손님 ID가 대분류 또는 소분류인지
- 소분류마다 "재고가 없을 때"의 품목별 기대 비율 상위(희귀도 가중치 적용, 카테고리 안은 균등 뽑기)
- 시간대(아침/낮/저녁/심야) x 계절별 대분류 구성비(이벤트·치장 제외)

사용: python tools/check_demand.py .
"""
import csv
import sys
from collections import defaultdict
from pathlib import Path

RARITY_WEIGHTS = {0: 100.0, 1: 100.0, 2: 60.0, 3: 30.0}  # GameConfig.DEMAND_RARITY_WEIGHTS 와 같게
PERIODS = [("morning", "아침"), ("day", "낮"), ("evening", "저녁"), ("night", "심야")]
SEASONS = [("spring", "봄"), ("summer", "여름"), ("autumn", "가을"), ("winter", "겨울")]


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values()))]


def parse_map(text, where, keys):
    result = {}
    for part in filter(None, text.split("|")):
        key, _, value = part.partition(":")
        if key not in keys:
            print(f"[오류] {where}: 알 수 없는 키 {key}")
            return None
        try:
            result[key] = float(value)
        except ValueError:
            print(f"[오류] {where}: 숫자가 아님 {part}")
            return None
    return result


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    items = {r["id"]: r for r in read(root / "data/core/items.csv")}
    sellable = {i for i, r in items.items() if r["sellable"].lower() == "true"}
    by_category = defaultdict(list)
    for i in sellable:
        by_category[items[i]["category"]].append(i)

    groups = {g["group_id"]: g for g in read(root / "data/shop/catalogs/customer_groups.csv")}
    types = read(root / "data/shop/catalogs/customer_types.csv")
    type_ids = {t["customer_type_id"] for t in types}
    problems = 0

    season_w, period_w = {}, {}
    for gid, g in groups.items():
        sw = parse_map(g["season_weights"], f"{gid}.season_weights", {k for k, _ in SEASONS})
        pw = parse_map(g["period_weights"], f"{gid}.period_weights", {k for k, _ in PERIODS})
        if sw is None or pw is None:
            problems += 1
        season_w[gid], period_w[gid] = sw or {}, pw or {}

    for t in types:
        if t["group_id"] not in groups:
            print(f"[오류] 소분류의 대분류가 없음: {t['customer_type_id']} -> {t['group_id']}")
            problems += 1
        if t["customer_type_id"] in groups:
            print(f"[오류] 소분류 ID가 대분류 ID와 겹침: {t['customer_type_id']}")
            problems += 1
    for gid in groups:
        if not any(t["group_id"] == gid for t in types):
            print(f"[오류] 소분류가 없는 대분류: {gid}")
            problems += 1

    owners = set(groups) | type_ids
    demands = defaultdict(list)
    for r in read(root / "data/shop/catalogs/customer_demands.csv"):
        t, kind, target, weight = r["customer_type_id"], r["target_type"], r["target_id"], float(r["weight"])
        if t not in owners:
            print(f"[오류] 수요 행의 손님 ID가 없음: {t}")
            problems += 1
        if kind == "item" and target not in sellable:
            print(f"[오류] {t}: 판매할 수 없거나 없는 품목: {target}")
            problems += 1
        if kind == "category" and not by_category.get(target):
            print(f"[경고] {t}: 판매 가능한 품목이 없는 카테고리(무시됨): {target}")
        demands[t].append((kind, target, weight))

    for name in ("store_event_customer_modifiers.csv", "store_event_demands.csv"):
        for r in read(root / "data/shop/events" / name):
            cid = r["customer_type_id"]
            if cid != "any" and cid not in owners:
                print(f"[오류] {name}: 손님 ID가 없음: {cid}")
                problems += 1

    def merged(tid, gid):
        """대분류 수요 위에 소분류 수요를 덮어쓴다(코드 CustomerDemandData.get_merged_base_entries와 같은 규칙)."""
        result = {}
        for owner in ([gid] if gid != tid else []) + [tid]:
            for kind, target, weight in demands.get(owner, []):
                result[(kind, target)] = weight
        return [(k, x, w) for (k, x), w in result.items()]

    print("== 소분류별 원하는 품목(재고 없을 때 기대 비율) ==")
    for gid, g in groups.items():
        group_types = [t for t in types if t["group_id"] == gid]
        group_total = sum(float(t["weight"]) for t in group_types) or 1.0
        print(f"\n[{g['display_name']} ({gid})]")
        for t in group_types:
            tid = t["customer_type_id"]
            rows = merged(tid, gid)
            if not rows:
                print(f"[오류] 수요 행이 없는 손님: {tid}")
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
            top = sorted(share.items(), key=lambda kv: -kv[1])[:5]
            pct = float(t["weight"]) / group_total * 100
            print(f"  {t['display_name']} ({tid}) — 대분류 안 {pct:.0f}%")
            print("    " + ", ".join(f"{items[i]['name']} {v * 100:.0f}%" for i, v in top))

    print("\n== 시간대 x 계절별 대분류 구성비(%) ==")
    for season, season_name in SEASONS:
        print(f"\n[{season_name}]")
        print("  " + "".join(f"{name:>8}" for _, name in PERIODS))
        for gid, g in groups.items():
            cells = []
            for period, _ in PERIODS:
                weights = {
                    x: float(groups[x]["weight"]) * season_w[x].get(season, 1.0) * period_w[x].get(period, 1.0)
                    for x in groups
                }
                cells.append(weights[gid] / (sum(weights.values()) or 1.0) * 100)
            print(f"  {g['display_name']:<6}" + "".join(f"{c:>7.0f}%" for c in cells))

    print(f"\n문제 {problems}개")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
