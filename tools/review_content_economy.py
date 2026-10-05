#!/usr/bin/env python3
"""콘텐츠 경제 검토(2026-10-05): 데이터 파일만 읽어 부탁·주문 대금, 식품 기한, 가구 투자, 마석 개조를 계산한다.
사용: python tools/review_content_economy.py [저장소 루트]
"""
import csv, glob, json, os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."

def rows(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return list(csv.DictReader(f))

ITEMS = {r["id"]: r for r in rows("data/core/items.csv")}
def price(i): return int(ITEMS[i]["price"]) if i in ITEMS else 0
def name(i): return ITEMS[i]["name"] if i in ITEMS else i

def events():
    out = {}
    for f in glob.glob(os.path.join(ROOT, "scenes/shop/requests/default_*.tres")):
        if "act_four" in f: continue
        for line in open(f, encoding="utf-8"):
            line = line.strip().rstrip(",")
            if not line.startswith('{"id"'): continue
            try: d = json.loads(line)
            except Exception: continue
            d["_file"] = os.path.basename(f)
            out[d["id"]] = d
    return out
EV = events()

def req_items(e):
    items = []
    if "item" in e and "amount" in e: items.append((e["item"], e["amount"]))
    for r in e.get("requirements", []): items.append((r["item"], r["amount"]))
    for s in e.get("steps", []):
        for r in s.get("requirements", []): items.append((r["item"], r["amount"]))
    return items

def value(items): return sum(price(i) * a for i, a in items)

print("# 콘텐츠 경제 검토 계산 (자동 출력)\n")

# 1. 대금이 있는 부탁·주문: 요구 물품 가치 대비 대금
print("## 1. 부탁·주문의 대금 / 요구 물품 가치\n")
print("| 사건 | 파일 | 요구 | 가치 | 대금 | 대금/가치 |\n|---|---|---|---|---|---|")
table = []
for i, e in EV.items():
    m = e.get("money")
    items = req_items(e)
    if not m or not items: continue
    v = value(items)
    table.append((m / v if v else 0, i, e["_file"], items, v, m))
for ratio, i, f, items, v, m in sorted(table):
    print("| %s | %s | %s | %dG | %dG | %.2f |" % (i, f.replace("default_", "").replace(".tres", ""), ", ".join("%s×%d" % (name(a), b) for a, b in items), v, m, ratio))

# 2. 마석 개조
print("\n## 2. 마석 발전기 개조\n")
t = open(os.path.join(ROOT, "scenes/shop/power/default_power_repair.tres"), encoding="utf-8").read()
fee = int(re.search(r"fee = (\d+)", t).group(1))
req = [(m["item"], int(m["amount"])) for m in re.findall(r'\{"item":"(\w+)","amount":(\d+)\}', t) and [dict(item=a, amount=b) for a, b in re.findall(r'\{"item":"(\w+)","amount":(\d+)\}', t)]]
mat = value(req)
print("- 개조비 %dG + 재료 %s = 가치 %dG (총 %dG)" % (fee, ", ".join("%s×%d" % (name(a), b) for a, b in req), mat, fee + mat))
print("- 비교: 시작 식품 빵 1개 판매가 %dG, 원정 숲 1회(난이도1) 재료 약 525G" % price("bread"))

# 3. 식품 기한
print("\n## 3. 식품 기한과 마감 할인\n")
sl = {r["item_id"]: r for r in rows("data/shop/catalogs/food_shelf_life.csv")}
rec = {}
for r in rows("data/production/product_recipes.csv"): rec[r["result_item_id"]] = r
ing = {}
for r in rows("data/production/product_recipe_ingredients.csv"):
    ing.setdefault(r["recipe_id"], []).append((r["item_id"], int(r["amount"])))
print("| 식품 | 판매가 | 재료 원가 | 상온 기한 | 마감 할인가(−30%) | 할인 후 마진 | 폐기 시 손실(원가) |\n|---|---|---|---|---|---|---|")
for item, r in sl.items():
    p = price(item)
    rid = rec[item]["recipe_id"] if item in rec else None
    cost = value(ing.get(rid, [])) if rid else 0
    disc = max(1, p * 70 // 100)
    print("| %s | %dG | %dG | %s일 | %dG | %dG (%d%%) | %dG |" % (name(item), p, cost, r["shelf_life_days"], disc, disc - cost, round((disc - cost) * 100 / cost) if cost else 0, cost))
print("- 퇴비 재료 판매가: %dG (만료 식품 2개 → 1개)" % price("food_compost"))

# 4. 가구
print("\n## 4. 진열대·창고 (같은 자리 대비 용량과 재료 가치)\n")
cap = {r["id"]: r for r in rows("data/shop/catalogs/shelf_data.csv")}
prog = {r["id"]: r for r in rows("data/shop/catalogs/furniture_progression.csv")}
fr = {}
for r in rows("data/production/furniture_recipes.csv"):
    fr.setdefault(r["furniture_id"], []).append((r["item_id"], int(r["amount"])))
print("같은 ID 한 개를 더 소비해 층을 쌓으므로 **한 층 = 가구 1개** 기준으로 비교한다.\n")
print("| 가구 | 단계 | 재료 가치(1개) | 한 층 수용(칸×칸당) | 한 층 수용 1개당 재료 가치 | 최대 층 | 최대 층수 수용 |\n|---|---|---|---|---|---|---|")
for fid, c in cap.items():
    v = value(fr.get(fid, []))
    level = int(c["slots_per_level"]) * int(c["slot_capacity"])
    stage = prog[fid]["stage"] if fid in prog else "기존"
    print("| %s | %s | %dG | %s×%s = %d | %.1fG | %s | %d |" % (fid, stage, v, c["slots_per_level"], c["slot_capacity"], level, v / level if level else 0, c["max_stack_level"], level * int(c["max_stack_level"])))
for fid, p in prog.items():
    if p["family"] in ("warehouse_storage", "register", "decoration"):
        v = value(fr.get(fid, []))
        extra = "창고 %s개/%s칸" % (p["storage_capacity"], p["storage_slots"]) if p["family"] == "warehouse_storage" else ""
        print("| %s | %s | %dG | %s | | | |" % (fid, p["stage"], v, extra))
