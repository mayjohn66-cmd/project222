#!/usr/bin/env python3
"""3D 마을 그림 작업 도우미 — 터미널에서 번호를 골라 진행하는 메뉴(내 PC 터미널에서 실행).

  python tools/world3d_menu.py            메뉴
  python tools/world3d_menu.py status     진행 현황만 출력
  python tools/world3d_menu.py next       다음에 그릴 면 하나 안내(프롬프트 포함)

메뉴에서 하는 일
  1) 진행 현황      자산별로 실제 그림이 몇 장 들어왔는지
  2) 다음에 그릴 면  크기·반복 여부·영문 프롬프트를 보여 주고(클립보드 복사 선택), 저장할 위치 안내
  3) 그림 넣기      그림 폴더(또는 파일)를 알려 주면 검사하고 art/world3d/<자산id>/ 에 넣음
  4) 가져오기 설정·검증  .import 무손실 설정 맞추기 + validate_assets 검사
  5) 요청서·틀 다시 만들기  (Godot 필요: GODOT_EXE 환경변수) 그림 요청 문서와 면 질감 틀 PNG 재생성
  6) Pixel Lab 으로 만들기   자산 하나의 작업 지시 파일(지시 파일)을 만들고, PC 의 Claude Code(`claude`, Pixel Lab MCP 연결됨)를 그 지시와 함께 실행
참고: 이미지는 이 도구가 아니라 PC 의 Claude Code 가 Pixel Lab MCP 로 만든다(사용자 범위로 연결: `claude mcp add pixellab ... -s user`, 토큰은 저장소에 두지 않음).
      이 도구는 지시 파일을 만들고, 만들어진 PNG 를 검사해 art/world3d/ 에 넣는 일을 맡는다.
Pillow 가 필요하다(pip install pillow).
"""
import csv
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART_REQ = os.path.join(ROOT, "docs", "그림_작업")
FACES_CSV = os.path.join(ART_REQ, "faces.csv")
OUT_DIR = os.path.join(ROOT, "art", "world3d")
PY = sys.executable

# 요청 순서(그림 요청 문서 4장): 이끼 오두막 → 나머지 건물 → 개수 많은 소품
PRIORITY = ["moss_cottage", "red_house", "bakery", "tool_shop", "blacksmith", "ochre_townhouse", "stable", "granary",
            "apple_tree", "flower_bush", "street_lantern", "wood_fence", "low_wall", "village_well", "stall_bakery", "stall_fish",
            "stall_cloth", "stall_herb", "stall_market", "supply_cart", "plaza_crates", "noticeboard", "oak_bench", "road_sign"]


# 한 자산 안에서 먼저 그릴 면(눈에 가장 크게 보이는 순서). 나머지는 표 순서.
FACE_ORDER = ["wall_front", "wall_side", "roof_tiles", "gable_wall", "roof_trim", "chimney_stone", "plinth_stone", "awning",
              "tree_foliage", "bark", "stall_awning", "stall_counter", "stall_goods"]


def face_rank(face):
    return FACE_ORDER.index(face) if face in FACE_ORDER else len(FACE_ORDER)


