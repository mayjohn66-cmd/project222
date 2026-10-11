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

RECOVERED = "docs/그림_작업/받은그림/마을_원본_복구/"
# 그림 지면/기둥의 바닥을 실제 복구본에서 대조했다. 건물 앞 포장 일부는 보행 가능하다.
RESTORED_SPECS = [
    ("blacksmith", "blacksmith_iso", 224, [(760,985),(75,728),(760,455),(1460,728)], "blacksmith_v2/blacksmith_iso.png", .82, 1.0),
    ("tool_shop", "tool_shop", 272, [(850,965),(245,765),(740,495),(1360,765)], "tool_shop_v1/tool_shop.png", .88, 1.0),
    ("red_house_front", "red_house", 288, [(995,970),(240,730),(710,445),(1410,715)], "houses_v1/red_house.png", .97, 1.0),
    ("red_house_turned", "red_house_quarter_turn", 288, [(925,980),(115,545),(745,280),(1460,735)], "houses_v1/red_house_quarter_turn.png", .97, 1.0),
    ("bakery", "bakery", 232, [(780,965),(240,715),(785,445),(1300,715)], "village_buildings_v1/bakery.png", .88, 1.0),
    ("granary", "granary", 264, [(670,955),(235,750),(875,440),(1340,745)], "village_buildings_v1/granary.png", .97, 1.0),
    ("stable", "stable", 256, [(850,955),(230,625),(775,370),(1350,755)], "village_buildings_v1/stable.png", .88, 1.0),
    ("moss_cottage_rear", "moss_cottage_rear", 288, [(765,980),(250,690),(765,420),(1280,690)], "village_houses_v2/moss_cottage_rear.png", .97, 1.0),
    ("bakery_stall_front", "bakery_front", 144, [(865,1005),(270,730),(870,435),(1350,770)], "market_stalls_v3/bakery_front.png", .97, 1.0),
    ("bakery_stall_rear", "bakery_rear", 144, [(600,950),(315,720),(885,430),(1260,705)], "market_stalls_v3/bakery_rear.png", .97, 1.0),
    ("cloth_stall_front", "cloth_front", 144, [(840,980),(265,710),(860,425),(1290,735)], "market_stalls_v3/cloth_front.png", .97, 1.0),
    ("cloth_stall_rear", "cloth_rear", 144, [(865,960),(335,670),(825,430),(1330,710)], "market_stalls_v3/cloth_rear.png", .97, 1.0),
    ("fish_stall_front", "fish_front", 144, [(885,960),(265,690),(860,420),(1305,700)], "market_stalls_v3/fish_front.png", .97, 1.0),
    ("fish_stall_rear", "fish_rear", 144, [(775,985),(340,720),(890,450),(1280,725)], "market_stalls_v3/fish_rear.png", .97, 1.0),
    ("plaza_crates", "plaza_crates", 64, [(850,940),(270,730),(845,450),(1290,715)], "plaza_props_v1/plaza_crates.png", .97, 1.0),
    ("oak_bench", "oak_bench", 64, [(500,965),(315,900),(1120,500),(1310,610)], "village_gathering_v1/oak_bench.png", .97, 1.0),
    ("street_lantern", "street_lantern", 32, [(850,847),(755,805),(850,755),(945,805)], "village_gathering_v1/street_lantern.png", .97, .55),
    ("noticeboard", "village_noticeboard", 64, [(1085,975),(490,800),(525,730),(1120,905)], "village_gathering_v1/village_noticeboard.png", .97, 1.0),
    ("road_sign", "road_sign", 32, [(540,1250),(425,1205),(550,1145),(640,1205)], "route_props_v1/road_sign.png", .97, .40),
    ("wood_fence", "wood_fence", 64, [(385,915),(305,875),(1125,510),(1225,545)], "route_props_v1/wood_fence.png", .97, 1.0),
    ("village_flower_bush", "flower_bush", 40, [(880,790),(420,625),(880,440),(1340,625)], "route_props_v1/flower_bush.png", .97, 1.0),
]
EXTRA_SETTINGS={}
for asset_id, filename, span, footprint, legacy, inset, display_scale in RESTORED_SPECS:
    anchor=tuple(sum(p[i] for p in footprint)/4 for i in range(2))
    SPECS.append((asset_id,RECOVERED+filename+".png",span,anchor,footprint,["res://art/world/"+legacy]))
    EXTRA_SETTINGS[asset_id]={"collision_inset":inset,"display_scale":display_scale}

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
    assets.append({**EXTRA_SETTINGS.get(id,{}),"id":id,"path":"res://"+target.relative_to(ROOT).as_posix(),"source":source,"aliases":["res://"+source,*aliases],"anchor":point(anchor),"footprint":[point(p) for p in footprint],"source_sha256":sha(path),"sha256":sha(target),"size":list(canvas.size),"colors":sum(1 for count,color in image.getcolors(image.width*image.height) if color[3] == 255),"alpha_threshold":220})
