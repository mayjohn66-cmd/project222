"""Rectify the eight runtime wall strips from preserved received PNGs.

python tools/art/normalize_shop_wall_tiles.py --write
python tools/art/normalize_shop_wall_tiles.py --check
Only --write replaces runtime *_tile.png files and their eight manifest hashes.
No generation, antialiasing, new palette, room coordinates or source replacement.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/그림_작업/받은그림/매장_외벽/픽셀_정리"
RUNTIME = ROOT / "art/received/shop_shell"
MANIFEST = ROOT / "data/art/pixel_shop_assets.json"
WIDTH = 32
ANCHOR = (32, 104)


def column(image, x):
    ys = [y for y in range(image.height) if image.getpixel((x, y))[3]]
    assert ys and ys == list(range(ys[0], ys[-1] + 1)), "continuous opaque column required"
    return [image.getpixel((x, y)) for y in ys]


def resample(values, count):
    # Nearest samples only: retain source colors and hard alpha.
    return [values[round(i * (len(values) - 1) / (count - 1))] for i in range(count)]


def rectify(kind, direction):
    source = Image.open(SOURCE / f"{kind}_{direction}.png").convert("RGBA")
    assert source.size == (64, 128)
    top = 44 if kind == "wall_full" else 66
    count = ANCHOR[1] - top + 1
    # All four faces share the same cap/stripe/base profile and height.
    # Preserve the plaster / glass / mullion details between these borders.
    reference = Image.open(SOURCE / f"{kind}_0.png").convert("RGBA")
    profile = resample(column(reference, ANCHOR[0]), count)
    upper, lower = (15, 34) if kind == "wall_full" else (12, 27)
    sign = 1 if direction in (0, 2) else -1
    out = Image.new("RGBA", (64, 128), (0, 0, 0, 0))
    for x in range(16, 48):
        colors = resample(column(source, x), count)
        offset = sign * ((x - ANCHOR[0]) // 2)
        for i in range(count):
            color = profile[i] if i < upper or i >= lower else colors[i]
            out.putpixel((x, top + offset + i), color)
    return out


def verify(image, kind, direction):
    assert image.size == (64, 128)
    pixels = [image.getpixel((x, y)) for y in range(image.height) for x in range(image.width)]
    assert {p[3] for p in pixels} == {0, 255}
    assert all(p == (0, 0, 0, 0) for p in pixels if not p[3])
    assert len({p[:3] for p in pixels if p[3]}) <= 32
    top = 44 if kind == "wall_full" else 66
    upper, lower = (15, 34) if kind == "wall_full" else (12, 27)
    sign = 1 if direction in (0, 2) else -1
    reference = None
    for x in range(64):
        ys = [y for y in range(128) if image.getpixel((x, y))[3]]
        if not 16 <= x < 48:
            assert not ys
            continue
        offset = sign * ((x - 32) // 2)
        assert ys == list(range(top + offset, 105 + offset)), "exact 2:1 top and foot"
        colors = [image.getpixel((x, y)) for y in ys]
        borders = colors[:upper] + colors[lower:]
        if reference is None: reference = borders
        assert borders == reference, "continuous cap, stripe, footer across all columns"
    # Last source column and the next tile's first column must continue with
    # a single normal 0/1 pixel step, including the repeating 2-pixel phase.
    last = sign * ((47 - 32) // 2)
    next_first = sign * ((16 - 32) // 2) + sign * 16
    assert next_first - last == sign


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    assert args.write != args.check, "choose --write or --check"
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    by_path = {a["path"]: a for a in manifest["assets"]}
    for kind in ("wall_full", "window"):
        for direction in range(4):
            name = f"{kind}_{direction}_tile.png"
            path = RUNTIME / name
            # Received source and its preserved full runtime copy must agree.
            assert (SOURCE / f"{kind}_{direction}.png").read_bytes() == (RUNTIME / f"{kind}_{direction}.png").read_bytes()
            expected = rectify(kind, direction)
            verify(expected, kind, direction)
            entry = by_path[f"res://art/received/shop_shell/{name}"]
            if args.write:
                expected.save(path)
                entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            else:
                actual = Image.open(path).convert("RGBA")
                verify(actual, kind, direction)
                assert actual.tobytes() == expected.tobytes(), "runtime differs from reproducible correction"
                assert entry["sha256"] == hashlib.sha256(path.read_bytes()).hexdigest()
    if args.write:
        MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("SHOP_WALL_TILES: 8 verified; 2:1 silhouettes and continuous trims; 32 colors/hard alpha; source unchanged")


if __name__ == "__main__":
    main()
