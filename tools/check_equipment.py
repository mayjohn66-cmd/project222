#!/usr/bin/env python3
"""장비 밸런스 점검: 무기 공격 프로필(.tres)·장비 CSV·제작 재료를 읽어 초당 피해와 생존력을 계산한다.

가정(코드 ExpeditionRoomModel/Settings와 같게, 이동·명중 손실은 생략한 이론치):
- 플레이어 기본 공격 12, 방어 3, 체력 100. 피해 = 공격² ÷ (공격 + 방어), 반올림, 최소 1(ExpeditionDamage와 같은 식).
- 무기 공격력 = 12 + 무기 base + 강화(+0/+4/+8). 초당 피해 = 피해 / 쿨다운, 다중 타격은 인접한 적 2마리 기준(최대 타격 수와 각도 반영).
- 적 공격은 예고 0.65초 + 쿨다운 1.1초로 약 1.75초에 1회, 방 안 일반 몬스터 2마리·보스 1마리.
사용: python tools/check_equipment.py .
"""
import csv
import re
import sys
from pathlib import Path

BASE_ATK, BASE_DEF, PLAYER_HP = 12, 3, 100


def dmg(attack, defense):
    """최종 피해(코드 ExpeditionDamage.calculate와 같은 식)."""
    if attack <= 0:
        return 1
    return max(1, round(attack * attack / (attack + max(defense, 0))))


def attack_for_hit(hit, defense):
    """방어가 defense일 때 한 방에 hit만큼 들어가게 하는 공격력(a^2/(a+d)=hit의 해)."""
    return (hit + (hit * hit + 4 * hit * defense) ** 0.5) / 2
ENEMY_CYCLE = 0.65 + 1.1


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r and next(iter(r.values()))]


