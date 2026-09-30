#!/usr/bin/env python3
"""손님 도착률 점검: data/shop/customer_arrival.csv의 하루 방문 수와 시간대별 합계.

손님 생성기는 생성 틱(기본 5초)마다 확률 = λ × 틱 간격 / 게임 1시간(초) / 입장 확률로 행인을 만든다.
이 스크립트는 그 확률이 1을 넘지 않는지(클램프로 λ가 깎이는지)도 확인한다.
사용: python tools/check_arrival.py .
"""
import csv
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
rates = {int(r["hour"]): float(r["rate"]) for r in csv.DictReader(open(root / "data/shop/customer_arrival.csv", encoding="utf-8"))}

TICK = 5.0          # SpawnTimer.wait_time
HOUR_SEC = 25.0     # HourTimer.wait_time
INTEREST = 0.65     # base_store_interest_chance

print("시간대별 도착(명/6시간)")
periods = [("아침 06~12", range(6, 12)), ("낮 12~18", range(12, 18)), ("저녁 18~24", range(18, 24)), ("심야 00~06", range(0, 6))]
for name, hours in periods:
    print(f"  {name}: {sum(rates.get(h, 0) for h in hours):.1f}명")
print(f"하루 합계: {sum(rates.values()):.1f}명 (24시간)")

worst = max(rates.values()) * TICK / HOUR_SEC / INTEREST
print(f"최대 행인 생성 확률/틱: {worst:.2f} (1.0을 넘으면 λ가 깎임)")
