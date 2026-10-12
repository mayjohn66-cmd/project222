#!/usr/bin/env python3
"""3D 도트 질감 PNG 의 Godot 가져오기 설정(.import)을 무손실로 맞춘다.

Godot 기본값(detect_3d/compress_to=1)은 3D 재질에 쓰이는 질감을 손실 압축(VRAM)으로 다시 가져와서 도트가 번진다.
이 도구는 지정한 폴더의 모든 .png.import 를 아래 값으로 고친다.
    compress/mode=0, detect_3d/compress_to=0, mipmaps/generate=false

사용:
  python tools/art/fix_texture_import.py                 # 기본 폴더(art/world3d, dev/spike3d/textures)를 고침
  python tools/art/fix_texture_import.py --check         # 고치지 않고 어긋난 것만 보고(어긋나면 종료 코드 1)
  python tools/art/fix_texture_import.py art/world3d     # 폴더 지정

새 PNG 는 Godot 가 처음 열어서 .import 를 만든 뒤에 실행한다(없는 .import 는 건너뛰고 알려 준다). 고친 뒤 Godot 에서 다시 가져오기(프로젝트 다시 열기 또는 --import).
"""
import argparse
import os
import re
import sys

# Windows 한국어 환경(cp949)에서 한글·기호 출력 시 UnicodeEncodeError 로 멈추지 않게 한다.
for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

REQUIRED = {
    "compress/mode": "0",
    "detect_3d/compress_to": "0",
    "mipmaps/generate": "false",
}
DEFAULT_DIRS = ["art/world3d", "dev/spike3d/textures"]


def read_params(import_path):
    """.import 의 [params] 구역을 {키: 값(문자열)} 로 읽는다."""
    params = {}
    in_params = False
    with open(import_path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("["):
                in_params = s == "[params]"
                continue
            if in_params and "=" in s:
                k, v = s.split("=", 1)
                params[k] = v
    return params


def mismatches(import_path):
    params = read_params(import_path)
    return [(k, params.get(k), v) for k, v in REQUIRED.items() if params.get(k) != v]


def fix(import_path):
    with open(import_path, encoding="utf-8") as f:
        text = f.read()
    for key, value in REQUIRED.items():
        pattern = re.compile(r"^" + re.escape(key) + r"=.*$", re.M)
        if pattern.search(text):
            text = pattern.sub(f"{key}={value}", text)
        else:
            text = text.replace("[params]\n", f"[params]\n\n{key}={value}\n", 1)
    with open(import_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def collect(dirs):
    pngs, imports = [], []
    for d in dirs:
        for dirpath, _, files in os.walk(d):
            for fn in files:
                if fn.lower().endswith(".png"):
                    full = os.path.join(dirpath, fn)
                    pngs.append(full)
                    if os.path.exists(full + ".import"):
                        imports.append(full + ".import")
    return pngs, imports


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="*", default=DEFAULT_DIRS)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    dirs = [d for d in a.dirs if os.path.isdir(d)]
    pngs, imports = collect(dirs)
    missing = [p for p in pngs if not os.path.exists(p + ".import")]
    bad = 0
    for imp in imports:
        diffs = mismatches(imp)
        if not diffs:
            continue
        bad += 1
        shown = ", ".join(f"{k}={got} (필요 {want})" for k, got, want in diffs)
        if a.check:
            print(f"어긋남: {imp} — {shown}")
        else:
            fix(imp)
            print(f"고침: {imp} — {shown}")
    for p in missing:
        print(f"주의: {p} 의 .import 가 아직 없음(Godot 에서 한 번 열거나 --import 후 다시 실행)")
    print(f"PNG {len(pngs)}개, .import {len(imports)}개, {'어긋남' if a.check else '고침'} {bad}개")
    return 1 if (a.check and (bad or missing)) else 0


if __name__ == "__main__":
    sys.exit(main())
