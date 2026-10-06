"""막별 '고쳐 쓰기' 요청문을 만든다(Opus·Gemini 등 어느 모델에 넣어도 됨).

실행: python tools/export_rewrite_prompts.py  → docs/스토리/고쳐쓰기_요청/*.md
각 파일은 공통 지침 + 화자 표 + 그 막의 글 현재 문장(화자·장면 포함)이 들어 있어 단독으로 쓸 수 있다.
"""
import csv, glob, re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_story_full as F

root = F.root
OUT = root / "docs/스토리/고쳐쓰기_요청"

PARTS = [
    ("1_프롤로그_튜토리얼_1막", "프롤로그·튜토리얼·1막", [0, 1, 2, 3, 4]),
    ("2_2막_제작과_개인부탁", "2막: 제작·교류·개인 부탁", [5, 6]),
    ("3_매장_행사", "매장 행사(공용·계절 행사 95행)", [7]),
    ("4_3막_마을", "3막: 길손·마을 이야기·장터·쉼터·안부·사계절 확장", [8, 9, 10, 11, 12, 13]),
    ("5_3막_곁가지", "3막 곁가지: 단골·날씨·계절 생활·기억", [14]),
    ("6_4막", "4막: 길 위의 가게·유적의 단서", [15, 16, 17]),
]

COMMON = """# 고쳐 쓰기 요청 — {title}

## 너의 역할
편의점 경영 + 판타지 원정 게임의 글 교정·집필자다. 아래 [글 목록]의 각 항목을 읽고 **규칙에 어긋나거나 어색한 곳만 고쳐 다시 쓴다.** 괜찮은 항목은 현재 문장을 **그대로** 출력한다. 글만 바꾸고 사건·조건·보상은 건드리지 않는다.

## 세계와 분위기
- 이세계 숲 한가운데 떨어진 현대 24시 편의점. 위협·악역은 없고 던전·몬스터는 재료를 구하러 가는 원정의 배경일 뿐이다. 스타듀밸리 같은 잔잔한 생활극이다.
- **편의점이 이세계에 온 이유는 끝까지 밝히지 않는다.** 신·마법사·소환·저주 같은 원인 설정을 넣지 않는다. 단서는 "닮아 보인다" 정도의 질문으로만 남긴다.
- 현지인은 편의점을 "먼 곳에서 온 낯선 가게"로 안다. 게임 용어(퀘스트·의뢰·보상·레벨·경험치·미션·임무·스탯·수락·클리어)와 현대 용어(편의점·플레이어·UI)는 대사에 쓰지 않는다.

## 말투 규칙 (가장 중요)
| 인물 | 말투 |
|---|---|
| 세이나(치료사) | **존댓말**(~어요/~세요). 한 문장 안에서 반말을 섞지 않는다 |
| 순회 기술자(역할 방문자) | **신중한 존댓말**(~습니다/~지요/~군요). 플레이어를 호칭 없이 가리킨다 |
| 심야 상인(역할 방문자) | **하게체**(~하게, ~구먼, ~일세, ~다네) |
| 타블렌(행상인) | 입담 좋은 친근한 반말. 농담·비유. 존댓말 금지 |
| 코르빈(채굴꾼) | 짧고 진지한 반말. 말끝을 흐린다. 존댓말 금지 |
| 이세르(여행자) | 사색적인 긴 문장의 반말. 존댓말 금지 |
| 오렐(이웃) | 느긋하고 살가운 반말. 안부 먼저 |
| 피니아·라슈·엘미·델빈 | 친근한 반말(피니아는 밝게, 라슈는 짧게, 엘미는 자연의 말로 가끔, 델빈은 또렷하게) |
| 바르크(광부) | 퉁명스러운 반말. 명령형(~해라) 대신 "~해 줘/~해 둬" |
| 완료 문구(`completion`) | 기록 문장은 **"~했다/~다"체**로 통일한다("~습니다" 금지). 뒤에 플레이어 안내 문장("~하세요")이 붙은 것은 안내 문장만 그대로 둔다 |
| 그 밖의 손님·방문자(상단·길손·배경 손님·이름 없는 이웃) | 친근한 반말 |
| 장면 서술문 | "~다"체(예: "바람이 지나가자 흙 냄새가 가까워진다.") |

## 형식 규칙
- 열: `id, kind, title, summary, lines, completion`. **탭 문자로 구분**하고 칸 안에 탭·줄바꿈을 쓰지 않는다. 쉼표는 써도 되고 따옴표로 감싸지 않는다. 비우는 칸은 탭 사이를 비운다(칸 수 항상 6개).
- 길이: title 20자, summary 60자 이내, lines와 completion은 한 칸 45자 이내, lines는 `|`로 나누고 6칸 이하.
- 준 항목마다 정확히 한 행. **id와 kind는 그대로.** 새 id를 만들거나 빼지 않는다. 채워 있는 열만 채우고 비어 있던 열은 비워 둔다.
- `{{item}}` 같은 자리표시자가 있으면 그대로 유지한다. 대사에 수량·돈·평판 같은 숫자를 쓰지 않는다.
- 화자 이름은 화면에서 붙으므로 대사에 쓰지 않는다. 단, 원문에 `이세르:` 처럼 화자 표시가 있으면 그대로 둔다.
- 같은 어구(예: "것 같아", "수 있겠어", "섣불리", "남겨 둔", "준비를 마쳤다")를 **서로 다른 3개 이상 항목에서 반복하지 않는다.**
- 새 설정·새 이름·새 장소·새 보상·새 사건을 만들지 않는다. 현재 문장의 사실(누가 무엇을 하는지, 순서, 조건)은 그대로 두고 말투와 표현만 고친다.

## 출력 형식
**코드블록 하나** 안에 탭으로 구분한 행만 넣는다. 항목 수와 같은 행 수여야 하고, 머리말·설명·표는 쓰지 않는다. 코드블록 밖에 "바꾼 항목과 이유" 목록(id: 한 줄)을 따로 적는다.

## [글 목록] ({n}행)
"""

