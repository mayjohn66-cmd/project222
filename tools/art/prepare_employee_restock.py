"""Extract generated arm poses; retain original employee heads and planted feet.

Use --source and --write to create assets. Without --write verify saved assets.
Existing rotation/walk PNGs are never overwritten. North-east uses mirrored
generated north-west arms only, over the original north-east head and legs.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs/그림_작업/받은그림/직원_진열"
KEYS = ["worker_001", "worker_002", "worker_003"]
DIRECTIONS = ["south-east", "south-west", "north-west", "north-east"]


def original(key, direction):
    return Image.open(ROOT / "art/actors" / key / "rotations" /
                      (direction.replace("-", "_") + ".png")).convert("RGBA")


def clean_component(image):
    image = image.copy()
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            pixels[x, y] = (r, g, b, 255) if a >= 180 else (0, 0, 0, 0)
    # Keep the connected character, discard generated specks outside it.
    seen, components = set(), []
    for y in range(image.height):
        for x in range(image.width):
            if not pixels[x, y][3] or (x, y) in seen:
                continue
            stack, component = [(x, y)], []
            seen.add((x, y))
            while stack:
                px, py = stack.pop()
                component.append((px, py))
                for nx, ny in [(px-1, py), (px+1, py), (px, py-1), (px, py+1)]:
                    if (0 <= nx < image.width and 0 <= ny < image.height
                            and (nx, ny) not in seen and pixels[nx, ny][3]):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            components.append(component)
    keep = set(max(components, key=len))
    for component in components:
        if len(component) < 100:
            for p in component:
                if p not in keep:
                    pixels[p] = (0, 0, 0, 0)
    return image


def head_axis(image):
    box = image.getbbox()
    top = box[1]
    bottom = top + round((box[3]-top)*0.30)
    points = [(x, y) for y in range(top, bottom) for x in range(image.width)
              if image.getpixel((x, y))[3]]
    return sum(x+0.5 for x, _ in points)/len(points)


def generate(source):
    sheet = Image.open(source).convert("RGBA")
    if abs(sheet.width/sheet.height - 4/9) > 0.02:
        raise ValueError("Expected corrected 4-column, 9-row sheet")
    DOC.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, DOC / "생성_원본.png")
    manifest = {"generated_source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "frame_size": [64, 64], "phase_weights": [0.15, 0.30, 0.35, 0.20],
                "protected_foot_rows": [51, 64], "employees": {}}
    preview = Image.new("RGBA", (4*192, 12*192), (65, 55, 45, 255))
    for ki, key in enumerate(KEYS):
        # Original colors only, plus three carton colors from its generated source.
        colors = sorted({p[:3] for d in DIRECTIONS for p in original(key, d).get_flattened_data() if p[3]})
        palette = colors + [(130, 88, 48), (174, 125, 70), (211, 164, 103)]
        entry = {}
        for di, direction in enumerate(DIRECTIONS):
            base = original(key, direction)
            head_box = (0, 0, 64, 26)
            donor_row = ki*3 + min(di, 2)
            frames = []
            for frame in range(4):
                # Generated front-left raised pose reached right. Mirror only the
                # matching front-right arm pose; retain original front-left head.
                selected_row = ki*3 if di == 1 and frame == 1 else donor_row
                mirrored = di == 3 or (di == 1 and frame == 1)
                cell = sheet.crop((round(frame*sheet.width/4), round(selected_row*sheet.height/9),
                                   round((frame+1)*sheet.width/4), round((selected_row+1)*sheet.height/9)))
                cell = clean_component(cell)
                box = cell.getbbox()
                factor = (base.getbbox()[3]-base.getbbox()[1])/(box[3]-box[1])
                reduced = cell.resize((round(cell.width*factor), round(cell.height*factor)), Image.Resampling.NEAREST)
                if mirrored:
                    reduced = reduced.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                aligned = Image.new("RGBA", (64, 64))
                dx = round(head_axis(base)-head_axis(reduced))
                dy = base.getbbox()[1]-reduced.getbbox()[1]
                aligned.alpha_composite(reduced, (dx, dy))
                # Quantize only the new waist/arm region. Head/feet copied exactly.
                out = base.copy()
                nearest = {}
                for y in range(26, 51):
                    for x in range(64):
                        r, g, b, a = aligned.getpixel((x, y))
                        if not a:
                            out.putpixel((x, y), (0, 0, 0, 0))
                            continue
                        rgb = (r, g, b)
                        if rgb not in nearest:
                            nearest[rgb] = min(palette, key=lambda p: sum((p[i]-rgb[i])**2 for i in range(3)))
                        out.putpixel((x, y), (*nearest[rgb], 255))
                out.paste(base.crop(head_box), head_box)
                for y in range(26, 31):
                    for x in range(64):
                        if base.getpixel((x, y))[3]:
                            out.putpixel((x, y), base.getpixel((x, y)))
                target = ROOT / "art/actors" / key / "animations/restock" / direction / ("frame_%03d.png" % frame)
                target.parent.mkdir(parents=True, exist_ok=True)
                out.save(target)
                frames.append({"path": target.relative_to(ROOT).as_posix(),
                               "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                               "donor_row_zero_based":selected_row, "arms_mirrored":mirrored})
                preview.alpha_composite(out.resize((192, 192), Image.Resampling.NEAREST),
                                        (frame*192, (ki*4+di)*192))
            entry[direction] = {"frames": frames, "arms_mirrored": di == 3,
                                "protected_head_rect": list(head_box)}
        manifest["employees"][key] = entry
    (DOC / "프레임_목록.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    preview.save(DOC / "동작_점검.png")


def verify():
    manifest = json.loads((DOC / "프레임_목록.json").read_text(encoding="utf-8"))
    checked = 0
    for key, directions in manifest["employees"].items():
        for direction, row in directions.items():
            base = original(key, direction)
            for frame in row["frames"]:
                path = ROOT / frame["path"]
                assert hashlib.sha256(path.read_bytes()).hexdigest() == frame["sha256"]
                out = Image.open(path).convert("RGBA")
                assert out.size == (64, 64)
                assert set(out.getchannel("A").get_flattened_data()) <= {0, 255}
                box = tuple(row["protected_head_rect"])
                assert out.crop(box).tobytes() == base.crop(box).tobytes()
                for y in range(26, 31):
                    for x in range(64):
                        if base.getpixel((x, y))[3]:
                            assert out.getpixel((x, y)) == base.getpixel((x, y))
                top, bottom = manifest["protected_foot_rows"]
                assert out.crop((0, top, 64, bottom)).tobytes() == base.crop((0, top, 64, bottom)).tobytes()
                checked += 1
    print("Employee restock: %d frames, head/feet unchanged, SHA and alpha PASS" % checked)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.write:
        if not args.source:
            parser.error("--write requires --source")
        generate(args.source)
    verify()
