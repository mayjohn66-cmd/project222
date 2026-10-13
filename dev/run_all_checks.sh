#!/usr/bin/env bash
# 모든 dev/scenes/check_*.tscn 를 차례로 돌려 통과/실패를 한 줄씩 보여 준다.
# 사용: GODOT_EXE=/경로/Godot dev/run_all_checks.sh   (프로젝트 루트에서)
# 일부 검사는 사용자 저장 보호를 위해 사용자 데이터 경로에 "foodbag_checks" 가 들어 있어야 한다.
#   리눅스: XDG_DATA_HOME=/tmp/foodbag_checks GODOT_EXE=... dev/run_all_checks.sh
#   Windows: 프로젝트 사본의 config/name 을 foodbag_checks 로 바꿔 실행(또는 해당 검사만 건너뜀).
# 통과 기준: "failures=0" · "실패 0" · "stuck": 0 (check_direct_expedition_run) 이 나오고 ERROR·FAIL 줄이 없을 것.
G="${GODOT_EXE:-godot}"
fail=0
for f in dev/scenes/check_*.tscn; do
  n=$(basename "$f" .tscn)
  out=$(timeout 300 "$G" --headless --path . "res://$f" 2>&1)
  if echo "$out" | grep -qE "^ERROR: |^FAIL|failures=[1-9]|실패 [1-9]"; then s="FAIL"; fail=$((fail+1))
  elif echo "$out" | grep -qE "failures=0|실패 0|\"stuck\": 0"; then s="ok"
  else s="결과 줄 없음(확인 필요)"; fi
  echo "$s  $n"
done
echo "실패 $fail개"
