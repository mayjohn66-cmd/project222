#!/usr/bin/env python3
"""콘텐츠 완료 조건 점검표(읽기 전용). 사용: python tools/story/audit_completion.py [출력경로]
  기본 출력: docs/콘텐츠/콘텐츠_완료조건_점검표.md

각 이야기·부탁이 "무엇을 하면 완료되는가"를 구조 파일(scenes/shop/requests/default_*.tres)에서 읽어 분류한다.
  A 실제 행동 : 손님에게 실판매 · 장소 방문/관찰 · 채집·제작 단계 · 튜토리얼 조작
  B 전달만   : 재료나 제작품을 창고에 준비해 두고 전달 버튼. 구하거나 만드는 과정은 다른 시스템(원정·제작)이 맡는다
  C 대화만   : 듣기·읽기·선택으로 끝(요구 물품·판매·장소 없음)
분류는 구조 파일의 값에서 기계적으로 읽은 것이다. 게임을 직접 실행해 확인한 것이 아니다.
"""
import csv, json, re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = root / (sys.argv[1] if len(sys.argv) > 1 else "docs/콘텐츠/콘텐츠_완료조건_점검표.md")

# --- 아이템 이름·종류 ---
items = {}
with open(root / "data/core/items.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        if r.get("id"): items[r["id"]] = r
def iname(i): return items.get(i, {}).get("name", i)
def is_product(i): return items.get(i, {}).get("item_type") == "store_product"

# --- 제목(글 파일) ---
titles = {}
with open(root / "data/shop/requests/requests_text.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        if r.get("title"): titles[r["id"]] = r["title"]

RES = {"naru": "타블렌", "doyun": "코르빈", "sora": "이세르", "caravan": "먼 곳의 상단"}
def who(x):
    return RES.get(x, x or "")

# --- 구조 파일 읽기 ---
def array_after(text, name):
    m = re.search(r"^%s = Array\[Dictionary\]\(\[" % re.escape(name), text, re.M)
    if not m: return None
    i = m.end() - 1  # '[' 위치
    depth = 0; instr = False; esc = False
    for j in range(i, len(text)):
        c = text[j]
        if instr:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': instr = False
            continue
        if c == '"': instr = True
        elif c == "[": depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                try: return json.loads(text[i:j + 1])
                except Exception: return None
    return None

FILES = [  # (파일, 배열 이름, 묶음 제목)
    ("resident_requests", "requests", "1막 주민 부탁"),
    ("community_requests", "requests", "마을 부탁 게시판"),
    ("personal_requests", "requests", "2막 개인 부탁"),
    ("crafting_path", "stages", "제작·교류(배우기)"),
    ("preservation_lessons", "events", "계절 보존 수업"),
    ("workshop_requests", "requests", "제작 뒤 부탁"),
    ("store_event_followups", "requests", "매장 행사 뒤 부탁"),
    ("market_afterglow", "requests", "장터 뒤 후일담 부탁"),
    ("trail_errands", "requests", "쉼터 뒤 생활 부탁"),
    ("season_stockpile", "requests", "보관한 재료 부탁"),
    ("seasonal_life_requests", "events", "사계절 생활 부탁"),
    ("seasonal_village", "events", "사계절 마을 사건"),
    ("regular_customers", "events", "단골 재방문"),
    ("weather_life", "events", "날씨 인사"),
    ("resident_memories", "events", "주민과 남기는 기억"),
    ("village_expansion", "events", "마을 확장(사계절·기념일·챕터)"),
    ("act_four", "events", "4막"),
]

def classify(e):
    """(분류, 하는 일 한 줄, 태그)"""
    tags = []
    reqs = list(e.get("requirements") or [])
    for s in e.get("steps") or []:
        reqs += s.get("requirements") or []
    if e.get("item"):  # 주민 부탁
        reqs.append({"item": e["item"], "amount": e.get("amount", 1)})
    sales = []
    for s in e.get("steps") or []:
        sales += s.get("sales") or []
    modes = {s.get("mode") for s in e.get("steps") or []}
    if e.get("mode"): modes.add(e["mode"])
    show = any(s.get("show") for s in e.get("steps") or [])
    do = []; act = False
    if any(s.get("map_purchase") for s in e.get("steps") or []):
        act = True; do.append("밤 상인에게 지도 구매")
    if any(s.get("ruins_run") for s in e.get("steps") or []):
        act = True; do.append("유적 원정 1회")
    if e.get("paths") or e.get("raw"):
        act = True; do.append("보존(냉장·냉동·말리기) 조작 후 전달")
    if sales or e.get("purchase_item") or e.get("sale_item") or e.get("after_store_event"):
        act = True; do.append("손님에게 실판매")
    if e.get("site") or "observe" in modes:
        act = True; do.append("장소 방문·관찰")
    if modes & {"gather"}:
        act = True; do.append("채집 지점 방문")
    if modes & {"produce"}:
        act = True; do.append("제작 단계")
    prod = [r for r in reqs if is_product(r.get("item", ""))]
    if prod or e.get("after_craft") or e.get("recipe"):
        tags.append("제작 필요")
    if reqs:
        names = "·".join("%s×%s" % (iname(r.get("item", "")), r.get("amount", 1)) for r in reqs[:3])
        do.append("전달: " + names)
    if show:
        tags.append("보여 주기")
        if not act: do.append("원정에서 얻은 물건을 보여 주기(소비 없음)")
    if e.get("choices"): tags.append("선택")
    if e.get("wait_days") or e.get("days_after") or any(s.get("wait_days") for s in e.get("steps") or []): tags.append("다음 날 이후")
    if act: cls = "A 실제 행동"
    elif reqs or show: cls = "B 전달만"
    else: cls = "C 대화만"
    if not do: do.append("대화 듣기" + (" · 선택" if e.get("choices") else ""))
    return cls, " + ".join(do), tags

rows = []   # (묶음, id, 제목, 주는 사람, 분류, 하는 일, 태그)
for fname, arr, group in FILES:
    text = (root / f"scenes/shop/requests/default_{fname}.tres").read_text(encoding="utf-8")
    entries = array_after(text, arr)
    if entries is None:
        print("읽지 못함:", fname); continue
    for e in entries:
        eid = e.get("id") or e.get("type") or "?"
        title = titles.get(e.get("title_id", ""), "") or titles.get(eid, "") or titles.get(eid + "_intro", "") or e.get("title", "")
        giver = who(e.get("resident") or e.get("giver") or e.get("npc") or "")
        if not giver and e.get("steps"): giver = who(e["steps"][0].get("resident", ""))
        cls, do, tags = classify(e)
        rows.append((group, eid, title, giver, cls, do, tags))

# --- 튜토리얼(구조 파일 단계) ---
tut_text = (root / "scenes/shop/tutorial/default_tutorial.tres").read_text(encoding="utf-8")
GOAL = {"cleanup": ("A 실제 행동", "바닥 잔해를 직접 치우기"), "fixtures": ("A 실제 행동", "계산대·진열대를 메뉴에서 건축"),
        "stock": ("A 실제 행동", "식품을 진열대에 직접 넣기"), "checkout": ("A 실제 행동", "문을 열고 첫 손님에게 직접 계산"),
        "barter": ("A 실제 행동", "교환창에서 식품을 장비와 교환"), "shop_days": ("A 실제 행동", "가게를 열어 재고를 모두 판매"),
        "stock_depleted": ("A 실제 행동", "가게를 열어 재고를 모두 판매"), "expedition": ("A 실제 행동", "장비를 차고 원정에서 재료를 얻어 귀환"),
        "raw_sale": ("A 실제 행동", "원재료를 진열해 손님에게 실판매"), "food_care": ("A 실제 행동", "상품 조회에서 날짜·마감 정리 확인"),
        "production": ("A 실제 행동", "화덕으로 현지식 빵 제작·수령")}
for m in re.finditer(r'\{"id":"([a-z_]+)"[^{}]*?"goal":"([a-z_]+)"', tut_text):
    sid, goal = m.group(1), m.group(2)
    cls, do = GOAL.get(goal, ("A 실제 행동", goal))
    rows.append(("프롤로그·튜토리얼", sid, titles.get("tutorial_step:" + sid, "") or titles.get(sid, ""), "", cls, do, []))

# --- 낚시(설계 파일의 action 문장) ---
fj = json.load(open(root / "data/fishing/fishing_content.json", encoding="utf-8"))
for key, label in (("progression", "낚시 진행"), ("events", "낚시 사건")):
    for e in fj[key]:
        act = e.get("action", "")
        cls = "A 실제 행동" if any(w in act for w in ("획득", "실제", "조작", "소비", "판매", "관찰")) else "C 대화만"
        if key == "events" and "대화" in act and not any(w in act for w in ("조작", "획득", "판매")): cls = "C 대화만" if "관찰" not in act else "A 실제 행동"
        if "보여 준" in act: cls = "B 전달만"
        rows.append((label, e["id"], e.get("title", ""), who(e.get("npc_id", "")), cls, act, []))
for e in fj["requests"]:
    rows.append(("낚시 부탁", e["id"], e.get("title", ""), who(e.get("npc_id", "")), "B 전달만", "생선 요리를 만들어 전달", ["제작 필요"]))

# --- 매장 행사 ---
with open(root / "data/shop/events/store_events.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        rows.append(("매장 행사", r["event_id"], r["title"], "", "A 실제 행동", "소문을 듣고 상품을 진열·재고 준비 → 기간 중 실판매", ["기간 한정"]))

# --- 손으로 분류한 서비스 ---
rows += [
    ("서비스", "대장간", "장비 제작·강화", "코르빈", "A 실제 행동", "배운 장비를 재료로 제작·강화", []),
    ("서비스", "직원 고용·교육", "직원 3명", "", "A 실제 행동", "고용·교육을 실제로 성공시켜야 후일담", []),
    ("서비스", "전원 복구", "꺼진 계산대에 불을", "기술자", "B 전달만", "재료·개조비를 건네고 다음 날 연결", ["다음 날 이후"]),
    ("서비스", "비밀 상인", "심야 상인", "", "A 실제 행동", "밤에 보물 지도를 구매", []),
    ("마을 이야기", "village_story", "이세르의 마을 이야기", "이세르", "C 대화만", "이웃 두 명을 만나 말을 듣고 기억 하나 선택", ["선택"]),
    ("마을 이야기", "village_goodwill", "가게 앞에 남기는 안부", "이세르", "C 대화만", "이웃 세 명을 차례로 만나 말을 듣기", []),
    ("마을 이야기", "village_gathering", "우물 곁 저녁 모임", "", "A 실제 행동", "빵·물을 준비해 저녁에 우물 벤치로 가기", []),
    ("마을 이야기", "village_rest", "길목 쉼터 첫 모임", "", "A 실제 행동", "벤치를 마련하고 다음 오후에 쉼터로 가서 앉기", []),
    ("마을 이야기", "village_market", "작은 노점의 첫 장터", "타블렌", "B 전달만", "빵·열매를 준비해 맡기고 다음 낮 장터로 가기", ["다음 날 이후"]),
    ("마을 이야기", "lantern_wayfarer", "등불 아래의 길손", "길손", "B 전달만", "저녁에 물이나 빵을 건네고 다음 날 재방문", ["선택", "다음 날 이후"]),
]

# --- 출력 ---
order = ["A 실제 행동", "B 전달만", "C 대화만"]
cnt = {c: sum(1 for r in rows if r[4] == c) for c in order}
total = len(rows)
L = []
w = L.append
w("# 콘텐츠 완료 조건 점검표 (2026-10-13)")
w("")
w("> 자동 생성: `python tools/story/audit_completion.py` · 구조 파일(`scenes/shop/requests/*.tres`·튜토리얼·낚시 JSON·매장 행사 CSV)에서 읽은 값으로 분류했다. **게임을 직접 실행해 확인한 것이 아니다.** 분류 기준이 맞는지 의심되는 줄은 아래 표의 \"하는 일\"을 읽고 고쳐 달라고 하면 된다.")
w("")
w("## 분류 기준")
w("")
w("| 분류 | 뜻 | 게임다움 |")
w("|---|---|---|")
w("| **A 실제 행동** | 손님에게 실판매, 장소 방문·관찰, 채집·제작 단계처럼 **완료하려면 게임 안에서 직접 해야 하는 일**이 있다 | 있음 |")
w("| **B 전달만** | 재료나 제작품(`제작 필요` 표시)을 창고에 준비해 두고 **전달 버튼**을 누른다. 구하거나 만드는 과정은 원정·제작에 있고, 이 콘텐츠 자체의 완료는 인벤토리 확인이다 | 약함 |")
w("| **C 대화만** | 대화를 읽거나 선택하면 끝. 요구 물품·판매·장소가 없다 | 없음 |")
w("")
w("## 1. 한눈에")
w("")
w("| 분류 | 개수 | 비율 |")
w("|---|---|---|")
for c in order: w(f"| {c} | {cnt[c]} | {cnt[c]*100//total}% |")
w(f"| 합계 | {total} | |")
w("")
groups = []
for r in rows:
    if r[0] not in groups: groups.append(r[0])
w("### 묶음별")
w("")
w("| 묶음 | A 실제 행동 | B 전달만 | C 대화만 | 합계 |")
w("|---|---|---|---|---|")
for g in groups:
    sub = [r for r in rows if r[0] == g]
    n = {c: sum(1 for r in sub if r[4] == c) for c in order}
    w(f"| {g} | {n[order[0]]} | {n[order[1]]} | {n[order[2]]} | {len(sub)} |")
w("")
w("## 2. 가장 먼저 손볼 후보 (B 전달만·C 대화만)")
w("")
w("`B`와 `C`는 \"설명을 읽고 버튼을 누르면 끝\"에 가까운 것들이다. 아래 3장의 표에서 모아 보았다.")
w("")
bc = [r for r in rows if r[4] != "A 실제 행동"]
w(f"- 대상 {len(bc)}개 (전체의 {len(bc)*100//total}%). 이 중 **'다음 날 이후' 대기만 붙은 것**은 기다리기만 하면 되니 긴장이 없다.")
w("")
w("## 3. 전체 표")
w("")
for g in groups:
    w(f"### {g}")
    w("")
    w("| id | 제목 | 주는 사람 | 분류 | 하는 일 | 특징 |")
    w("|---|---|---|---|---|---|")
    for r in rows:
        if r[0] != g: continue
        w("| `%s` | %s | %s | %s | %s | %s |" % (r[1], r[2].replace("|", "/"), r[3], r[4], r[5].replace("|", "/"), "·".join(r[6])))
    w("")
out.write_text("\n".join(L) + "\n", encoding="utf-8")
print("→", out, f"· 총 {total}개 · A {cnt[order[0]]} B {cnt[order[1]]} C {cnt[order[2]]}")
