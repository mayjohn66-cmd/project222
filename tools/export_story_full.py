"""게임에 들어간 모든 글을 이야기 순서(막 → 사건)로 묶어 읽기 좋은 문서 하나로 만든다.

실행: python tools/export_story_full.py   → docs/스토리/전체_스토리.md
- 묶는 기준은 id 접두어 규칙(아래 GROUPS)이다. 위에서부터 처음 맞는 묶음에 들어간다. 어디에도 안 맞으면 마지막 묶음.
- 말하는 사람은 scenes/shop/requests/*.tres 의 `"id":..,"npc":..` 에서 찾는다(없으면 종류만 표시).
- 사건 순서는 대략이다(정확한 선행 조건은 docs/콘텐츠/ 막별 문서와 .tres 의 "after"를 본다).
"""
import csv, glob, re, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent

GROUPS = [
    ("프롤로그 — 마지막 근무와 낯선 창", "prologue_", None),
    ("튜토리얼 — 계산대·원정·판매 핵심 안내", r"(checkout|raw_|barter|expedition|food_care|production|raw_sale|setup|stock|trade_|arrival_peddler|smithy_panel)", None),
    ("1막 — 첫 이웃과 부탁", None, {"resident_introduction", "resident_request", "resident_greeting"}),
    ("1막 — 주민 정착", r"(settle_|landmark_settle)", None),
    ("1막 사이드 — 꺼진 계산대에 불을 되찾다(순회 기술자)", "power_", None),
    ("2막 — 제작과 교류(빵·간식·음식과 차)", r"(craft_|contact_|trade_first|preserve_)", None),
    ("2막 — 개인 부탁(타블렌·코르빈·이세르)", None, {"personal_request"}),
    ("2막~3막 — 매장 행사(소문에서 진열대로)", "store_", None),
    ("3막 — 등불 아래의 길손", "lantern_wayfarer", None),
    ("3막 — 이세르의 마을 이야기", r"(village_story|sora_village_story)", None),
    ("3막 — 작은 노점의 첫 장터와 후일담", r"(first_market|market_afterglow|workshop_afterglow)", None),
    ("3막 — 길목의 쉼터와 우물 저녁", r"(trail_rest|trail_afterglow|well_evening|well_gathering|path_light|trail_rest_corner|flower_corner|welcome_garden|open_smithy)", None),
    ("3막 — 가게 앞에 남기는 안부", "goodwill", None),
    ("3막 — 이웃과 사계절 마을 확장", "expansion_", None),
    ("3막 곁가지 — 단골·날씨·계절 생활·기억", r"(regular_|weather_|spring_|summer_|autumn_|winter_|doyun_|naru_|sora_|first_|autumn|trail_|iron|grain|mushroom)", None),
    ("4막 A — 길 위의 가게", r"act4_a", None),
    ("4막 B — 유적의 단서", r"act4_b", None),
    ("4막 — 길목의 쉼터 안부", r"act4_rest", None),
]

def match(g, row):
    _, pat, kinds = g
    if kinds and row["kind"] in kinds:
        return True
    if pat is None:
        return False
    if any(c in pat for c in "()|\\"):
        return re.match(pat, row["id"]) is not None
    return row["id"].startswith(pat)

def build():
    rows = list(csv.DictReader(open(root / "data/shop/requests/requests_text.csv", encoding="utf-8", newline="")))
    tres = "\n".join(open(f, encoding="utf-8").read() for f in sorted(glob.glob(str(root / "scenes/shop/requests/*.tres"))))
    npc = {}
    for m in re.finditer(r'"id":"([^"]+)","npc":"([^"]*)"', tres):
        npc.setdefault(m.group(1), m.group(2))
    with open(root / "data/story/story_beats.csv", encoding="utf-8", newline="") as f:
        beats = list(csv.DictReader(f))

    buckets = [[] for _ in GROUPS] + [[]]
    for r in rows:
        for gi, g in enumerate(GROUPS):
            if match(g, r):
                buckets[gi].append(r); break
        else:
            buckets[-1].append(r)

    out = ["# 전체 스토리 (게임에 들어간 모든 글, 이야기 순서)\n",
           f"자동 생성: `python tools/export_story_full.py` · 총 {len(rows)}행 + 이웃 이야기 {len(beats)}개.\n",
           "묶음은 id 규칙으로 나눈 것이라 막 안의 사건 순서는 대략이다. `id`·말하는 사람·종류를 함께 적었다. 대사 줄은 `/`로 구분한다. '수첩/안내'는 게시판·기록에 나오는 설명 문장이다.\n"]
    for g, items in zip(GROUPS + [("그 밖(분류되지 않은 글)", None, None)], buckets):
        if not items:
            continue
        out.append(f"\n## {g[0]} ({len(items)}행)\n")
        for r in items:
            who = npc.get(r["id"], "")
            head = f"- `{r['id']}` [{r['kind']}{' · ' + who if who else ''}]"
            if r["title"]:
                head += f" **{r['title']}**"
            out.append(head)
            if r["summary"]:
                out.append(f"  - 수첩/안내: {r['summary']}")
            if r["lines"]:
                out.append(f"  - 대사: {r['lines'].replace('|', ' / ')}")
            if r["completion"]:
                out.append(f"  - 완료 문구: {r['completion']}")
    out.append(f"\n## 이웃 이야기(story_beats, {len(beats)}개) — 조건이 맞으면 이웃이 건네는 한마디\n")
    for b in beats:
        out.append(f"- `{b['beat_id']}` [{b['npc_id']}] 조건: {b['conditions'] or '-'} → {b['lines'].replace('|', ' / ')}")
    return "\n".join(out) + "\n", [(g[0], len(i)) for g, i in zip(GROUPS + [("그 밖", 0, 0)], buckets)]

if __name__ == "__main__":
    text, stat = build()
    out = root / (sys.argv[1] if len(sys.argv) > 1 else "docs/스토리/전체_스토리.md")
    out.write_text(text, encoding="utf-8")
    for n, c in stat:
        print(f"{c:4d}  {n}")
    print(f"→ {out.relative_to(root)} ({out.stat().st_size // 1024} KB)")
