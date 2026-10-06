"""스토리 글 전체 점검(읽기만 함). python tools/audit_story.py
검사: 화자별 말투(반말/존댓말), 전이 원인 단정어, 수치·게임 용어, 같은 줄 중복, 현지인이 쓰면 어색한 현대어, 미해결 자리표시자.
"""
import csv, glob, re, collections
from pathlib import Path
root = Path(__file__).resolve().parent.parent
rows = list(csv.DictReader(open(root/"data/shop/requests/requests_text.csv", encoding="utf-8", newline="")))
beats = list(csv.DictReader(open(root/"data/story/story_beats.csv", encoding="utf-8", newline="")))
tres = "\n".join(open(f, encoding="utf-8").read() for f in sorted(glob.glob(str(root/"scenes/shop/requests/*.tres"))))
npc = {}
for m in re.finditer(r'"id":"([^"]+)","npc":"([^"]*)"', tres): npc.setdefault(m.group(1), m.group(2))
for m in re.finditer(r'"title_id":"([^"]+)"[^}]*?"npc":"([^"]*)"', tres): npc.setdefault(m.group(1), m.group(2))

POLITE = re.compile(r"(요|습니다|니다|세요|십시오|시지요|지요)[.?!…]*$")
NAMES = ["타블렌","코르빈","이세르","오렐","피니아","라슈","엘미","바르크","델빈","세이나"]
FORMAL_OK = {"세이나", "순회 기술자", "기술자"}
cause = re.compile(r"(소환|차원|신이|마법사가|저주|운명이|선택받|이세계로 (왔|오게)|전이(된|했)|너를 불러)")
modern = re.compile(r"(편의점|플레이어|점장님|유저|UI|퀘스트|레벨)")
rep = collections.defaultdict(list)
issues = collections.defaultdict(list)

def speakers(r):
    """(화자 또는 None, 대사)"""
    out = []
    for l in r["lines"].split("|"):
        m = re.match(r"^(" + "|".join(NAMES) + r"):\s*(.*)$", l)
        out.append((m.group(1), m.group(2)) if m else (None, l))
    return out

for r in rows:
    who = npc.get(r["id"], "")
    for sp, line in speakers(r):
        rep[line].append(r["id"])
        who2 = sp or who
        polite = bool(POLITE.search(line.strip()))
        formal_ok = any(k in (who2 or "") for k in FORMAL_OK)
        if r["kind"] in ("service_text","personal_request","resident_request","resident_greeting","community_request","resident_introduction","trade_offer","tutorial_dialogue") and who2 and not formal_ok and polite and not r["id"].startswith(("store_",)):
            issues["말투: 반말 인물이 존댓말"].append(f"{r['id']} [{who2}] {line}")
        if formal_ok and not polite and who2 and "기술자" in who2 and "act4_b2" in r["id"] or ("기술자" in who2 and not polite and line.strip().endswith(("어.","야.","지.","네.","군.","해."))):
            issues["말투: 기술자가 반말"].append(f"{r['id']} {line}")
        if cause.search(line): issues["전이 원인 단정 의심"].append(f"{r['id']} {line}")
        if re.search(r"\d", line) and "{" not in line: issues["대사 안 숫자"].append(f"{r['id']} {line}")
        if modern.search(line): issues["현대/게임 용어"].append(f"{r['id']} {line}")
        if re.search(r"\{[^}]*\}", line) and not re.search(r"\{item\}", line): issues["알 수 없는 자리표시자"].append(f"{r['id']} {line}")
    for col in ("title","summary","completion"):
        if cause.search(r[col]): issues["전이 원인 단정 의심"].append(f"{r['id']}.{col} {r[col]}")
for b in beats:
    for l in b["lines"].split("|"):
        if POLITE.search(l.strip()): issues["말투: 이웃 이야기 존댓말"].append(f"{b['beat_id']} {l}")
        rep[l].append("beat:"+b["beat_id"])
for line, ids in rep.items():
    if len(ids) > 1 and len(line) > 12: issues["같은 줄 중복"].append(f"{', '.join(ids)} :: {line}")

tot = 0
for k, v in issues.items():
    print(f"\n## {k} ({len(v)})")
    for x in v[:40]: print(" -", x)
    if len(v) > 40: print(f" … 외 {len(v)-40}")
    tot += len(v)
print(f"\n총 {tot}건 / 글 {len(rows)}행·이웃 이야기 {len(beats)}개")
