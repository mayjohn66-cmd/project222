#!/usr/bin/env python3
"""가격 단계 기대 수익표(읽기 전용). 사용: python tools/balance/check_pricing.py .
data/shop/catalogs/economy/pricing_*.csv 의 값으로 손님 종류별·단계별 기대 판매량과 이익을 계산한다.
  판매량 지수 = 구매 확률(비쌀 때) 또는 1 + 한 개 더 살 확률(쌀 때)
  이익 지수  = (배율 - 원가율) / (1 - 원가율) x 판매량 지수   → 기본 단계(배율 1.0)의 이익을 1.00으로 본다
원가율은 재료값 x 2.5 = 가격 규칙(CLAUDE.md·recipe_prices.py)에서 0.4로 둔다.
"""
import csv, sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
E = root / "data/shop/catalogs/economy"
COST = 0.4

def rows(p):
    with open(p, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values())) and not next(iter(r.values())).startswith("#")]

steps = {int(r["step"]): (r["label"], float(r["multiplier"])) for r in rows(E / "pricing_steps.csv")}
sens = {r["group_id"]: float(r["sensitivity"]) for r in rows(E / "pricing_sensitivity.csv")}
cfg = {r["key"]: float(r["value"]) for r in rows(E / "pricing_settings.csv")}
weights = {r["group_id"]: float(r["weight"]) for r in rows(root / "data/shop/catalogs/customer/customer_groups.csv")}

def volume(g, r):
    if r > 1: return max(cfg["min_accept"], min(1.0, 1 - sens[g] * (r - 1) * cfg["expensive_slope"]))
    if r < 1: return 1 + min(cfg["max_bonus"], sens[g] * (1 - r) * cfg["cheap_bonus_slope"])
    return 1.0

def profit(g, r):
    return (r - COST) / (1 - COST) * volume(g, r)

problems = []
print("가격 단계별 이익 지수(기본 단계 = 1.00, 원가율 %.0f%%)" % (COST * 100))
head = "손님".ljust(12) + "".join(steps[s][0].rjust(10) for s in sorted(steps)) + "   최적"
print(head)
for g in sens:
    vals = {s: profit(g, steps[s][1]) for s in steps}
    best = max(vals, key=vals.get)
    print(g.ljust(12) + "".join(("%.2f" % vals[s]).rjust(10) for s in sorted(steps)) + "   " + steps[best][0])
    if g not in weights: problems.append("손님 대분류 %s의 weight 없음" % g)
total = sum(weights.get(g, 0) for g in sens)
avg = {s: sum(weights.get(g, 0) * profit(g, steps[s][1]) for g in sens) / total for s in steps}
print("가중 평균".ljust(12) + "".join(("%.2f" % avg[s]).rjust(10) for s in sorted(steps)) + "   " + steps[max(avg, key=avg.get)][0])
print()
print("판매량 지수(비쌀 때는 구매 확률)")
for g in sens:
    print(g.ljust(12) + "".join(("%.2f" % volume(g, steps[s][1])).rjust(10) for s in sorted(steps)))

# 판단 기준: 기본값이 정확히 1.00, 한쪽 끝이 모든 손님에게 항상 최선이면 의미가 없다.
if abs(avg[0] - 1.0) > 1e-9: problems.append("기본 단계의 가중 평균 이익이 1.00이 아님")
if max(avg, key=avg.get) in (min(steps), max(steps)): problems.append("가중 평균으로 가장 이익인 단계가 끝 단계다(한쪽으로 쏠림)")
best_by_group = {g: max(steps, key=lambda s: profit(g, steps[s][1])) for g in sens}
if len(set(best_by_group.values())) < 2: problems.append("모든 손님의 최적 단계가 같다(손님 구성이 가격 선택에 영향을 주지 않음)")
if any(best_by_group[g] == min(steps) for g in sens): problems.append("값을 가장 싸게 팔아야 이익인 손님이 있다")
print()
print("문제 %d개" % len(problems))
for p in problems: print(" -", p)