# Saved roof colours alter only selected green roof pixels, never body/alpha.
ROOFS = {
    "moss_cottage_front":[[(505,250),(855,42),(1240,467),(946,655)],[(295,445),(505,250),(555,269),(336,473)],[(370,508),(516,408),(645,576),(584,606)]],
    "moss_cottage_rear":[[(270,280),(690,35),(1320,600),(920,765),(270,500)]],
}
for roof_id,roof_polygons in ROOFS.items():
    original_footprint=next(spec[4] for spec in SPECS if spec[0]==roof_id)

    base_row = next(row for row in assets if row["id"] == roof_id)
    base_path = ROOT / base_row["path"].removeprefix("res://")
    base_image = Image.open(base_path).convert("RGBA")
    source_image = Image.open(ROOT / base_row["source"]).convert("RGBA")
    source_box = source_image.getchannel("A").point(lambda v:255 if v>=220 else 0).getbbox()
    # Match the actual non-padding resized image size, not canvas rounding.
    source_span = max(p[0] for p in original_footprint)-min(p[0] for p in original_footprint)
    rx = 288/source_span
    size = (round((source_box[2]-source_box[0])*rx),round((source_box[3]-source_box[1])*rx))
    mask = Image.new("L",source_image.size)
    draw = ImageDraw.Draw(mask)
    for polygon in roof_polygons: draw.polygon(polygon,fill=255)
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
        target=base_path.with_name(roof_id+"_"+name+".png");variant.save(target)
        base_row["roof_variants"][colour]={"path":"res://"+target.relative_to(ROOT).as_posix(),"sha256":sha(target),"roof_pixels":len(roof_pixels)}


row=next(r for r in assets if r["id"]=="street_lantern")
source=Image.open(ROOT/row["source"]).convert("RGBA")
box=source.getchannel("A").point(lambda v:255 if v>=220 else 0).getbbox()
fp=next(spec[4] for spec in SPECS if spec[0]=="street_lantern")
ratio=32/(max(p[0] for p in fp)-min(p[0] for p in fp))
size=(round((box[2]-box[0])*ratio),round((box[3]-box[1])*ratio))
mask=Image.new("L",source.size)
for y in range(330,525):
    for x in range(970,1130):
        r,g,b,a=source.getpixel((x,y))
        if a>=220 and r>160 and g>95 and b<g*.9: mask.putpixel((x,y),255)
small=mask.crop(box).resize(size,Image.Resampling.NEAREST)
canvas=Image.new("L",tuple(row["size"]));canvas.paste(small,(4,4))
mask_path=ROOT/"art/received/village/street_lantern_glow.png";canvas.save(mask_path)
row["emission_mask"]="res://"+mask_path.relative_to(ROOT).as_posix()
(ROOT/"data/art/village_sprite_assets.json").write_text(json.dumps({"assets":assets},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

print("Prepared",len(assets),"village sprites plus roof colours and glass mask; sources preserved")
