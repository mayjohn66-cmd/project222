#!/usr/bin/env python3
"""실제 그림(Pixel Lab 등으로 만든 PNG)을 3D 마을용 규격 폴더에 넣는 도구.

  python tools/ingest_world3d.py <자산id> <파일 또는 폴더 ...> [--resize] [--dry-run]

- 자산 id 와 면 이름·크기는 docs/drafts/art_requests/faces.csv(그림 요청 문서가 쓰는 표)에서 읽는다.
- 입력 파일 이름에서 면 이름을 알아낸다: `wall_front.png`, `moss_cottage_wall_front.png`, `face_wall_front.png` 모두 가능.
    * `..._n.png` = 법선 맵 그대로,  `..._h.png` = 높이 맵(회색조) → 법선 맵으로 변환(tools/height_to_normal.py)
- 검사: 불투명(알파 255 만), 색 수(알베도 16 이하), 크기가 요청서와 같은지. 크기가 다르면 기본은 거절하고,
  `--resize` 를 주면 최근접(nearest)으로 맞춘다(Pixel Lab 이 정확한 크기를 못 낼 때. 줄이면 도트가 뭉개질 수 있으니 눈으로 확인할 것).
- 결과: art/world3d/<자산id>/<면이름>.png (+ <면이름>_n.png). 그 뒤 Godot 에서 한 번 열어 .import 를 만들고
  `python tools/fix_texture_import.py` 로 무손실 설정을 맞춘 다음, 게임(game_3d_view.tscn)에서 F8 로 다시 읽는다.
Pillow 만 필요하다.
"""
import argparse
import csv
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import height_to_normal  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACES_CSV = os.path.join(ROOT, "docs", "drafts", "art_requests", "faces.csv")
OUT_DIR = os.path.join(ROOT, "art", "world3d")
MAX_COLORS = 16


def load_faces(asset):
    faces = {}
    with open(FACES_CSV, encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if row["asset"] == asset:
                faces[row["face"]] = (int(row["width"]), int(row["height"]), row["normal_map"] != "선택")
    return faces


def split_name(stem, asset, face_names):
    """파일 이름(확장자 없음) → (면 이름, 종류 albedo|normal|height) 또는 None."""
    kind = "albedo"
    if stem.endswith("_n"):
        kind, stem = "normal", stem[:-2]
    elif stem.endswith("_h"):
        kind, stem = "height", stem[:-2]
    for prefix in ("face_", asset + "_"):
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
    if stem in face_names:
        return stem, kind
    return None


def collect(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            for fn in sorted(os.listdir(p)):
                if fn.lower().endswith(".png"):
                    files.append(os.path.join(p, fn))
        else:
            files.append(p)
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("asset")
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--resize", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(FACES_CSV):
        sys.exit("faces.csv 가 없음: python tools/build_art_request_doc.py 로 먼저 만드세요.")
    faces = load_faces(a.asset)
    if not faces:
        sys.exit("자산 id 를 찾을 수 없음: %s (faces.csv 의 asset 열 참고)" % a.asset)

    ok, bad, provided = [], [], set()
    out_folder = os.path.join(OUT_DIR, a.asset)
    for path in collect(a.paths):
        stem = os.path.splitext(os.path.basename(path))[0]
        parsed = split_name(stem, a.asset, faces)
        if parsed is None:
            bad.append((path, "면 이름을 알 수 없음(요청서의 면 이름과 같게: %s)" % ", ".join(sorted(faces))))
            continue
        face, kind = parsed
        want_w, want_h, _ = faces[face]
        try:
            im = Image.open(path)
        except OSError as e:
            bad.append((path, "이미지를 열 수 없음: %s" % e))
            continue
        im = im.convert("RGBA")
        if kind == "albedo" or kind == "height":
            alpha = [px[3] for px in im.getdata()]
            if min(alpha) < 255 and kind == "albedo":
                bad.append((path, "투명/반투명 픽셀이 있음(모든 면은 불투명이어야 함)"))
                continue
        if im.size != (want_w, want_h):
            if not a.resize:
                bad.append((path, "크기 %dx%d (요청서 %dx%d) — 맞추려면 --resize" % (im.width, im.height, want_w, want_h)))
                continue
            im = im.resize((want_w, want_h), Image.NEAREST)
            print("주의: %s 를 %dx%d 로 최근접 축소/확대함(눈으로 확인)" % (os.path.basename(path), want_w, want_h))
        if kind == "albedo":
            colors = len(set(px[:3] for px in im.getdata()))
            if colors > MAX_COLORS:
                print("주의: %s 색 %d개(상한 %d 권장)" % (os.path.basename(path), colors, MAX_COLORS))
        target = os.path.join(out_folder, face + (".png" if kind == "albedo" else "_n.png"))
        if kind == "height":
            im = height_to_normal.convert(im.convert("L"))
        else:
            im = im.convert("RGB")
        if not a.dry_run:
            os.makedirs(out_folder, exist_ok=True)
            im.save(target)
        ok.append((path, os.path.relpath(target, ROOT)))
        if kind == "albedo":
            provided.add(face)

    print("\n통과 %d개, 거절 %d개" % (len(ok), len(bad)))
    for src, dst in ok:
        print("  OK  %s → %s" % (os.path.basename(src), dst))
    for src, why in bad:
        print("  X   %s — %s" % (os.path.basename(src), why))
    missing = [f for f in faces if f not in provided and not os.path.exists(os.path.join(out_folder, f + ".png"))]
    if missing:
        print("\n아직 그림이 없는 면(임시 질감이 계속 쓰임): %s" % ", ".join(missing))
    if ok and not a.dry_run:
        print("\n다음: Godot 를 한 번 열어 .import 생성 → python tools/fix_texture_import.py → 게임에서 F8")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