def build_scene():
    tres = "\n".join(open(f, encoding="utf-8").read() for f in sorted(glob.glob(str(root / "scenes/shop/requests/*.tres"))))
    scene = {}
    for m in re.finditer(r'"id":"([^"]+)","npc":"([^"]*)"(?:[^{}]*?"stage":"([^"]*)")?', tres):
        scene.setdefault(m.group(1), (m.group(2), m.group(3) or ""))
    return scene

def main():
    rows = list(csv.DictReader(open(root / "data/shop/requests/requests_text.csv", encoding="utf-8", newline="")))
    scene = build_scene()
    buckets = [[] for _ in F.GROUPS] + [[]]
    for r in rows:
        for gi, g in enumerate(F.GROUPS):
            if F.match(g, r):
                buckets[gi].append(r); break
        else:
            buckets[-1].append(r)
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.md"): old.unlink()
    index = ["# 고쳐 쓰기 요청 (막별)\n", "모델에 한 파일씩 통째로 붙여 넣는다. 파일 하나가 한 번의 요청이다. 답(탭 구분 코드블록)은 `webimport` 또는 직접 대조해서 반영한다. 다시 만들기: `python tools/export_rewrite_prompts.py`\n"]
    for name, title, idxs in PARTS:
        items = [r for i in idxs for r in buckets[i]]
        if name.startswith("6_"): items += buckets[-1]
        lines = [COMMON.format(title=title, n=len(items))]
        for r in items:
            who, stage = scene.get(r["id"], ("", ""))
            meta = f"종류 {r['kind']}" + (f" / 화자 {who}" if who else "") + (f" / 장면 {stage[:90]}" if stage else "")
            lines.append(f"id={r['id']} | {meta}")
            lines.append("현재: " + "\t".join([r["id"], r["kind"], r["title"], r["summary"], r["lines"], r["completion"]]))
            lines.append("")
        p = OUT / f"{name}.md"
        p.write_text("\n".join(lines), encoding="utf-8")
        index.append(f"- [{title}]({name}.md) — {len(items)}행 ({p.stat().st_size // 1024} KB)")
        print(name, len(items), p.stat().st_size // 1024, "KB")
    (OUT / "README.md").write_text("\n".join(index) + "\n", encoding="utf-8")

main()
