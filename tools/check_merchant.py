#!/usr/bin/env python3
"""비밀 상인 밸런스 점검: 판매 목록의 진열 기대치, 방문 주기와 소비 규모, 물건별 가치 대비 가격.

가정(측정하지 못한 값은 표시): 하루 손님 27명, 평균 객단가는 check_economy.py와 같은 방식, 상인은 밤마다 10% 확률로 방문.
사용: python tools/check_merchant.py .
"""
import csv
import sys
from collections import defaultdict
from pathlib import Path

NIGHT_CHANCE = 0.10
PER_DAY = 27.0
RUN_MINUTES = 5.5          # 난이도 1 원정 1회(가정: 방 45초, 준비 60초)
DAY_MINUTES = 10.0


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values()))]


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    items = {r["id"]: r for r in read(root / "data/core/items.csv")}
    furniture = {r["id"]: r for r in read(root / "data/shop/catalogs/furniture_items.csv")}
    merchant = read(root / "data/shop/catalogs/secret_merchant.csv")
    price = {k: int(v["price"]) for k, v in items.items()}
    groups = {g["group_id"]: g for g in read(root / "data/shop/catalogs/customer_groups.csv")}
    types = read(root / "data/shop/catalogs/customer_types.csv")
    demands = defaultdict(list)
    for r in read(root / "data/shop/catalogs/customer_demands.csv"):
        demands[r["customer_type_id"]].append((r["target_type"], r["target_id"], float(r["weight"])))
    rates = [float(r["rate"]) for r in read(root / "data/shop/customer_arrival.csv")]
    problems = 0

    # ---- 손님 대분류 비중과 객단가(하루 평균)
    periods = {"night": range(0, 6), "morning": range(6, 12), "day": range(12, 18), "evening": range(18, 24)}
    seasons = ("spring", "summer", "autumn", "winter")

    def pw(text):
        return {k: float(v) for k, v in (p.split(":") for p in text.split("|") if p)}

    share = defaultdict(float)
    for period, hours in periods.items():
        lam = sum(rates[h] for h in hours)
        for season in seasons:
            w = {g: float(d["weight"]) * pw(d["season_weights"]).get(season, 1) * pw(d["period_weights"]).get(period, 1) for g, d in groups.items()}
            total = sum(w.values())
            for g in groups:
                share[g] += lam * w[g] / total / 4
    total_visits = sum(share.values())
    for g in share:
        share[g] /= total_visits
    sellable = {i for i, r in items.items() if r["sellable"].lower() == "true"}
    by_cat = defaultdict(list)
    for i in sellable:
        by_cat[items[i]["category"]].append(i)
    rw = {0: 100.0, 1: 100.0, 2: 60.0, 3: 30.0}

    def group_price(g):
        tot = 0.0
        ts = [t for t in types if t["group_id"] == g]
        wsum = sum(float(t["weight"]) for t in ts)
        for t in ts:
            merged = {}
            for owner in (g, t["customer_type_id"]):
                for k, x, w in demands.get(owner, []):
                    merged[(k, x)] = w
            usable = [(k, x, w) for (k, x), w in merged.items() if k == "item" or by_cat.get(x)]
            s = sum(w for _, _, w in usable) or 1.0
            p = 0.0
            for k, x, w in usable:
                if k == "item":
                    p += price[x] * w / s
                else:
                    ids = by_cat[x]
                    ws = {i: rw[int(items[i]["rarity"] or 0)] for i in ids}
                    sw = sum(ws.values())
                    p += sum(price[i] * ws[i] / sw for i in ids) * w / s
            tot += p * float(t["weight"]) / wsum
        return tot

    gp = {g: group_price(g) for g in groups}
    avg_price = sum(share[g] * gp[g] for g in groups)
    day_revenue = PER_DAY * avg_price
    per_minute = day_revenue / DAY_MINUTES

    print(f"기준: 하루 손님 {PER_DAY:.0f}명, 평균 객단가 {avg_price:.0f}원, 하루 최대 매출 약 {day_revenue:,.0f}원 (재고가 충분할 때), 분당 약 {per_minute:.0f}원")
    print(f"상인 방문: 밤마다 {NIGHT_CHANCE * 100:.0f}% -> 평균 {1 / NIGHT_CHANCE:.0f}일(현실 약 {DAY_MINUTES / NIGHT_CHANCE:.0f}분)에 한 번\\n")

    print("== 판매 목록 ==")
    print(f"{'물건':14}{'가격':>7}{'수량':>6}{'진열%':>6}{'하루 매출의':>10}   근거")
    expected_offers = expected_spend = 0.0
    for r in merchant:
        i, p, lo, hi, chance, kind = r["item_id"], int(r["price"]), int(r["min_stock"]), int(r["max_stock"]), float(r["offer_chance"]), r.get("kind") or "item"
        avg_stock = (lo + hi) / 2
        expected_offers += chance / 100
        expected_spend += chance / 100 * avg_stock * p
        name = furniture[i]["name"] if kind == "furniture" and i in furniture else (items[i]["name"] if i in items else i)
        if kind == "furniture" and i not in furniture or kind == "item" and i not in items and i != "scroll_random":
            print(f"[오류] 없는 ID: {i}")
            problems += 1
            continue
        note = ""
        if i == "treasure_map":
            note = f"보스 드롭 확률 약 13%이면 지도 1장 = 원정 약 {1 / 0.13:.0f}회({1 / 0.13 * RUN_MINUTES:.0f}분) -> 분당 {p / (1 / 0.13 * RUN_MINUTES):.0f}원"
        elif kind == "item" and i in items and items[i]["item_type"] == "material":
            note = f"판매가 {price[i]}원의 {p / price[i]:.1f}배(재료 수급 단축 값)"
        elif i == "scroll_random":
            note = "희귀도 3 두루마리는 2배. 상품 마진 130~650원/개, 하루 4~5개 팔면 3~4일에 회수"
        elif kind == "item" and i in items and items[i]["item_type"] == "equipment":
            note = f"공격 방식 특수({'무기' if int(items[i]['attack']) else '방어구'}), 강화 그룹 night_*(희귀 재료)"
        elif i == "night_lantern":
            # 평판 2.0 -> 방문 +0.5*2/(10+2)=8.3%, 입장 확률 +4% 정도 => 손님 약 +12%
            extra = PER_DAY * 0.12 * avg_price
            note = f"평판 +2로 손님 약 +12% -> 하루 +{extra:,.0f}원(재고 충분 시), 회수 {p / extra:.1f}일"
        elif kind == "furniture":
            e = furniture[i]
            g = e["effect_target"]
            b = float(e["effect_value"])
            b_eff = b / (1 + b)   # 곡선 CUSTOMER_WEIGHT_HALF_VALUE=1, MAX=1
            s = share[g]
            s2 = s * (1 + b_eff) / (1 + s * b_eff)
            note = f"{groups[g]['display_name']} 비중 {s * 100:.1f}% -> {s2 * 100:.1f}% (객단가 {gp[g]:.0f}원 vs 평균 {avg_price:.0f}원이라 매출 변화는 거의 없고 손님 구성이 바뀌는 효과)"
        print(f"{name:12}{p:7,}{f'{lo}~{hi}':>6}{chance:6.0f}{p / day_revenue * 100:9.0f}%   {note}")

    print(f"\\n한 번 방문의 기대 진열 {expected_offers:.1f}종, 전부 사면 약 {expected_spend:,.0f}원 (하루 최대 매출의 {expected_spend / day_revenue:.1f}배)")
    print(f"골드 용도 참고: 확장 비용 매장 5,000/15,000/40,000, 창고 7,000/22,000/55,000, 생산실 8,000/25,000/60,000")
    print(f"문제 {problems}개")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
