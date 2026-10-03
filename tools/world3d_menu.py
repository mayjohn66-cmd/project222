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
참고: 이 도구는 이미지를 직접 만들지 않는다. Pixel Lab 등에서 만든 PNG 를 규격에 맞게 넣는 흐름이다.
Pillow 가 필요하다(pip install pillow).
"""
import csv
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART_REQ = os.path.join(ROOT, "docs", "drafts", "art_requests")
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
    print("  틀 PNG    : docs/drafts/art_requests/%s  (이 크기·배치 그대로 새로 그리기)" % r["file"])
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


def menu():
    while True:
        faces = load_faces()
        print("=== 3D 마을 그림 작업 도우미 ===")
        print(" 1) 진행 현황")
        print(" 2) 다음에 그릴 면 보기(프롬프트)")
        print(" 3) 그림 넣기")
        print(" 4) 가져오기 설정·검증")
        print(" 5) 요청서·틀 다시 만들기 (Godot 필요)")
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
