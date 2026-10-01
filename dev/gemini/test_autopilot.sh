#!/bin/bash
# 자동 순환 종단 시험(네트워크·키 없음): 임시 원격 저장소와 가짜 제미나이로 한 바퀴를 끝까지 돌린다.
# 사용: GODOT=/path/to/godot bash dev/gemini/test_autopilot.sh   (프로젝트 폴더에서, feature/story-script 가 커밋된 상태)
set -e
GODOT="${GODOT:-godot}"
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
git clone -q --bare "$ROOT" "$TMP/origin.git"
git clone -q -b feature/story-script "$TMP/origin.git" "$TMP/work"
cd "$TMP/work"
git config user.email test@example.com && git config user.name tester
# ChatGPT 시뮬레이션: 다른 브랜치에 새 부탁(기계 부분만)을 추가한다.
git switch -q -c gpt-sim
python3 - <<'PY'
p = 'scenes/shop/requests/default_resident_requests.tres'
t = open(p, encoding='utf-8').read()
new = '{"id":"smith_charcoal", "npc":"마을 대장장이", "title":"임시", "item":"iron_ore", "amount":4, "reputation":1, "money":45, "lines":["임시"], "completion":["임시"]},\n'
i = t.index('{"id":"neighbor_bread"')
open(p, 'w', encoding='utf-8').write(t[:i] + new + t[i:])
PY
git add -A && git commit -q -m "gpt: 새 부탁 추가" && git push -q origin gpt-sim && git switch -q feature/story-script
"$GODOT" --headless --path . --import >/dev/null 2>&1; "$GODOT" --headless --path . --import >/dev/null 2>&1
STORY_FAKE_GEMINI=1 "$GODOT" --headless --path . res://dev/gemini/request_text.tscn -- --mode autopilot --once --auto-accept --source-branch gpt-sim | grep "자동 순환\|검사 대상\|오류"
git --git-dir="$TMP/origin.git" show feature/story-script:data/shop/requests/requests_text.csv | grep -q smith_charcoal && echo "PASS: 새 부탁의 글이 원격에 올라갔다"
STORY_FAKE_GEMINI=1 "$GODOT" --headless --path . res://dev/gemini/request_text.tscn -- --mode autopilot --once --source-branch gpt-sim | grep -q "할 일이 없습니다" && echo "PASS: 두 번째 순환은 할 일이 없다"
rm -rf "$TMP"