def parse_profiles(tres):
    text = tres.read_text(encoding="utf-8")
    profiles = {}
    for block in re.findall(r'\[sub_resource type="Resource" id="[^"]+"\](.*?)(?=\n\[)', text, re.S):
        def val(key, default):
            m = re.search(rf"^{key} = (.+)$", block, re.M)
            return type(default)(m.group(1).strip().strip('"')) if m else default
        eid = val("equipment_id", "")
        profiles[eid] = {
            "name": val("display_name", ""), "method": val("method", 0), "cooldown": val("cooldown", 0.4),
            "reach": val("reach", 1.35), "arc": val("arc_degrees", 80.0), "targets": val("max_targets", 1),
            "kb": val("knockback", 0.0), "heal": val("heal_fraction", 0.0),
        }
    return profiles


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    items = {r["id"]: r for r in read(root / "data/core/items.csv")}
    price = {k: int(v["price"]) for k, v in items.items()}
    eq = {r["item_id"]: r for r in read(root / "data/expedition/expedition_equipment.csv")}
    profiles = parse_profiles(root / "scenes/expedition/rooms/default_room_settings.tres")
    recipes = {r["result_item_id"]: r for r in read(root / "data/production/recipes.csv")}
    unlocks = {r["recipe_id"]: r for r in read(root / "data/production/recipe_unlocks.csv")}
    tiers = {int(r["difficulty"]): r for r in read(root / "data/expedition/expedition_difficulty.csv")}
    enemies = {r["id"]: r for r in read(root / "data/expedition/enemies.csv")}
    problems = 0

    print("== 무기 (기본 공격 12 + 무기, 초당 피해 = (공격 - 적 방어) / 쿨다운 x 타격 수) ==")
    print(f"{'무기':10}{'공격+':>6}{'쿨':>6}{'사거리':>7}{'타격':>5}{'상대 방어5(보스급) 초당 피해: +0 / +4 / +8':>44}")
    weapon_rows = []
    for item_id, e in eq.items():
        if e["equipment_type"] != "weapon":
            continue
        base = float(e["base_value"])
        p = profiles.get(item_id, {"name": "기본(찌르기)", "cooldown": 0.4, "reach": 1.35, "arc": 80.0, "targets": 1, "method": 0})
        if item_id not in profiles and item_id != "rusty_sword":
            print(f"[오류] 공격 프로필이 없는 무기: {item_id}")
            problems += 1
        eff_targets = min(p["targets"], 2) if p["arc"] >= 90 else min(p["targets"], 1.5)
        dps = []
        for lvl in (0, 4, 8):
            atk = BASE_ATK + base + lvl
            dps.append(dmg(atk, 5) / p["cooldown"] * eff_targets)
        weapon_rows.append((item_id, dps))
        kind = "원거리" if p.get("method", 0) == 1 else "근접"
        print(f"{items[item_id]['name']:9}{base:6.0f}{p['cooldown']:6.2f}{p['reach']:7.2f}{p['targets']:5}   {kind} {dps[0]:5.0f} / {dps[1]:5.0f} / {dps[2]:5.0f}  ({p['name']}, 회복 {p.get('heal', 0) * 100:.0f}%, 넉백 {p.get('kb', 0)})")

    print("\n== 방어구 (방어 3 + 장비, 3부위까지 합산) ==")
    for item_id, e in eq.items():
        if e["equipment_type"] == "armor":
            b = float(e["base_value"])
            print(f"{items[item_id]['name']:8} +{b:.0f} (+8이면 +{b + 8:.0f})")

    print("\n== 난이도별 적과 세트 비교 (일반 몬스터 2마리 vs 보스 1마리) ==")
    sets = [
        ("기본(낡은 검+가죽 갑옷)", "rusty_sword", ["leather_armor"], 0),
        ("1단계 세트+4", "rusty_sword", ["leather_armor", "miner_helmet", "marsh_boots"], 4),
        ("2~3단계 세트+4(쇠창·철판)", "iron_spear", ["iron_plate", "miner_helmet", "marsh_boots"], 4),
        ("룬 세트+4", "rune_blade", ["rune_mail", "iron_plate", "miner_helmet"], 4),
    ]
    boss_ids = {"forest": "forest_alpha_slime", "mine": "mine_golem", "swamp": "swamp_queen_slime", "hidden_ruins": "ancient_guardian"}
    for name, weapon, armors, lvl in sets:
        p = profiles.get(weapon, {"cooldown": 0.4, "targets": 1, "arc": 80.0})
        atk = BASE_ATK + float(eq[weapon]["base_value"]) + lvl
        armor = BASE_DEF + sum(float(eq[a]["base_value"]) + lvl for a in armors)
        print(f"\n[{name}] 공격 {atk:.0f}, 방어 {armor:.0f}")
        for d in sorted(tiers):
            hp_m, atk_m = float(tiers[d]["monster_hp_mult"]), float(tiers[d]["monster_atk_mult"])
            cells = []
            for region, boss in boss_ids.items():
                en = enemies[boss]
                hp = float(en["max_hp"]) * hp_m
                per_hit = dmg(atk, float(en["defense"]))
                ttk = hp / per_hit * p["cooldown"]
                taken = dmg(float(en["attack"]) * atk_m, armor) / ENEMY_CYCLE
                cells.append(f"{region[:4]} 처치 {ttk:4.0f}초/받는 피해 {taken:4.1f}/s")
            print(f"  난이도{d}: " + " | ".join(cells))

    # 전투 수치 역산(제안 근거): 진행 단계별 장비로 보스를 TARGET_TTK초에 잡고 한 방에 체력의 HIT_PCT%를 맞게 하려면
    # 보스 체력과 공격이 얼마여야 하는지. 지금 적 수치(체력 40~120)가 이 값보다 훨씬 작아 방이 몇 초 만에 끝난다.
    TARGET_TTK, HIT_PCT = 25, 13
    print(f"\n== 전투 수치 역산: 보스를 이론상 {TARGET_TTK}초에 잡고, 한 방에 체력의 {HIT_PCT}%를 맞게 하려면 (보스 방어 5) ==")
    stages = {1: ("rusty_sword", 0, [("leather_armor", 0)]), 2: ("hand_axe", 3, [("leather_armor", 2), ("miner_helmet", 2)]),
              3: ("iron_spear", 4, [("iron_plate", 4), ("miner_helmet", 4)]), 4: ("rune_blade", 4, [("rune_mail", 4), ("iron_plate", 4)])}
    first = None
    for d, (weapon, wl, armors) in stages.items():
        p = profiles.get(weapon, {"cooldown": 0.4})
        atk = BASE_ATK + float(eq[weapon]["base_value"]) + wl
        armor = BASE_DEF + sum(float(eq[a]["base_value"]) + l for a, l in armors)
        dps = dmg(atk, 5) / p["cooldown"]
        need_hp = dps * TARGET_TTK
        need_atk = attack_for_hit(HIT_PCT, armor)
        first = first or (need_hp, need_atk)
        print(f"난이도{d} ({items[weapon]['name']}+{wl}, 공격 {atk:.0f}, 방어 {armor:.0f}): 초당 피해 {dps:4.0f} -> 보스 체력 약 {need_hp:5.0f} (난이도1의 {need_hp / first[0]:.1f}배), 보스 공격 약 {need_atk:3.0f} (난이도1의 {need_atk / first[1]:.1f}배)")
    print("지금 값: 보스 체력 90~120, 공격 13~16, 난이도 체력 배율 1/1.4/1.8/2.4, 공격 배율 1/1.2/1.4/1.7 -> 체력을 몇 배 올리고 공격을 올려야 함(플레이 확인 뒤 적용, 규칙서 6.7)")

    print("\n== 제작 재료 가치와 획득 (제작 재료 판매가 합) ==")
    for item_id, e in eq.items():
        r = recipes.get(item_id)
        if not r:
            continue
        cost = sum(price[r[f"material_{i}"]] * int(r[f"amount_{i}"]) for i in (1, 2) if r.get(f"material_{i}"))
        u = unlocks.get(r["recipe_id"], {})
        if not u:
            print(f"[오류] 두루마리 해금이 없는 장비 레시피: {item_id}")
            problems += 1
        print(f"{items[item_id]['name']:9} 재료 {cost:4}원 / 두루마리 난이도 {u.get('difficulty', '?')} {u.get('regions', '')}")
    print("\n== 피해 계산식 표: 피해 = 공격² ÷ (공격 + 방어) — 세로 공격력, 가로 방어력, 칸 = 최종 피해 (괄호 = 방어로 줄어든 비율) ==")
    defenses = (0, 3, 6, 10, 15, 20, 30, 40, 50)
    print("공격\\방어 " + "".join(f"{d:>10}" for d in defenses))
    for a in (10, 12, 17, 22, 27, 34, 45):
        print(f"{a:>8}   " + "".join(f"{dmg(a, d):>4}({100 * d / (a + d):>2.0f}%)" for d in defenses))

    print(f"\n문제 {problems}개")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
