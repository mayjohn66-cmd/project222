"""Prepare the single selected 1-cell wall. Original variants preserve palette history."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/그림_작업/받은그림/돌담_모듈"
PARTS = {"left": "좌", "middle": "중간", "right": "우"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reduce_source(label):
    path = DOC / (label + "_원본.png")
    source = Image.open(path).convert("RGBA")
    alpha = source.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    source.putalpha(alpha)
    bounds = alpha.getbbox()
    assert bounds
    crop = source.crop(bounds)
    factor = 40 / crop.width
    size = (40, round(crop.height * factor))
    body = crop.resize(size, Image.Resampling.NEAREST)
    return body, dict(source=path.relative_to(ROOT).as_posix(), source_sha256=digest(path),
                      source_size=list(source.size), bounds=list(bounds),
                      uniform_scale=factor, body_size=list(size))


def register_end(body, reference):
    # Translation only: never stretch either axis to match generated variants.
    choices = []
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            error = 0
            for x in range(8, 32):
                for y in range(reference.height):
                    ref = reference.getpixel((x, y))
                    sx, sy = x-dx, y-dy
                    if ref[3] and 0 <= sx < body.width and 0 <= sy < body.height:
                        got = body.getpixel((sx, sy))
                        error += sum(abs(ref[c]-got[c]) for c in range(3)) if got[3] else 765
            choices.append((error, abs(dx)+abs(dy), dx, dy))
    _, _, dx, dy = min(choices)
    aligned = Image.new("RGBA", reference.size)
    aligned.alpha_composite(body, (dx, dy))
    return aligned, [dx, dy]


def prepare():
    bodies, records = {}, {}
    for part, label in PARTS.items():
        bodies[part], records[part] = reduce_source(label)
    base = bodies["middle"]
    for part in ("left", "right"):
        bodies[part], shift = register_end(bodies[part], base)
        records[part]["registration_translation"] = shift
    # Quantize together; same stones use the same colors across every join.
    atlas = Image.new("RGB", (120, base.height), (90, 78, 63))
    for i, part in enumerate(PARTS):
        atlas.paste(bodies[part].convert("RGB"), (i*40, 0), bodies[part].getchannel("A"))
    palette = atlas.quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    for part, body in bodies.items():
        alpha = body.getchannel("A")
        body = body.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
        body.putalpha(alpha)
        bodies[part] = body
    base = bodies["middle"]
    # Exact 32px strip; the source slope already rises by 16px over this width.
    # Reusing the middle artwork avoids repeated end-face shadows at joins.
    core = base.crop((4, 0, 36, base.height))
    results = {}
    for part in PARTS:
        out = Image.new("RGBA", (64, 96))
        out.alpha_composite(core, (16, 32))
        if part == "left":
            out.alpha_composite(bodies[part].crop((0, 0, 4, base.height)), (12, 32))
        elif part == "right":
            out.alpha_composite(bodies[part].crop((36, 0, 40, base.height)), (48, 32))
        results[part] = out
    return results, records


def preview(results):
    # One selected image, repeated unchanged on the actual paving.
    canvas = Image.new("RGBA", (240, 256), (46, 40, 35, 255))
    wall = results["wall"]
    canvas.alpha_composite(wall, (88, -12))
    floor = Image.open(ROOT / "art/received/floors/paving_1.png").convert("RGBA")
    for i in range(6):
        x, y = 8+i*32, 100+i*16
        canvas.alpha_composite(floor, (x, y))
    for i in range(6):
        canvas.alpha_composite(wall, (8+i*32, 100+i*16-48))
    out = canvas.resize((960, 1024), Image.Resampling.NEAREST)
    font_path = Path("C:/Windows/Fonts/malgun.ttf")
    font = ImageFont.truetype(str(font_path), 24) if font_path.exists() else ImageFont.load_default()
    draw = ImageDraw.Draw(out)
    draw.text((480, 25), "돌담 1종 · 같은 그림 반복", fill=(232, 215, 188), font=font, anchor="mt")
    draw.text((40, 980), "1칸: 64×32 바닥 / 연결 간격: 가로 32 · 세로 16", fill=(232, 215, 188), font=font)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--install", action="store_true")
    args = ap.parse_args()
    legacy_results, sources = prepare()
    # User correction: one active image; do not output or select left/right variants.
    results = {"wall": legacy_results["middle"]}
    records = dict(mode="built-in image_gen; authorized Python pixel preparation", date="2026-10-12",
                   footprint=[1, 1], floor_tile=[64, 32], canvas=[64, 96], anchor=[32, 64],
                   run_step=[32, 16], orientation="upper-left to lower-right",
                   actual_wall_thickness_cells=0.25, palette_limit=48,
                   alpha_threshold=128, filter="NEAREST", runtime_connected=True,
                   runtime_path="res://art/received/village/stone_wall.png",
                   asset_count=1, selection="single_repeat_wall", pillars=False,
                   repeat_strip=[16, 32, 48, 69], historical_sources=sources, outputs={})
    for part, image in results.items():
        path = DOC / "stone_wall.png"
        colors = {p[:3] for p in image.get_flattened_data() if p[3]}
        assert len(colors) <= 48 and set(image.getchannel("A").get_flattened_data()) <= {0, 255}
        if args.install:
            image.save(path)
        else:
            selected = Image.open(path).convert("RGBA")
            assert selected.size == image.size and selected.tobytes() == image.tobytes(), part
        records["outputs"][part] = dict(path=path.relative_to(ROOT).as_posix(), sha256=digest(path),
                                      colors=len(colors), bounds=list(image.getbbox()))
    original_middle = Image.open(DOC / "stone_wall_middle.png").convert("RGBA")
    assert results["wall"].tobytes() == original_middle.tobytes(), "Selected masonry changed"
    # At the join, both opaque vertical profiles differ by exactly the grid step.
    mid = results["wall"]
    profiles = [[y for y in range(96) if mid.getpixel((x, y))[3]] for x in (16, 47)]
    assert abs(profiles[1][0] - (profiles[0][0]+16)) <= 1
    assert abs(profiles[1][-1] - (profiles[0][-1]+16)) <= 1
    if args.install:
        (DOC / "통일_기록.json").write_text(json.dumps(records, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        preview(results).save(DOC / "돌담_통일_연결_4배.png")
    else:
        saved = json.loads((DOC / "통일_기록.json").read_text(encoding="utf-8"))
        assert records == saved, "Manifest changed"
    print("1 selected wall: 1x1, 64x96, step32/16, original middle pixels unchanged, <=48 colors, binary alpha; runtime connected")


if __name__ == "__main__":
    main()
