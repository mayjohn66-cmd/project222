#!/usr/bin/env python3
"""상품 레시피 가격 점검·적용 도구.

공식: 상품 가격 = 재료 원가(재료 판매가 × 수량의 합) × 마진, 10원 단위 반올림
  - 마진 2.5, 재료 중 희귀도 3(매우 드묾)이 있으면 2.8
  - 기존 상품(FIXED_PRODUCTS)은 시작 데이터라 가격을 바꾸지 않고 배율만 보여 준다.

사용:
  python tools/recipe_prices.py .            # 표만 출력
  python tools/recipe_prices.py . --apply    # items.csv의 새 상품 가격을 공식대로 갱신
"""
import csv
import sys
from pathlib import Path

MARGIN = 2.5
MARGIN_TOP_RARITY = 2.8
FIXED_PRODUCTS = {"water", "bread", "herb_drink", "potion"}


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values()))]


def round10(value):
    return int(round(value / 10.0)) * 10


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else ".")
    apply = "--apply" in sys.argv

    items = {r["id"]: r for r in read(root / "data/core/items.csv")}
    recipes = read(root / "data/production/product_recipes.csv")
    ingredients = {}
    for r in read(root / "data/production/product_recipe_ingredients.csv"):
        ingredients.setdefault(r["recipe_id"], []).append(r)

    new_prices = {}
    problems = 0
    print(f"{'상품':<16}{'현재':>6}{'원가':>6}{'공식':>6}{'배율':>7}{'제작(초)':>9}{'초당이익':>9}")

    for recipe in recipes:
        rid = recipe["recipe_id"]
        result = recipe["result_item_id"]
        cost = 0
        top_rarity = False

        for ing in ingredients.get(rid, []):
            item = items.get(ing["item_id"])
            if item is None:
                print(f"[오류] {rid}: 재료 {ing['item_id']} 없음")
                problems += 1
                continue
            cost += int(item["price"]) * int(ing["amount"])
            if int(item.get("rarity") or 0) >= 3:
                top_rarity = True

        formula = round10(cost * (MARGIN_TOP_RARITY if top_rarity else MARGIN))
        current = int(items[result]["price"]) if result in items else 0
        seconds = int(recipe["craft_time"])
        shown = current if result in FIXED_PRODUCTS else formula
        mark = " (기존 유지)" if result in FIXED_PRODUCTS else ""
        print(
            f"{result:<16}{current:>6}{cost:>6}{formula:>6}"
            f"{(shown / cost if cost else 0):>6.2f}x{seconds:>9}"
            f"{((shown - cost) / seconds if seconds else 0):>9.2f}{mark}"
        )

        if result not in FIXED_PRODUCTS:
            new_prices[result] = formula

    if apply:
        path = root / "data/core/items.csv"
        lines = path.read_text(encoding="utf-8").split("\n")
        changed = 0
        for i, line in enumerate(lines):
            cells = line.split(",")
            if cells and cells[0] in new_prices and int(cells[4]) != new_prices[cells[0]]:
                cells[4] = str(new_prices[cells[0]])
                lines[i] = ",".join(cells)
                changed += 1
        path.write_text("\n".join(lines), encoding="utf-8", newline="")
        print(f"\nitems.csv 가격 {changed}개 갱신")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