def load_faces():
    if not os.path.exists(FACES_CSV):
        print("faces.csv 가 없습니다. 메뉴 5번(요청서 다시 만들기)을 먼저 실행하거나 저장소를 최신으로 받으세요.")
        return {}
    data = {}
    with open(FACES_CSV, encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            data.setdefault(row["asset"], []).append(row)
    for rows in data.values():
        rows.sort(key=lambda r: face_rank(r["face"]))
    return data


def has_art(asset, face):
    return os.path.exists(os.path.join(OUT_DIR, asset, face + ".png"))


def ordered_assets(faces):
    rest = [a for a in faces if a not in PRIORITY]
    return [a for a in PRIORITY if a in faces] + sorted(rest)


def show_status(faces):
    print("\n자산별 진행 (실제 그림이 들어온 면 / 전체 면)")
    print("-" * 64)
    done_total = all_total = 0
    for a in ordered_assets(faces):
        rows = faces[a]
        done = sum(1 for r in rows if has_art(a, r["face"]))
        done_total += done
        all_total += len(rows)
        bar = "#" * int(20 * done / len(rows)) + "." * (20 - int(20 * done / len(rows)))
        print("%-18s %-14s [%s] %2d/%2d" % (a, rows[0]["asset_label"], bar, done, len(rows)))
    print("-" * 64)
    print("합계 %d/%d 면 (그림이 없는 면은 임시 질감이 계속 쓰임)\n" % (done_total, all_total))


def next_face(faces, asset=None):
    for a in ([asset] if asset else ordered_assets(faces)):
        for r in faces.get(a, []):
            if not has_art(a, r["face"]):
                return a, r
    return None, None


def copy_clip(text):
    try:
        if sys.platform.startswith("win"):
            subprocess.run("clip", input=text.encode("utf-16"), check=True, shell=True)
        elif sys.platform == "darwin":
            subprocess.run("pbcopy", input=text.encode("utf-8"), check=True)
        else:
            return False
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def show_next(faces, asset=None):
    a, r = next_face(faces, asset)
    if r is None:
        print("\n더 그릴 면이 없습니다." if asset is None else "\n이 자산은 모든 면에 그림이 있습니다.")
        return
    print("\n다음에 그릴 면: %s (%s) — %s" % (a, r["asset_label"], r["face"]))
    print("  크기      : %s x %s px  (%s)" % (r["width"], r["height"], r["repeat"]))
    print("  법선 맵   : %s" % r["normal_map"].replace(a + "/", "") if r["normal_map"] != "선택" else "  법선 맵   : 선택")
    print("  틀 PNG    : docs/그림_작업/%s  (이 크기·배치 그대로 새로 그리기)" % r["file"])
    print("  시트      : docs/그림_작업/시트/%s.png  (한 장 요약)" % a)
    print("  저장 위치 : art/world3d/%s/%s.png   (도구 3번으로 넣으면 자동)" % (a, r["face"]))
    print("  설명      : %s" % r["note"])
    print("\n  영문 프롬프트:\n  %s\n" % r["prompt_en"])
    if input("프롬프트를 클립보드에 복사할까요? (y/N) ").strip().lower() == "y":
        print("  복사했습니다." if copy_clip(r["prompt_en"]) else "  이 환경에서는 복사할 수 없습니다. 위 글을 직접 복사하세요.")


def pick_asset(faces, prompt="자산 번호 또는 id"):
    names = ordered_assets(faces)
    for i, a in enumerate(names, 1):
        print("  %2d) %-18s %s" % (i, a, faces[a][0]["asset_label"]))
    s = input("%s: " % prompt).strip()
    if s.isdigit() and 1 <= int(s) <= len(names):
        return names[int(s) - 1]
    return s if s in faces else None


def clean_path(s):
    return s.strip().strip('"').strip("'")


def do_ingest(faces):
    a = pick_asset(faces, "넣을 자산 번호 또는 id (취소: 엔터)")
    if not a:
        return
    path = clean_path(input("그림 폴더 또는 파일 경로(탐색기에서 끌어다 놓아도 됨): "))
    if not path:
        return
    cmd = [PY, os.path.join(ROOT, "tools", "ingest_world3d.py"), a, path]
    first = subprocess.run(cmd + ["--dry-run"], cwd=ROOT)
    if first.returncode != 0:
        if input("\n거절된 파일이 있습니다. 요청서 크기에 최근접으로 맞춰서 다시 시도할까요? (y/N) ").strip().lower() != "y":
            return
        cmd.append("--resize")
    if input("\n위 결과대로 art/world3d/%s/ 에 넣을까요? (y/N) " % a).strip().lower() == "y":
        subprocess.run(cmd, cwd=ROOT)
        print("\n다음: Godot 를 한 번 열어 .import 를 만든 뒤 메뉴 4번(가져오기 설정·검증)을 실행하세요.")


def do_check():
    subprocess.run([PY, os.path.join(ROOT, "tools", "fix_texture_import.py")], cwd=ROOT)
    print("\n--- 검증(art/world3d 부분) ---")
    out = subprocess.run([PY, os.path.join(ROOT, "tools", "validate_assets.py"), ROOT], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    keep = [ln for ln in out.splitlines() if "world3d" in ln]
    print("\n".join(keep) if keep else "art/world3d 항목 없음(아직 그림이 없음)")


def do_regen():
    godot = os.environ.get("GODOT_EXE", "")
    if not godot or not os.path.exists(godot):
        print("GODOT_EXE 환경변수가 없거나 파일이 없습니다. 예) setx GODOT_EXE \"C:\\path\\Godot_v4.7.1-stable_win64_console.exe\" 후 새 터미널")
        return
    subprocess.run([godot, "--headless", "--path", ROOT, "--import"], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # 미리보기는 렌더링이 필요하므로 --headless 를 쓰지 않는다(창이 잠깐 뜸).
    subprocess.run([godot, "--path", ROOT, "res://dev/spike3d/art_request_export.tscn"], cwd=ROOT)
    subprocess.run([PY, os.path.join(ROOT, "tools", "build_art_request_doc.py")], cwd=ROOT)


TASK_HEADER = """# 작업 지시 — {label} ({asset}) 의 3D 마을용 면 질감을 Pixel Lab 으로 만들기

이 파일은 `python tools/world3d_menu.py` 가 만들었다(사용자 PC 의 Claude Code 용). 아래 순서대로 진행하고, **한 면씩 만들어 사용자에게 보여 준 뒤** 다음으로 넘어간다.

## 0. 먼저 확인
- 이 세션에서 `/mcp` 로 `pixellab` 이 연결(Connected)인지, 어떤 도구가 있는지 사용자에게 알려 준다. 연결이 없거나 필요한 도구가 없으면 **추측으로 진행하지 말고 중단하고 보고**한다.
- 이미지 생성은 크레딧이 든다. 한 번에 한 면만, 마음에 안 들면 사용자와 상의해서 다시 만든다.
- **토큰·API 키를 화면에 찍거나 파일에 적지 않는다.**

## 1. 규칙 (docs/그림_작업/요청서.md 1장 요약)
- 크기는 아래 표의 크기와 **정확히 같게**. 확대·축소로 맞추지 않는다. 정확한 크기를 못 내는 도구라면 가장 가까운 크기로 만든 뒤 `--resize`(최근접)로 맞추되 도트가 뭉개지지 않았는지 사용자에게 보여 준다.
- 외곽선·그림자·빛(밝고 어두움)·반투명 없이 **평평한 색**으로. 안쪽 선(줄눈·창틀·나무결)은 허용.
- 색은 한 장 8~12개(최대 16), 같은 자산의 면끼리 팔레트를 공유(벽·기단·창틀 색).
- "반복"인 면은 위아래·좌우가 이어져야 한다. 만든 뒤 `python tools/preview_tiles.py <파일>` 로 3x3 이은 그림을 만들어 이음매를 사용자에게 보여 준다.
- 틀 PNG(`docs/그림_작업/틀/{asset}__<면>.png`)와 한 장 요약 `docs/그림_작업/시트/{asset}.png` 는 창·문 위치 등 **배치 규격**이다. 가능하면 참조/초안 이미지로 쓰고, 같은 배치를 지킨다. 2D 원본 그림 `{sprite}` 은 분위기 참고용(그대로 베끼지 않는다).
- 문은 앞벽 가운데, 창 위치는 틀과 같게(3D 의 화분·계단 위치가 맞아야 함).

## 2. 저장 위치
- 만든 결과는 먼저 `docs/그림_작업/받은그림/{asset}/<면이름>.png` 에 둔다(Godot 가 가져오지 않는 폴더).
- 사용자가 확인하면 `python tools/ingest_world3d.py {asset} docs/그림_작업/받은그림/{asset}` 로 넣는다(크기·불투명·색 수 검사, `art/world3d/{asset}/` 에 저장).
- 넣은 뒤 사용자에게 안내: Godot 를 한 번 열고 → `python tools/fix_texture_import.py` → 게임(`dev/spike3d/game_3d_view.tscn`)에서 F8.

## 3. 만들 면 (먼저 그릴 순서)
"""

TASK_FOOTER = """
## 4. 끝났을 때 보고
- 만든 면 목록, 각 면에 쓴 Pixel Lab 도구와 주요 옵션(크기, 참조 이미지 사용 여부), 크레딧 사용량(확인 가능하면), 크기를 맞추려고 리사이즈한 면, 마음에 안 드는 면과 이유.
- `art/` 밖의 파일은 건드리지 않는다. 커밋·푸시는 사용자가 요청할 때만 한다.
"""


def write_task(faces, asset):
    rows = faces[asset]
    label = rows[0]["asset_label"]
    sprite = ""
    assets_json = os.path.join(ART_REQ, "assets.json")
    if os.path.exists(assets_json):
        import json
        for a in json.load(open(assets_json, encoding="utf-8")):
            if a["id"] == asset:
                sprite = a["sprite"]
    lines = [TASK_HEADER.format(label=label, asset=asset, sprite=sprite or "(없음)")]
    for i, r in enumerate(rows, 1):
        done = "  ← 이미 그림이 있음(건너뛰어도 됨)" if has_art(asset, r["face"]) else ""
        lines.append("### %d. `%s` %sx%s px — %s%s" % (i, r["face"], r["width"], r["height"], r["repeat"], done))
        lines.append("- 틀: `docs/그림_작업/%s`" % r["file"])
        lines.append("- 법선 맵: %s" % ("필요(같은 크기 `%s_n.png`, 못 만들면 회색조 높이 맵 `%s_h.png` 로 대신)" % (r["face"], r["face"]) if r["normal_map"] != "선택" else "선택"))
        lines.append("- 설명: %s" % r["note"])
        lines.append("- 영문 프롬프트: `%s`" % r["prompt_en"])
        lines.append("")
    lines.append(TASK_FOOTER)
    out = os.path.join(ART_REQ, "지시", asset + ".md")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    os.makedirs(os.path.join(ART_REQ, "받은그림", asset), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return out


def do_pixellab(faces):
    a = pick_asset(faces, "만들 자산 번호 또는 id (취소: 엔터)")
    if not a:
        return
    task = write_task(faces, a)
    rel = os.path.relpath(task, ROOT).replace(os.sep, "/")
    first = ("%s 을 읽고 그 지시대로 진행해 줘. 먼저 `/mcp` 로 pixellab 연결과 도구를 확인해서 알려 주고, 첫 번째 면 하나만 만들어서 보여 줘." % rel)
    print("\n작업 지시 파일을 만들었습니다: %s" % rel)
    print("PC 의 Claude Code 에 줄 첫 문장:\n  %s\n" % first)
    if input("지금 이 폴더에서 claude 를 실행할까요? (y/N) ").strip().lower() == "y":
        try:
            subprocess.run(["claude", first], cwd=ROOT, shell=sys.platform.startswith("win"))
        except OSError as e:
            print("claude 를 실행하지 못했습니다(%s). 새 터미널에서 직접 `claude` 를 실행한 뒤 위 문장을 붙여 넣으세요." % e)
    elif copy_clip(first):
        print("첫 문장을 클립보드에 복사했습니다. 터미널에서 `claude` 를 실행한 뒤 붙여 넣으세요.")


def menu():
    while True:
        faces = load_faces()
        print("=== 3D 마을 그림 작업 도우미 ===")
        print(" 1) 진행 현황")
        print(" 2) 다음에 그릴 면 보기(프롬프트)")
        print(" 3) 그림 넣기")
        print(" 4) 가져오기 설정·검증")
        print(" 5) 요청서·틀 다시 만들기 (Godot 필요)")
        print(" 6) Pixel Lab 으로 만들기 (PC 의 Claude Code + MCP)")
        print(" 0) 종료")
        c = input("번호: ").strip()
        if c == "0":
            return
        if c == "1" and faces:
            show_status(faces)
        elif c == "2" and faces:
            a = input("특정 자산만 볼까요? 번호/id (엔터 = 추천 순서의 다음 면): ").strip()
            if a.isdigit():
                names = ordered_assets(faces)
                a = names[int(a) - 1] if 1 <= int(a) <= len(names) else ""
            show_next(faces, a if a in faces else None)
        elif c == "3" and faces:
            do_ingest(faces)
        elif c == "4":
            do_check()
        elif c == "5":
            do_regen()
        elif c == "6" and faces:
            do_pixellab(faces)
        print()


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    if len(sys.argv) > 1:
        faces = load_faces()
        if sys.argv[1] == "status" and faces:
            show_status(faces)
        elif sys.argv[1] == "next" and faces:
            a, r = next_face(faces)
            if r:
                print("%s / %s : %sx%s  %s\n%s" % (a, r["face"], r["width"], r["height"], r["repeat"], r["prompt_en"]))
        else:
            print(__doc__)
        return
    menu()


if __name__ == "__main__":
    main()
