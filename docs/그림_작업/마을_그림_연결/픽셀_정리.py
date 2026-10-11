from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json, colorsys
ROOT = Path(__file__).resolve().parents[3]
SPECS = [
    ("market_stall", "art/world/village_decor_v6/market_stall_frame_tile_aligned.png", 144, (695,828.5), [(670,992),(320,824),(720,665),(1070,833)], ["res://art/world/village_decor_v6/market_stall_quarter_turn.png"]),
    ("herb_stall", "art/world/plaza_props_v1/herb_stall_tile_aligned_v4.png", 144, (755,938), [(679,1107),(355,949),(831,769),(1155,927)], ["res://art/world/plaza_props_v1/herb_stall_roof_diamond_v6.png"]),
    ("supply_cart", "art/world/plaza_props_v1/supply_cart_tile_aligned_v2.png", 96, (875,580), [(770,780),(480,630),(980,380),(1270,530)], ["res://art/world/plaza_props_v1/supply_cart_tile_aligned_v3.png"]),
    ("moss_cottage_front", "art/world/village_houses_v2/moss_cottage.png", 288, (770,740), [(770,998),(254,740),(770,482),(1286,740)], ["res://art/world/village_houses_v2/moss_cottage_180.png"]),
    ("ochre_townhouse_front", "art/world/village_houses_v2/ochre_townhouse.png", 288, (770,740), [(770,998),(254,740),(770,482),(1286,740)], []),
    ("ochre_townhouse_rear", "art/world/village_houses_v2/ochre_townhouse_rear.png", 288, (765,728), [(790,1010),(225,728),(740,446),(1305,728)], ["res://art/world/village_houses_v2/ochre_townhouse_rear_aligned.png"]),
]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
assets = []
for id,source,span,anchor,footprint,aliases in SPECS:
    path = ROOT / source
    raw = Image.open(path).convert("RGBA")
    alpha = raw.getchannel("A").point(lambda v: 255 if v >= 220 else 0)
    box = alpha.getbbox()
    raw.putalpha(alpha)
    image = raw.crop(box)
    ratio = span / (max(p[0] for p in footprint) - min(p[0] for p in footprint))
    size = (round(image.width * ratio), round(image.height * ratio))
    image = image.resize(size, Image.Resampling.NEAREST)
    mask = image.getchannel("A")
    rgb = image.convert("RGB").quantize(colors=80, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    image = rgb.convert("RGBA"); image.putalpha(mask)
    image.paste((0,0,0,0),(0,0,image.width,image.height),mask.point(lambda v:255-v))
    canvas = Image.new("RGBA", (((size[0]+15)//8)*8, ((size[1]+15)//8)*8))
    canvas.paste(image,(4,4))
    target = ROOT / "art/received/village" / (id+".png")
    target.parent.mkdir(parents=True,exist_ok=True); canvas.save(target)
    # Exact X/Y factors introduced by integer rounding are recorded, never stretched in the renderer.
    rx,ry = size[0]/(box[2]-box[0]),size[1]/(box[3]-box[1])
    def point(p): return [round((p[0]-box[0])*rx+4,4),round((p[1]-box[1])*ry+4,4)]
    assets.append({"id":id,"path":"res://"+target.relative_to(ROOT).as_posix(),"source":source,"aliases":["res://"+source,*aliases],"anchor":point(anchor),"footprint":[point(p) for p in footprint],"source_sha256":sha(path),"sha256":sha(target),"size":list(canvas.size),"colors":sum(1 for count,color in image.getcolors(image.width*image.height) if color[3] == 255),"alpha_threshold":220})
# Saved front-roof colours use the same body pixels and silhouette.
base_row = next(row for row in assets if row["id"] == "moss_cottage_front")
base_path = ROOT / base_row["path"].removeprefix("res://")
base_image = Image.open(base_path).convert("RGBA")
source_image = Image.open(ROOT / base_row["source"]).convert("RGBA")
source_box = source_image.getchannel("A").point(lambda v:255 if v>=220 else 0).getbbox()
# Match the actual non-padding resized image size, not canvas rounding.
source_span = 1286-254
rx = 288/source_span
size = (round((source_box[2]-source_box[0])*rx),round((source_box[3]-source_box[1])*rx))
mask = Image.new("L",source_image.size)
draw = ImageDraw.Draw(mask)
draw.polygon([(505,250),(855,42),(1240,467),(946,655)],fill=255)
draw.polygon([(295,445),(505,250),(555,269),(336,473)],fill=255)
draw.polygon([(370,508),(516,408),(645,576),(584,606)],fill=255)
small = mask.crop(source_box).resize(size,Image.Resampling.NEAREST)
canvas_mask = Image.new("L",base_image.size);canvas_mask.paste(small,(4,4))
roof_pixels=[]; body_colors=set()
for y in range(base_image.height):
    for x in range(base_image.width):
        r,g,b,a=base_image.getpixel((x,y))
        h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
        if a and canvas_mask.getpixel((x,y)) and 0.16<h<0.40 and s>0.2 and g>r*0.90:
            roof_pixels.append((x,y,r,g,b))
        elif a: body_colors.add((r,g,b))
assert roof_pixels
base_row["roof_variants"]={}
for name,colour in {"blue":"597d9c","terracotta":"ad6547","ochre":"bc934d"}.items():
    target_rgb=tuple(int(colour[i:i+2],16)/255 for i in (0,2,4))
    th,ts,tv=colorsys.rgb_to_hsv(*target_rgb)
    strip=Image.new("RGB",(len(roof_pixels),1))
    for i,(_,_,r,g,b) in enumerate(roof_pixels):
        _,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
        strip.putpixel((i,0),tuple(round(c*255) for c in colorsys.hsv_to_rgb(th,min(1,ts*(0.75+s*0.5)),min(1,v*tv/0.60))))
    strip=strip.quantize(colors=max(2,96-len(body_colors)),dither=Image.Dither.NONE).convert("RGB")
    variant=base_image.copy()
    for i,(x,y,_,_,_) in enumerate(roof_pixels): variant.putpixel((x,y),(*strip.getpixel((i,0)),255))
    target=base_path.with_name("moss_cottage_front_"+name+".png");variant.save(target)
    base_row["roof_variants"][colour]={"path":"res://"+target.relative_to(ROOT).as_posix(),"sha256":sha(target),"roof_pixels":len(roof_pixels)}

(ROOT/"data/art/village_sprite_assets.json").write_text(json.dumps({"assets":assets},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Prepared",len(assets),"village sprites; sources preserved")
