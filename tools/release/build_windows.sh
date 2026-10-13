#!/usr/bin/env bash
# Linux/클라우드에서 Windows 전달 ZIP 만들기(build_windows.ps1 과 같은 순서). 사용:
#   tools/release/build_windows.sh <godot 리눅스 실행 파일> <새 출력 폴더> [빌드 이름]
# 전제: 같은 버전의 Windows 내보내기 템플릿이 ~/.local/share/godot/export_templates/<버전>/ 에 있다.
# 커밋된 소스(git HEAD)만 새 폴더로 풀어 가져오기 2회 → release 내보내기 → 엔진 라이선스 → ZIP.
set -euo pipefail
GODOT="$(readlink -f "${1:?Godot 실행 파일 경로}")"
OUT="$(realpath -m "${2:?새 출력 폴더}")"
LABEL="${3:-playtest}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[ -e "$OUT/Project222.exe" ] && { echo "이미 있는 빌드는 덮어쓰지 않습니다: $OUT"; exit 1; }
if [ -n "$(git -C "$ROOT" diff --name-only HEAD)" ]; then echo "커밋하지 않은 소스 변경이 있습니다."; exit 1; fi
LOGS="${OUT}-build-logs"; STAGE="$LOGS/source"
rm -rf "$STAGE"; mkdir -p "$OUT" "$STAGE"
REV="$(git -C "$ROOT" rev-parse HEAD)"
git -C "$ROOT" archive --format=tar HEAD project.godot export_presets.cfg art data script scenes addons | tar -x -C "$STAGE"
# 빌드 전용 복사본에서만 에디터 연결 서버를 끈다.
sed -i 's|"res://addons/revvy/plugin.cfg", ||' "$STAGE/project.godot"
VERSION="$("$GODOT" --version | tr -d '\r\n')"
check_log() { if grep -qE "SCRIPT ERROR|^ERROR:" "$1"; then echo "오류가 있습니다: $1"; grep -E "SCRIPT ERROR|^ERROR:" "$1" | sort | uniq -c | head; exit 1; fi; }
cd "$STAGE"
timeout 300 "$GODOT" --headless --path . --editor --import --quit > "$LOGS/import1.log" 2>&1 || true   # 첫 회는 캐시 생성용
timeout 300 "$GODOT" --headless --path . --editor --import --quit > "$LOGS/import2.log" 2>&1; check_log "$LOGS/import2.log"
timeout 300 "$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/Project222.exe" > "$LOGS/export.log" 2>&1; check_log "$LOGS/export.log"
timeout 120 "$GODOT" --headless --path . --script "$ROOT/tools/release/write_engine_licenses.gd" -- "--out=$OUT/GODOT_LICENSES.txt" > "$LOGS/licenses.log" 2>&1; check_log "$LOGS/licenses.log"
cp "$ROOT/docs/배포/플레이테스트_안내.txt" "$OUT/README_KO.txt"
python3 - "$OUT" "$LABEL" "$REV" "$VERSION" <<'PY'
import hashlib, json, os, sys, zipfile, datetime
out, label, rev, version = sys.argv[1:5]
files = []
for name in ["Project222.exe", "Project222.pck", "README_KO.txt", "GODOT_LICENSES.txt"]:
    path = os.path.join(out, name)
    data = open(path, "rb").read()
    files.append({"name": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
manifest = {"label": label, "source_commit": rev, "tracked_source_dirty": False, "godot": version, "architecture": "x86_64",
            "built_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "files": files}
open(os.path.join(out, "BUILD_INFO.json"), "w", encoding="utf-8").write(json.dumps(manifest, indent=2, ensure_ascii=False))
open(os.path.join(out, "SHA256SUMS.txt"), "w", encoding="utf-8").write("".join(f"{f['sha256']}  {f['name']}\n" for f in files))
archive = out + ".zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    for name in ["Project222.exe", "Project222.pck", "README_KO.txt", "GODOT_LICENSES.txt", "BUILD_INFO.json", "SHA256SUMS.txt"]:
        z.write(os.path.join(out, name), name)
print("Windows playtest ZIP:", archive, os.path.getsize(archive), "bytes")
PY
