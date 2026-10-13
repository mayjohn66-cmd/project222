#!/usr/bin/env python3
"""계산 스캔 성공률표(읽기 전용). 사용: python tools/balance/check_checkout.py .
data/shop/catalogs/economy/checkout_settings.csv 의 값으로, 플레이어가 커서가 목표를 지나는 순간을
평균 0·표준편차 σ초의 오차로 누른다고 보고 판정별 확률과 기대 팁을 계산한다.
  σ 0.05초 ≈ 익숙한 손, 0.10초 ≈ 보통, 0.15초 ≈ 서툰 손(또는 지연이 큰 환경)
커서 속도 v = 1 / scan_sweep_seconds (막대 길이 / 초). 위치 오차 ~ N(0, vσ).
"""
import csv, math, sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
cfg = {}
with open(root / "data/shop/catalogs/economy/checkout_settings.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        if r["key"] and not r["key"].startswith("#"):
            cfg[r["key"]] = float(r["value"])

v = 1.0 / cfg["scan_sweep_seconds"]
perfect, good = cfg["scan_perfect_half"], cfg["scan_good_half"]
limit = int(cfg["scan_miss_limit"])
tip_rate, tip_min = cfg["tip_rate"], cfg["tip_min"]

def within(half, sigma_pos):
    return math.erf(half / (sigma_pos * math.sqrt(2)))

print(f"커서 속도 {v:.2f}/초, 완벽 ±{perfect}, 보통 ±{good}, 빗나감 한도 {limit}, 팁 {tip_rate:.0%}")
print()
print(f"{'σ(초)':>6} {'완벽':>7} {'보통':>7} {'빗나감':>7} {'자동계산':>8} {'시도평균':>8} | 가격별 기대 팁(G) 30 / 100 / 300")
for sigma in (0.05, 0.10, 0.15):
    sp = v * sigma
    p_perf = within(perfect, sp)
    p_good = within(good, sp) - p_perf
    p_miss = 1 - p_perf - p_good
    p_fail = p_miss ** limit
    # 한 번의 계산에서 완벽으로 끝날 확률 = 첫 시도 완벽 + (빗나가고 두 번째 완벽) ...
    p_end_perf = sum((p_miss ** k) * p_perf for k in range(limit))
    attempts = sum(p_miss ** k for k in range(limit))
    tips = [p_end_perf * max(math.ceil(price * tip_rate), tip_min) for price in (30, 100, 300)]
    print(f"{sigma:>6.2f} {p_perf:>7.0%} {p_good:>7.0%} {p_miss:>7.0%} {p_fail:>8.1%} {attempts:>8.2f} | "
          + " / ".join(f"{t:.1f}" for t in tips))
print()
print("읽는 법: 완벽/보통/빗나감은 한 번 눌렀을 때 확률. 자동계산은 빗나감 한도를 넘겨 팁 없이 끝나는 비율.")
print("직원은 이 표와 상관없이 1.2초 자동 계산(팁 없음)이다.")
