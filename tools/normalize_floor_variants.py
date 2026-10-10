"""Normalize floor variants without moving seams or changing the source artwork.

python tools/normalize_floor_variants.py --write
python tools/normalize_floor_variants.py --check
The received source PNGs remain unchanged. Runtime + derived docs copies share bytes.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/그림_작업/받은그림/바닥_등각/정리"
DEST = ROOT / "docs/그림_작업/받은그림/바닥_연결_보정"
RUNTIME = ROOT / "art/received/floors"
KINDS = ("tile", "wood", "paving", "road", "dirt", "grass")


def pixels(image):
    return (image.getpixel((x,y)) for y in range(image.height) for x in range(image.width))


def inside(x, y):
    # Inverse of the existing shader projection at pixel centers.
    u = (x + 0.5) / 64 + (y + 0.5) / 32 - 0.5
    v = (y + 0.5) / 32 - (x + 0.5) / 64 + 0.5
    return 0.12 < u < 0.88 and 0.12 < v < 0.88


def base(kind):
    # Grass_2 is the plain, low density ground; _1/_3 contain a central clump.
    return Image.open(SOURCE / f"{kind}_{2 if kind == 'grass' else 1}.png").convert("RGBA")


def derive(kind, variant):
    image = base(kind)
    if variant == 1:
        return image
    eligible = {c for c, _ in Counter(p[:3] for p in pixels(image) if p[3]).most_common(3)}
    original = image.copy()
    direction = 3 if variant == 2 else -3
    seed = KINDS.index(kind) * 31 + variant * 17
    for y in range(32):
        for x in range(64):
            p = original.getpixel((x, y))
            if not p[3] or p[:3] not in eligible or not inside(x, y):
                continue
            # Small 3x2 clusters, no changed shape/line positions or overall tint.
            h = (((x // 3 + seed) * 734287) ^ ((y // 2 + seed) * 912271)) % 19
            if h > 3:
                continue
            nearby = [original.getpixel((x+dx,y+dy)) for dx,dy in [(-1,0),(1,0),(0,-1),(0,1)]]
            # Do not paint across grout, cracks, plank outlines or grass accents.
            if any(not q[3] or max(abs(p[c]-q[c]) for c in range(3)) > 18 for q in nearby):
                continue
            image.putpixel((x,y),tuple(max(0,min(255,v+direction)) for v in p[:3])+(255,))
    return image


def verify(kind, variant, image):
    original = base(kind)
    assert image.size == (64,32)
    changes = 0
    for y in range(32):
        for x in range(64):
            p, q = image.getpixel((x,y)), original.getpixel((x,y))
            assert p[3] == q[3], "silhouette changed"
            if not p[3]:
                assert p == (0,0,0,0), "transparent RGB"
            if not inside(x,y):
                assert p == q, "common tile edge changed"
            if p != q:
                changes += 1
                assert max(abs(p[c]-q[c]) for c in range(3)) <= 3, "variant contrast exceeds bound"
    opaque = sum(p[3]>0 for p in pixels(original))
    assert changes <= opaque * 0.18, "too much of the common pattern changed"
    if variant > 1:
        assert changes > 0, "variant has no texture variation"
    colors = len({p[:3] for p in pixels(image) if p[3]})
    assert colors <= 64
    return dict(kind=kind,variant=variant,changed_pixels=changes,opaque_pixels=opaque,
                max_channel_delta=3 if changes else 0,common_edge_delta=0,colors=colors)


def patch(kind, corrected):
    images = ([derive(kind,i) for i in range(1,4)] if corrected else
              [Image.open(SOURCE/f"{kind}_{i}.png").convert("RGBA") for i in range(1,4)])
    canvas = Image.new("RGBA",(384,176))
    for x in range(6):
        for y in range(6):
            variant = abs(x*17+y*31)%3
            im=images[variant]
            at=(160+(x-y)*32, (x+y)*16)
            canvas.alpha_composite(im,at)
    return canvas


def preview():
    sheet=Image.new("RGB",(840,1220),(61,53,45))
    draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",18)
    draw.text((24,10),"보정 전: 다른 무늬",font=font,fill=(244,225,194))
    draw.text((444,10),"보정 후: 공통 무늬 + 작은 질감",font=font,fill=(244,225,194))
    for i,kind in enumerate(KINDS):
        y=42+i*195
        draw.text((24,y),kind,font=font,fill=(244,225,194))
        draw.text((444,y),kind,font=font,fill=(244,225,194))
        for col,corrected in enumerate((False,True)):
            im=patch(kind,corrected)
            sheet.paste(im,(20+420*col,y+20),im)
    sheet.save(DEST/"혼합_전후.png")


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--write",action="store_true")
    parser.add_argument("--check",action="store_true")
    args=parser.parse_args()
    if not (args.write or args.check): parser.error("choose --write or --check")
    rows=[]
    for kind in KINDS:
        for variant in range(1,4):
            image=derive(kind,variant)
            row=verify(kind,variant,image)
            name=f"{kind}_{variant}.png"
            if args.write:
                (DEST/"픽셀_정리").mkdir(parents=True,exist_ok=True)
                if variant==1:
                    # Preserve original file bytes for all unmodified common templates.
                    data=(SOURCE/f"{kind}_{2 if kind=='grass' else 1}.png").read_bytes()
                    (DEST/"픽셀_정리"/name).write_bytes(data)
                    (RUNTIME/name).write_bytes(data)
                else:
                    image.save(DEST/"픽셀_정리"/name)
                    (RUNTIME/name).write_bytes((DEST/"픽셀_정리"/name).read_bytes())
            for p in (RUNTIME/name,DEST/"픽셀_정리"/name):
                actual=Image.open(p).convert("RGBA")
                assert actual.tobytes()==image.tobytes(), f"not normalized: {p}"
            assert (RUNTIME/name).read_bytes()==(DEST/"픽셀_정리"/name).read_bytes()
            row["path"]="res://art/received/floors/"+name
            row["sha256"]=hashlib.sha256((RUNTIME/name).read_bytes()).hexdigest()
            row["source"]="docs/그림_작업/받은그림/바닥_연결_보정/픽셀_정리/"+name
            row["reference"]="docs/그림_작업/받은그림/바닥_등각/정리/"+f"{kind}_{2 if kind=='grass' else 1}.png"
            rows.append(row)
    manifests=[ROOT/"data/art/received_assets.json", ROOT/"data/art/pixel_shop_assets.json"]
    expected={r["path"]:r for r in rows}
    touched=0
    for path in manifests:
        manifest=json.loads(path.read_text("utf-8"))
        count=0
        for entry in manifest["assets"]:
            if entry["path"] in expected:
                row=expected[entry["path"]]
                if args.write: entry.update(sha256=row["sha256"],source=row["source"])
                assert entry["sha256"]==row["sha256"]
                assert entry["source"]==row["source"]
                count+=1
        if args.write and count:
            path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        touched+=count
    assert touched==18, f"expected 18 runtime manifest mappings, got {touched}"
    if args.write:
        (DEST/"검사_결과.json").write_text(json.dumps(rows,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        preview()
    print(f"FLOOR_VARIANTS 18 PASS; common edges unchanged; texture deltas <=3; manifests {touched}")


if __name__=="__main__":
    main()
