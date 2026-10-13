"""Prepare native generated sword poses without changing accepted idle/walk art.

Default is verification. --write accepts separate male/female 4x8 raw atlases.
Uniform row scale derives from the low-sword recovery pose, not sword bounds
in the high swing. Original heads and planted feet are composited unchanged.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import math
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs/그림_작업/받은그림/플레이어_공격"
DIRECTIONS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
PAD = 16
_CELLS = {}


def components(points):
    remaining=set(points)
    result=[]
    while remaining:
        first=remaining.pop()
        stack=[first]
        group=[first]
        while stack:
            x,y=stack.pop()
            for dx,dy in [(a,b) for a in [-1,0,1] for b in [-1,0,1] if a or b]:
                p=(x+dx,y+dy)
                if p in remaining:
                    remaining.remove(p)
                    stack.append(p)
                    group.append(p)
        result.append(group)
    return result


def split_sheet(sheet):
    # Use connected silhouettes, not cell edges: generated swords can cross a
    # nominal cell edge into transparent padding without touching another actor.
    groups=components((x,y) for y in range(sheet.height) for x in range(sheet.width)
                      if sheet.getpixel((x,y))[3]>=180)
    found={}
    for group in sorted(groups,key=len,reverse=True):
        if len(group)<1000: continue
        cx=sum(p[0] for p in group)/len(group)
        cy=sum(p[1] for p in group)/len(group)
        address=(min(7,int(cy/(sheet.height/8))),min(3,int(cx/(sheet.width/4))))
        if address in found: continue
        row,col=address
        x0=round(col*sheet.width/4)-64
        y0=round(row*sheet.height/8)-64
        image=Image.new("RGBA",(round(sheet.width/4)+128,round(sheet.height/8)+128))
        for x,y in group: image.putpixel((x-x0,y-y0),(*sheet.getpixel((x,y))[:3],255))
        found[address]=image
    if len(found)!=32: raise ValueError("Expected 32 isolated player/weapon silhouettes")
    _CELLS[id(sheet)]=found


def hair_center(image):
    points=[(x,y) for y in range(image.height) for x in range(image.width)
            if (lambda p: p[3] and p[0]>p[1]*1.12 and max(p[:3])<180)(image.getpixel((x,y)))]
    group=max(components(points),key=len)
    return sum(p[0]+0.5 for p in group)/len(group),sum(p[1]+0.5 for p in group)/len(group)


def original(key, direction):
    return Image.open(ROOT / "art/actors" / key / "rotations" /
                      (direction.replace("-", "_") + ".png")).convert("RGBA")


def cell(sheet, row, col):
    return _CELLS[id(sheet)][row,col]


def generate(sources):
    DOC.mkdir(parents=True, exist_ok=True)
    manifest = {"frame_size":[96,96], "original_padding":[PAD,PAD],
                "playback_order":[1,2,3,0], "phase_weights":[0.16,0.24,0.35,0.25], "players":{}}
    for key, source in sources.items():
        sheet = Image.open(source).convert("RGBA")
        if abs(sheet.width/sheet.height-0.5) > 0.02:
            raise ValueError("Expected regular 4x8 atlas")
        split_sheet(sheet)
        shutil.copy2(source, DOC / (key+"_원본.png"))
        colors = sorted({p[:3] for d in DIRECTIONS for p in original(key,d).get_flattened_data() if p[3]})
        palette = colors + [(40,44,54), (91,105,118), (165,186,196), (223,231,227)]
        preview = Image.new("RGBA", (4*192,8*192), (65,55,45,255))
        result = {"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(), "directions":{}}
        for row, direction in enumerate(DIRECTIONS):
            base = original(key,direction)
            padded = Image.new("RGBA", (96,96))
            padded.alpha_composite(base,(PAD,PAD))
            # Recovery pose has blade below waist, so source height is body height.
            reference = cell(sheet,row,3)
            box = reference.getbbox()
            factor = (base.getbbox()[3]-base.getbbox()[1])/(box[3]-box[1])
            size = (round(reference.width*factor),round(reference.height*factor))
            reference = reference.resize(size,Image.Resampling.NEAREST)
            base_hair=hair_center(base.crop((0,0,64,30)))
            head_box = base.crop((0,0,64,30)).getbbox()
            # Include transparent outline gap around the original head, to avoid
            # leaving a second generated hair silhouette around the protected one.
            head_box = (max(0,head_box[0]-1)+PAD, PAD,
                        min(64,head_box[2]+1)+PAD, 30+PAD)
            frames = []
            for index in range(4):
                donor_row = row
                mirrored = key == "player_male" and direction == "north-west" and index == 1
                if mirrored: donor_row = 3
                generated = cell(sheet,donor_row,index).resize(size,Image.Resampling.NEAREST)
                if mirrored: generated = generated.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                hair=hair_center(generated)
                dx=round(base_hair[0]+PAD-hair[0])
                dy=round(base_hair[1]+PAD-hair[1])
                aligned = Image.new("RGBA", (96,96))
                aligned.alpha_composite(generated,(dx,dy))
                nearest = {}
                for y in range(96):
                    for x in range(96):
                        p = aligned.getpixel((x,y))
                        if not p[3]: continue
                        rgb = p[:3]
                        if rgb not in nearest:
                            nearest[rgb] = min(palette,key=lambda q:sum((q[i]-rgb[i])**2 for i in range(3)))
                        aligned.putpixel((x,y),(*nearest[rgb],255))
                out=padded.copy()
                arm_box=(0,PAD+29,96,PAD+51)
                out.paste(aligned.crop(arm_box),arm_box)
                # Keep only blade-colored clusters outside the arm band; copied
                # heads/legs remove all generated identity or extra foot pixels.
                steel=[]
                for y in range(96):
                    for x in range(96):
                        r,g,b,a=aligned.getpixel((x,y))
                        if a and max(r,g,b)>=105 and max(r,g,b)-min(r,g,b)<=max(r,g,b)*0.30 and b>=r*0.88:
                            if y>=PAD+49 and abs(x-(base_hair[0]+PAD))<14: continue
                            steel.append((x,y))
                mask=Image.new("L",(96,96))
                for group in components(steel):
                    if len(group)<8: continue
                    cx=sum(p[0] for p in group)/len(group); cy=sum(p[1] for p in group)/len(group)
                    xx=sum((p[0]-cx)**2 for p in group)/len(group)
                    yy=sum((p[1]-cy)**2 for p in group)/len(group)
                    xy=sum((p[0]-cx)*(p[1]-cy) for p in group)/len(group)
                    span=math.sqrt((xx-yy)**2+4*xy*xy)
                    long_axis=(xx+yy+span)/2; short_axis=(xx+yy-span)/2
                    if math.sqrt((long_axis+0.2)/(short_axis+0.2))<2.2: continue
                    for p in group: mask.putpixel(p,255)
                near_blade=mask.filter(ImageFilter.MaxFilter(17))
                hands=Image.new("L",(96,96))
                for y in range(96):
                    for x in range(96):
                        r,g,b,a=aligned.getpixel((x,y))
                        if a and r>=175 and g<r*0.85 and b<r*0.85 and near_blade.getpixel((x,y)):
                            hands.putpixel((x,y),255)
                mask=mask.filter(ImageFilter.MaxFilter(5))
                hands=hands.filter(ImageFilter.MaxFilter(3))
                for y in range(96):
                    for x in range(96):
                        if hands.getpixel((x,y)): mask.putpixel((x,y),255)
                out.paste(aligned,(0,0),mask)
                out.paste(padded.crop(head_box),head_box)
                # The sword can pass IN FRONT of the unchanged original hair.
                # This is occlusion, not redrawing or moving the head.
                out.paste(aligned,(0,0),mask)
                feet_box = (PAD,PAD+51,PAD+64,PAD+64)
                out.paste(padded.crop(feet_box),feet_box)
                path = ROOT / "art/actors" / key / "animations/attack" / direction / ("frame_%03d.png"%index)
                path.parent.mkdir(parents=True,exist_ok=True)
                out.save(path)
                frames.append({"path":path.relative_to(ROOT).as_posix(),
                               "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                               "donor_row_zero_based":donor_row,"arms_mirrored":mirrored,
                               "weapon_head_pixels":[[x,y] for y in range(head_box[1],head_box[3])
                                                     for x in range(head_box[0],head_box[2])
                                                     if out.getpixel((x,y))!=padded.getpixel((x,y))]})
                preview.alpha_composite(out.resize((192,192),Image.Resampling.NEAREST),(index*192,row*192))
            result["directions"][direction] = {"frames":frames,"protected_head_rect":head_box,
                                                "protected_feet_rect":feet_box,"uniform_scale":factor}
        manifest["players"][key] = result
        preview.save(DOC/(key+"_점검.png"))
        frames = [Image.open(ROOT/result["directions"]["south-east"]["frames"][i]["path"]).resize((288,288),Image.Resampling.NEAREST)
                  for i in manifest["playback_order"]]
        backgrounds=[]
        for frame in frames:
            bg=Image.new("RGBA",(288,288),(65,55,45,255))
            bg.alpha_composite(frame)
            backgrounds.append(bg)
        backgrounds[0].save(DOC/(key+"_preview.gif"),save_all=True,append_images=backgrounds[1:],duration=[60,80,120,80],loop=0,disposal=2)
    (DOC/"프레임_목록.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def verify():
    manifest=json.loads((DOC/"프레임_목록.json").read_text(encoding="utf-8"))
    checked=0
    for key,result in manifest["players"].items():
        for direction,row in result["directions"].items():
            padded=Image.new("RGBA",(96,96))
            padded.alpha_composite(original(key,direction),(PAD,PAD))
            for frame in row["frames"]:
                path=ROOT/frame["path"]
                assert hashlib.sha256(path.read_bytes()).hexdigest()==frame["sha256"]
                image=Image.open(path).convert("RGBA")
                assert image.size==(96,96)
                assert set(image.getchannel("A").get_flattened_data())<={0,255}
                box=tuple(row["protected_feet_rect"])
                assert image.crop(box).tobytes()==padded.crop(box).tobytes()
                occluded={tuple(p) for p in frame["weapon_head_pixels"]}
                box=row["protected_head_rect"]
                for y in range(box[1],box[3]):
                    for x in range(box[0],box[2]):
                        if (x,y) not in occluded: assert image.getpixel((x,y))==padded.getpixel((x,y))
                assert not image.getchannel("A").crop((0,0,96,1)).getbbox()
                assert not image.getchannel("A").crop((0,95,96,96)).getbbox()
                checked+=1
    print("Player attack: %d PNGs; head/feet, alpha, padding and SHA PASS"%checked)


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--male",type=Path)
    parser.add_argument("--female",type=Path)
    parser.add_argument("--write",action="store_true")
    args=parser.parse_args()
    if args.write:
        if not args.male or not args.female: parser.error("--write requires both native source atlases")
        generate({"player_male":args.male,"player_female":args.female})
    verify()
