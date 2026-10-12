"""스토리 전체를 파일 하나로 묶는다(제미나이 웹에 통째로 올려 분석시키는 용도).

실행: python tools/export_story_bundle.py [출력경로] [요청문파일]   → 기본 docs/스토리/분석용_묶음.md
  요청문파일(.md/.txt)을 주면 맨 위의 "분석 요청" 대신 그 글을 넣는다(예: 스토리보드 새로 쓰기 요청). 자료 부분은 항상 최신 데이터로 다시 만든다.
묶는 것: 요청 프롬프트 + 전체 정리 + 세계관 + 인물 설정 + 4막 흐름 + 모든 글(막·사건 순서)과 이웃 이야기(story_beats).
"""
import csv, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
out = root / (sys.argv[1] if len(sys.argv) > 1 else "docs/스토리/분석용_묶음.md")

PROMPT = """# 스토리 일관성 분석 요청

아래는 편의점+판타지 원정 게임의 스토리 자료 전부입니다(줄거리 정리, 세계관, 인물 설정, 4막 흐름, 게임에 들어간 모든 대사·글).
읽고 다음을 한국어로 답해 주세요. 근거는 반드시 `id`나 문장을 인용하세요.

1. **설정 충돌**: 줄거리·세계관·인물 설정과 어긋나는 대사(사실, 직업, 관계, 시간 순서).
2. **말투 불일치**: 같은 인물인데 말투(존댓말/반말, 어휘)가 다른 곳.
3. **확정되지 않은 설정을 단정한 곳**: 편의점이 이 세계에 온 이유 등 미정 사항을 밝혀 버린 문장.
4. **흐름 문제**: 사건 순서상 앞에 알 수 없는 것을 아는 듯 말하는 대사, 갑작스러운 감정, 빠진 연결.
5. **반복·어색한 표현**: 여러 곳에서 되풀이되는 어구, 번역투, 어색한 문장.
6. **전체 평가**: 스타듀밸리 정도의 잔잔한 성장 이야기로서 어울리는지, 가장 먼저 고칠 5곳.

고칠 문장을 제안할 때는 원문과 수정안을 나란히 적어 주세요. 추측으로 새 설정을 만들지 마세요.

---
"""

if len(sys.argv) > 2:
    PROMPT = Path(sys.argv[2]).read_text(encoding="utf-8").strip() + "\n\n---\n"

import re

def read(p):
    text = (root / p).read_text(encoding="utf-8").strip()
    # 묶음은 다른 폴더로 옮겨 올리는 파일이라 상대 링크는 의미가 없다: [글자](주소) → 글자
    return re.sub(r"\[([^\]]+)\]\((?!https?://)[^)]+\)", r"\1", text)

def rows(p):
    with open(root / p, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))

parts = [PROMPT]
for title, p in [("줄거리 전체 정리", "docs/스토리/전체_정리.md"), ("세계관", "docs/drafts/story/world_setting.md"),
                 ("인물 설정", "docs/drafts/story/character_profiles.md"), ("4막 B 흐름", "docs/스토리/4막_B_흐름_보기.md")]:
    parts.append(f"\n\n# [자료] {title}\n\n{read(p)}\n")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_story_full
full, _ = export_story_full.build()
parts.append("\n\n# [자료] 게임에 들어간 모든 글(이야기 순서)\n\n" + full.replace("# 전체 스토리", "## 전체 스토리", 1))

out.write_text("\n".join(parts) + "\n", encoding="utf-8")
print(f"→ {out} ({out.stat().st_size // 1024} KB)")
