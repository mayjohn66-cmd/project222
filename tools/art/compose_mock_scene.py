#!/usr/bin/env python3
"""2D 도트 시험 장면 합성기: Pixel Lab 으로 만든 바닥 타일·진열대·계산대·캐릭터 PNG 를 한 장면에 놓아 느낌만 본다(게임 코드와 무관).

폴더 구조(파일이 없으면 그 부분은 건너뛴다):
  <폴더>/floor.png      바닥 타일 1장(16x16 또는 32x32, 가로세로 반복)
  <폴더>/shelf.png      진열대
  <폴더>/counter.png    계산대
  <폴더>/player.png     캐릭터(정면 한 장 또는 시트의 첫 칸)
  <폴더>/extra_*.png    그 밖의 소품(냉장고·화분 등), 이름순으로 벽쪽에 늘어놓는다
사용:
  python tools/art/compose_mock_scene.py <폴더> [-o 출력.png] [--scale 3]
장면: 가로 20칸 x 세로 11칸(칸=타일 크기), 위쪽 벽 두 줄, 진열대 둘, 계산대, 점장.
Pillow 필요.
"""
import argparse
import glob
import os

from PIL import Image


def load(folder, name):
    path = os.path.join(folder, name)
    return Image.open(path).convert("RGBA") if os.path.exists(path) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("-o", "--out", default="")
    ap.add_argument("--scale", type=int, default=3)
    args = ap.parse_args()
    floor = load(args.folder, "floor.png")
    if floor is None:
        raise SystemExit("floor.png 가 필요합니다")
    t = floor.size[0]
    cols, rows = 20, 11
    scene = Image.new("RGBA", (cols * t, rows * t), (40, 36, 34, 255))
    for y in range(rows):
        for x in range(cols):
            scene.alpha_composite(floor, (x * t, y * t))
    # 위쪽 벽: 어두운 띠 두 줄
    wall = Image.new("RGBA", (cols * t, 2 * t), (96, 78, 66, 255))
    scene.alpha_composite(wall, (0, 0))

    def put(img, cx, by):
        if img is not None:
            scene.alpha_composite(img, (int(cx * t - img.size[0] / 2), int(by * t - img.size[1])))

    shelf = load(args.folder, "shelf.png")
    put(shelf, 5, 6)
    put(shelf, 9, 6)
    put(shelf, 13, 6)
    put(load(args.folder, "counter.png"), 16, 9)
    put(load(args.folder, "player.png"), 14.5, 9.5)
    for i, path in enumerate(sorted(glob.glob(os.path.join(args.folder, "extra_*.png")))):
        put(Image.open(path).convert("RGBA"), 3 + i * 3, 3)
    out = scene.resize((scene.size[0] * args.scale, scene.size[1] * args.scale), Image.NEAREST)
    path = args.out or os.path.join(args.folder, "mock_scene.png")
    out.convert("RGB").save(path)
    print("저장:", path, out.size)


if __name__ == "__main__":
    main()
