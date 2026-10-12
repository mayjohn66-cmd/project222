#!/usr/bin/env python3
"""경제 점검 도구: 원정 1회 기대 획득, 손님 취향별 객단가와 시작 재고 커버율, 비밀 상인 가격 기준.

모델(게임 규칙과 같게, 단 도구 효과·이벤트 보정 등은 생략):
- 방 수 = 난이도 room_count(마지막 방 = 보스). 중간 방 종류는 지역 expedition_map_nodes 가중치로 뽑는다.
- 방 하나당 드롭 굴림 1회: 전투=적의 loot_table, 채집/보물/미지=이벤트가 가리키는 테이블(이벤트 가중치).
- 굴림: 난이도 min~max 조건에 맞는 행, 희귀도 2 이상(두루마리 포함)은 가중치 x rare_chance_mult, 수량은 올림(min~max x reward_amount_mult).
- 가치 = 아이템 판매가 x 수량(두루마리·보물 지도는 가치 0으로 두고 개수만 센다).
- 방 하나의 실제 플레이 시간(ROOM_SECONDS)은 측정하지 못한 가정값이다.
사용: python tools/balance/check_economy.py .
"""
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path

ROOM_SECONDS = 45          # 가정: 방 하나 평균 실제 시간(초). 실제 플레이로 측정해서 고칠 것.
PREP_SECONDS = 60          # 가정: 준비 화면(가방·장비)
ENTER = 0.65
REGIONS = ["forest", "mine", "swamp", "hidden_ruins"]
START_ITEMS = {"water", "bread", "potion"}  # 시작 재고 상품(GameConfig.STARTING_INVENTORY)


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values()))]


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    items = {r["id"]: r for r in read(root / "data/core/items.csv")}
    price = {k: int(v["price"]) for k, v in items.items()}
    rarity = {k: int(v["rarity"] or 0) for k, v in items.items()}
    tiers = {int(r["difficulty"]): r for r in read(root / "data/expedition/expedition_difficulty.csv")}
    node_w = defaultdict(dict)
    for r in read(root / "data/expedition/expedition_map_nodes.csv"):
        node_w[r["region_id"]][r["node_type"]] = float(r["weight"])
    events = read(root / "data/expedition/expedition_events.csv")
    enemies = {r["id"]: r["loot_table"] for r in read(root / "data/expedition/enemies.csv")}
    loot = defaultdict(list)
    for r in read(root / "data/expedition/expedition_loot.csv"):
        loot[r["table_id"]].append(r)

    problems = 0

    def roll(table, difficulty):
        """테이블 한 번 굴림의 기대 (아이템 -> 개수)."""
        tier = tiers[difficulty]
        amount_mult = float(tier["reward_amount_mult"])
        rare_mult = float(tier["rare_chance_mult"])
        rows = []
        for r in loot.get(table, []):
            lo = int(r.get("min_difficulty") or 1)
            hi = int(r.get("max_difficulty") or 9999)
            if lo <= difficulty <= hi:
                w = float(r["weight"]) * (rare_mult if rarity.get(r["item_id"], 0) >= 2 else 1.0)
                rows.append((r["item_id"], w, int(r["min_amount"]), int(r["max_amount"])))
        total = sum(w for _, w, _, _ in rows)
        out = defaultdict(float)
        if total <= 0:
            return out
        for item, w, lo, hi in rows:
            avg = sum(math.ceil(a * amount_mult) for a in range(lo, hi + 1)) / (hi - lo + 1)
            out[item] += w / total * avg
        return out

    def table_of(event):
        if event["result_type"] == "loot":
            return event["target_id"]
        if event["result_type"] == "battle":
            return enemies.get(event["target_id"], "")
        return ""

    def room_roll(region, node_type, difficulty):
        evs = [e for e in events if e["region_id"] == region and e["node_type"] == node_type]
        total = sum(float(e["weight"]) for e in evs) or 1.0
        out = defaultdict(float)
        for e in evs:
            table = table_of(e)
            if not table:
                continue
            if table not in loot:
                print(f"[오류] 없는 드롭 테이블: {table} ({e['event_id']})")
                nonlocal_problem[0] += 1
                continue
            for item, amount in roll(table, difficulty).items():
                out[item] += float(e["weight"]) / total * amount
        return out

    nonlocal_problem = [0]

    print("== 원정 1회 기대 획득 (재료 가치 = 판매가 x 수량) ==")
    print(f"가정: 방 {ROOM_SECONDS}초, 준비 {PREP_SECONDS}초")
    run_value = {}
    for region in REGIONS:
        for d in sorted(tiers):
            rooms = int(tiers[d]["room_count"])
            weights = node_w[region]
            wtotal = sum(v for k, v in weights.items() if k in ("battle", "gather", "unknown", "treasure"))
            yields = defaultdict(float)
            for node_type, w in weights.items():
                if node_type not in ("battle", "gather", "unknown", "treasure"):
                    continue
                for item, amount in room_roll(region, node_type, d).items():
                    yields[item] += (rooms - 1) * w / wtotal * amount
            for item, amount in room_roll(region, "boss", d).items():
                yields[item] += amount
            value = sum(price[i] * a for i, a in yields.items() if not i.startswith("scroll_") and i != "treasure_map")
            scrolls = sum(a for i, a in yields.items() if i.startswith("scroll_"))
            maps = yields.get("treasure_map", 0.0)
            minutes = (rooms * ROOM_SECONDS + PREP_SECONDS) / 60
            run_value[(region, d)] = (value, minutes)
            top = ", ".join(f"{items[i]['name']} {a:.1f}" for i, a in sorted(yields.items(), key=lambda kv: -price.get(kv[0], 0) * kv[1])[:4] if not i.startswith("scroll_"))
            print(f"{region:13} 난이도{d} 방{rooms}: 재료 {value:6.0f}원 / {minutes:.1f}분 = 분당 {value / minutes:5.0f}원, 두루마리 {scrolls:.2f}개, 지도 {maps:.2f}개  ({top})")

    print("\n== 손님 소분류별 객단가와 시작 재고 커버율 (재고 없음 기준 기대) ==")
    groups = {g["group_id"]: g for g in read(root / "data/shop/catalogs/customer/customer_groups.csv")}
    types = read(root / "data/shop/catalogs/customer/customer_types.csv")
    demands = defaultdict(list)
    for r in read(root / "data/shop/catalogs/customer/customer_demands.csv"):
        demands[r["customer_type_id"]].append((r["target_type"], r["target_id"], float(r["weight"])))
    sellable = {i for i, r in items.items() if r["sellable"].lower() == "true"}
    by_category = defaultdict(list)
    for i in sellable:
        by_category[items[i]["category"]].append(i)
    RARITY_W = {0: 100.0, 1: 100.0, 2: 60.0, 3: 30.0}

    def shares(tid, gid):
        merged = {}
        for owner in ([gid] if gid != tid else []) + [tid]:
            for kind, target, weight in demands.get(owner, []):
                merged[(kind, target)] = weight
        usable = [(k, x, w) for (k, x), w in merged.items() if k == "item" or by_category.get(x)]
        total = sum(w for _, _, w in usable) or 1.0
        out = defaultdict(float)
        for kind, target, weight in usable:
            if kind == "item":
                out[target] += weight / total
            else:
                ids = by_category[target]
                ws = {i: RARITY_W[rarity[i]] for i in ids}
                s = sum(ws.values())
                for i in ids:
                    out[i] += weight / total * ws[i] / s
        return out

    type_price, type_cover, type_share = {}, {}, {}
    for g in groups:
        gt = [t for t in types if t["group_id"] == g]
        wsum = sum(float(t["weight"]) for t in gt) or 1.0
        for t in gt:
            sh = shares(t["customer_type_id"], g)
            type_price[t["customer_type_id"]] = sum(price[i] * s for i, s in sh.items())
            type_cover[t["customer_type_id"]] = sum(s for i, s in sh.items() if i in START_ITEMS)
            type_share[t["customer_type_id"]] = (g, float(t["weight"]) / wsum)
    gtotal = sum(float(g["weight"]) for g in groups.values())
    avg_price = cover_all = 0.0
    for g, gd in groups.items():
        gw = float(gd["weight"]) / gtotal
        for t in [t for t in types if t["group_id"] == g]:
            w = gw * type_share[t["customer_type_id"]][1]
            avg_price += w * type_price[t["customer_type_id"]]
            cover_all += w * type_cover[t["customer_type_id"]]
    for g, gd in groups.items():
        line = []
        for t in [t for t in types if t["group_id"] == g]:
            tid = t["customer_type_id"]
            line.append(f"{t['display_name']} {type_price[tid]:.0f}원/커버 {type_cover[tid] * 100:.0f}%")
        print(f"{gd['display_name']:8} " + ", ".join(line))
    print(f"기본 가중치 기준 평균 객단가 {avg_price:.0f}원, 시작 재고(물·빵·상비약)로 채워지는 수요 {cover_all * 100:.0f}%")
    per_day = 27.0
    print(f"하루 {per_day:.0f}명 x {avg_price:.0f}원 = 재고가 충분할 때 하루 최대 매출 약 {per_day * avg_price:,.0f}원")

    print("\n== 원정 필요 횟수 (상점을 채우려면) ==")
    need_value = per_day * avg_price / 2.5  # 제작 상품 가격 = 원가의 2.5배 규칙
    best = {}
    for region in REGIONS[:3]:
        v, m = run_value[(region, 1)]
        best[region] = (v, m)
        print(f"{region:8} 난이도1: 하루 재료 가치 {need_value:,.0f}원이 필요 -> 원정 {need_value / v:.1f}회/일 ({need_value / v * m:.1f}분/일, 하루 = 10분)")

    print("\n== 비밀 상인 가격 점검 ==")
    merchant = read(root / "data/shop/catalogs/economy/secret_merchant.csv")
    ruins_v, ruins_m = run_value[("hidden_ruins", 1)]
    other_avg = sum(v for v, _ in best.values()) / len(best)
    for r in merchant:
        item = r["item_id"]
        p = int(r["price"])
        if item == "scroll_random":
            print(f"{item:15} {p}원(희귀도 2) / 희귀도 3은 2배 -> 레시피 하나 = 상품 마진 x 판매량으로 회수")
            continue
        base = price.get(item, 0)
        print(f"{item:15} {p:5}원" + (f" (판매가 {base}원의 {p / base:.1f}배)" if base else " (판매가 없음: 획득 대안 = 보스 확률 드롭)"))
    print(f"유적 1회 재료 가치 {ruins_v:.0f}원 vs 다른 지역 평균 {other_avg:.0f}원 -> 지도 1장의 초과 가치 약 {max(ruins_v - other_avg, 0):.0f}원")
    print(f"문제 {problems + nonlocal_problem[0]}개")
    return 1 if (problems + nonlocal_problem[0]) else 0


if __name__ == "__main__":
    sys.exit(main())
