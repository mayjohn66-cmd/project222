"""편의점 게임 밸런스 기준선 계산기 (CSV만 읽음, 게임 코드는 건드리지 않음).
사용: python balance_baseline.py <프로젝트 루트>
가정: 손님 1명 = 아이템 1개, 카테고리 안에서는 판매 가능 아이템을 균등 선택,
      하루 손님 수 = customer_arrival.csv의 시간당 도착률 합계(24시간),
      손님은 대분류(customer_groups.csv) 기준 평균으로 계산(소분류 수정은 반영하지 않음)
"""
import csv, sys, os
root = sys.argv[1] if len(sys.argv) > 1 else "."
def rd(p):
    with open(os.path.join(root, p), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))

items = {r["id"]: r for r in rd("data/core/items.csv")}
price = {k: int(v["price"]) for k, v in items.items()}
sellable = {k for k, v in items.items() if v["sellable"] == "true"}
demands = rd("data/shop/catalogs/customer/customer_demands.csv")
types = {r["group_id"]: int(r["weight"]) for r in rd("data/shop/catalogs/customer/customer_groups.csv")}

customers_per_day = sum(float(r["rate"]) for r in rd("data/shop/customer_arrival.csv"))

def avg_price(cat):
    ids = [i for i, v in items.items() if v["category"] == cat and i in sellable]
    return (sum(price[i] for i in ids) / len(ids), len(ids)) if ids else (0, 0)

def type_stats(t):
    rows = [d for d in demands if d["customer_type_id"] == t]
    tot = live = 0
    ev = 0.0
    dead = []
    for d in rows:
        w = int(d["weight"]); tot += w
        p, n = avg_price(d["target_id"])
        if n == 0: dead.append(d["target_id"]); continue
        live += w; ev += w * p
    return ev / live, live, tot, dead

out = []
out.append("# 밸런스 기준선 (현재 CSV 기준)\n")
out.append(f"- 하루 손님 수(기대값): **{customers_per_day:.1f}명** (customer_arrival.csv 24시간 합계)\n")
out.append("## 손님 대분류별 평균 객단가\n")
out.append("| 유형 | 평균 객단가 | 유효 수요 가중치 | 무효 수요(판매 가능 아이템 없음) |\n|---|---|---|---|")
mix = 0; wsum = sum(types.values())
for t, w in types.items():
    ev, live, tot, dead = type_stats(t)
    mix += ev * w / wsum
    out.append(f"| {t} | {ev:.0f}원 | {live}/{tot} | {', '.join(dead) or '-'} |")
out.append(f"\n- 유형 가중 평균 객단가: **{mix:.0f}원**")
rev = mix * customers_per_day
out.append(f"- **하루 예상 매출: 약 {rev:,.0f}원** (진열 재고가 항상 충분하다고 가정)\n")

emps = rd("data/shop/employees/employees.csv")
sal = {e["employee_id"]: int(e["monthly_salary"]) for e in emps}
hired = [e for e in emps if e["initially_hired"] == "true"]
month_days = 28
out.append("## 고정 지출\n")
out.append(f"- 초기 고용 직원 월급 합계: {sum(int(e['monthly_salary']) for e in hired):,}원 / {month_days}일 = 하루 {sum(int(e['monthly_salary']) for e in hired)/month_days:.0f}원")
out.append(f"- 전원 고용 시: {sum(sal.values()):,}원 / {month_days}일 = 하루 {sum(sal.values())/month_days:.0f}원")
out.append(f"- 매출 대비 인건비 비중: {sum(sal.values())/month_days/rev*100:.1f}% (전원 고용 기준)\n")

out.append("## 상품 제작 마진\n")
out.append("| 상품 | 재료 원가 | 판매가 | 마진 | 제작시간 |\n|---|---|---|---|---|")
recs = {r["recipe_id"]: r for r in rd("data/production/product_recipes.csv")}
ing = rd("data/production/product_recipe_ingredients.csv")
for rid, r in recs.items():
    cost = sum(price[i["item_id"]] * int(i["amount"]) for i in ing if i["recipe_id"] == rid)
    sp = price[r["result_item_id"]] * int(r["result_amount"])
    out.append(f"| {items[r['result_item_id']]['name']} | {cost} | {sp} | {sp-cost} ({(sp-cost)/cost*100:.0f}%) | {r['craft_time']} |")

out.append("\n## 원정 재료를 그냥 판매할 때 (재료 개당 가격 x 평균 획득량)\n")
out.append("| 채집 노드 | 아이템 | 개당 | 평균 획득 | 노드당 가치 |\n|---|---|---|---|---|")
for r in rd("data/expedition/expedition_loot.csv"):
    if r["table_id"] in ("forest_gather", "mine_gather", "swamp_gather", "meadow_gather", "river_gather", "ruins_gather", "gather_iron", "gather_wheat", "gather_water") and r["item_id"] in price:
        avg = (int(r["min_amount"]) + int(r["max_amount"])) / 2
        out.append(f"| {r['table_id']} | {items[r['item_id']]['name']} | {price[r['item_id']]} | {avg:.1f} | {price[r['item_id']]*avg:.0f} |")

out.append("\n## 참고: 초기 자금\n")
out.append("- `game_config.gd`의 STARTING_MONEY / STARTING_INVENTORY는 CSV가 아니라 코드 상수라서 이 스크립트가 읽지 않음")
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "balance_baseline.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
print("\n".join(out))
