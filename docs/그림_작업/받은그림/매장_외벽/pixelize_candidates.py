"""User-authorized pixel normalization of image_gen candidates; original art stays intact.
Run from repository root: python -X utf8 docs/그림_작업/받은그림/매장_외벽/pixelize_candidates.py
Requires Pillow. Native outputs are candidates, not installed runtime art.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json
BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[3]
OUTPUT = BASE / "픽셀_정리"
THRESHOLD = 160

def components(image):
    mask = image.getchannel("A").point(lambda v:255 if v >= THRESHOLD else 0)
    raw = mask.tobytes(); width,height = image.size
    parent=[]; runs=[]; previous=[]
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x=parent[x]
        return x
    for y in range(height):
        row=raw[y*width:(y+1)*width]; current=[]; pos=0
        while pos < width:
            start=row.find(b"\xff",pos)
            if start < 0: break
            end=row.find(b"\x00",start)
            if end < 0: end=width
            index=len(parent); parent.append(index); runs.append((start,end,y)); current.append(index)
            for other in previous:
                left,right,_=runs[other]
                if left <= end and right >= start:
                    a,b=find(index),find(other)
                    if a != b: parent[a]=b
            pos=end
        previous=current
    stats={}
    for index,(left,right,y) in enumerate(runs):
        key=find(index)
        if key not in stats: stats[key]=[0,left,y,right,y+1]
        value=stats[key]; value[0]+=right-left
        value[1]=min(value[1],left); value[2]=min(value[2],y)
        value[3]=max(value[3],right); value[4]=max(value[4],y+1)
    return [value for value in stats.values() if value[0] > 1500]

def extract(file, columns, rows):
    source=Image.open(BASE/file).convert("RGBA")
    parts=components(source)
    assert len(parts)==columns*rows,(file,len(parts))
    parts.sort(key=lambda p:(p[2]+p[4])/2)
    ordered=[]
    for row in range(rows):
        ordered.extend(sorted(parts[row*columns:(row+1)*columns],key=lambda p:(p[1]+p[3])/2))
    frames=[]
    for part in ordered:
        bounds=tuple(part[1:]); frame=source.crop(bounds)
        frame.putalpha(frame.getchannel("A").point(lambda v:255 if v >= THRESHOLD else 0))
        frames.append((frame,bounds))
    return source,frames

def place(frame,scale,bottom=116,center=32):
    size=(max(1,round(frame.width*scale)),max(1,round(frame.height*scale)))
    reduced=frame.resize(size,Image.Resampling.NEAREST)
    assert size[0] <= 64 and size[1] <= bottom,(size,scale)
    canvas=Image.new("RGBA",(64,128),(0,0,0,0))
    canvas.alpha_composite(reduced,(round(center-size[0]/2),bottom-size[1]))
    return canvas

def palette_for(frames, extra=()):
    items=list(frames)+list(extra)*4
    sample=Image.new("RGB",(64*8,128*((len(items)+7)//8)),(0,0,0))
    for index,frame in enumerate(items):sample.paste(frame,(index%8*64,index//8*128),frame.getchannel("A"))
    return sample.quantize(colors=32,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)

def quantize(frame,palette):
    result=frame.convert("RGB").quantize(palette=palette,dither=Image.Dither.NONE).convert("RGBA")
    result.putalpha(frame.getchannel("A"))
    # Transparent RGB values are zeroed for stable hashes/clean edge colors.
    clean=Image.new("RGBA",frame.size,(0,0,0,0));clean.paste(result,(0,0),result.getchannel("A"))
    return clean

def font(size):
    return ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",size)

def run():
    assert not OUTPUT.exists(),"Do not overwrite a selected candidate; retain existing outputs."
    OUTPUT.mkdir()
    wall_source,wall=extract("walls_reference_matched.png",4,4)
    window_source,window=extract("windows_reference_matched.png",4,2)
    door_source,doors=extract("door_states_reference_matched.png",8,3)
    names=[*[f"wall_full_{i}" for i in range(4)],*[f"wall_low_{i}" for i in range(4)],"corner_full_inside","corner_full_outside","corner_low_inside","corner_low_outside","wall_cap_left","wall_cap_right","doorway_left","doorway_right"]
    # One scale for the family; actual repeat seam lengths still need calibration.
    wall_scale=80/max(frame.height for frame,_ in wall[:4])
    window_scale=(sum(frame.width for frame,_ in wall[:4])/4*wall_scale)/(sum(frame.width for frame,_ in window[:4])/4)
    frames={}; info=[]
    for name,(frame,bounds) in zip(names,wall):
        frames[name]=place(frame,wall_scale);info.append({"id":name,"source":"walls_reference_matched.png","source_bounds":bounds,"scale":wall_scale})
    window_names=[*[f"window_{i}" for i in range(4)],"window_corner_inside","window_corner_outside","window_cap_left","window_cap_right"]
    for name,(frame,bounds) in zip(window_names,window):
        frames[name]=place(frame,window_scale);info.append({"id":name,"source":"windows_reference_matched.png","source_bounds":bounds,"scale":window_scale})
    wall_palette=palette_for(frames.values())
    for name in list(frames):frames[name]=quantize(frames[name],wall_palette)
    door_names=[]
    for row,kind in enumerate(["entrance","production","warehouse"]):
        for direction in range(4):
            pair=doors[row*8+direction*2:row*8+direction*2+2]
            scale=76/max(frame.height for frame,_ in pair)
            # One scale per pair; top lintel peak is a fixed frame landmark,
            # unlike a silhouette center that would move when the leaf swings.
            reduced=[]
            for frame,bounds in pair:
                thumb=frame.resize((max(1,round(frame.width*scale)),max(1,round(frame.height*scale))),Image.Resampling.NEAREST)
                top=thumb.getchannel("A").crop((0,0,thumb.width,min(3,thumb.height))).getbbox()
                landmark=(top[0]+top[2])/2 if top else thumb.width/2
                reduced.append((thumb,landmark,bounds))
            # Keep both states vertically fixed, including the original frame's foot.
            base_y=116-max(thumb.height for thumb,_,_ in reduced)
            target_landmark=32+reduced[0][1]-reduced[0][0].width/2
            for state,(thumb,landmark,bounds) in zip(["closed","open"],reduced):
                name=f"{kind}_{direction}_{state}"
                canvas=Image.new("RGBA",(64,128),(0,0,0,0));x=round(target_landmark-landmark)
                assert x>=0 and x+thumb.width<=64,(name,x,thumb.width)
                canvas.alpha_composite(thumb,(x,base_y));frames[name]=canvas;door_names.append(name)
                info.append({"id":name,"source":"door_states_reference_matched.png","source_bounds":bounds,"scale":scale,"pair_landmark":"top_lintel_peak","offset":[x,base_y]})
    references=[Image.open(ROOT/"art/received/furniture"/kind/"rotation_0.png").convert("RGBA") for kind in ["door","production_door","warehouse_door"]]
    door_palette=palette_for([frames[name] for name in door_names],references)
    for name in door_names:frames[name]=quantize(frames[name],door_palette)
    for record in info:
        name=record["id"];frame=frames[name];path=OUTPUT/(name+".png");frame.save(path)
        colors={pixel[:3] for pixel in frame.getdata() if pixel[3]==255};alphas=set(frame.getchannel("A").getdata())
        assert frame.size==(64,128) and alphas<= {0,255} and len(colors)<=32 and frame.getbbox()
        record.update({"file":name+".png","size":[64,128],"anchor":[32,104],"opaque_colors":len(colors),"alpha_values":sorted(alphas),"bounds":frame.getbbox(),"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"status":"native_pixel_candidate_geometry_unverified"})
    # Atlas export copies pixels without further scaling.
    for group,ids,columns in [("walls",names,4),("windows",window_names,4),("doors",door_names,8)]:
        atlas=Image.new("RGBA",(columns*64,((len(ids)+columns-1)//columns)*128),(0,0,0,0))
        for index,name in enumerate(ids):atlas.paste(frames[name],(index%columns*64,index//columns*128))
        atlas.save(OUTPUT/(group+"_atlas.png"))
    manifest={"alpha_threshold":THRESHOLD,"max_opaque_colors":32,"resample":"NEAREST","canvas":[64,128],"declared_anchor":[32,104],"runtime_imported":False,"geometry_verified":False,"frames":info}
    (OUTPUT/"frames.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    ids=names+window_names+door_names
    sheet=Image.new("RGBA",(8*92,6*160+48),(54,42,33,255));draw=ImageDraw.Draw(sheet)
    draw.text((12,8),"게임용 픽셀 후보 · 64×128 / 32색 / 원본 보존",font=font(16),fill="white")
    for index,name in enumerate(ids):
        x=index%8*92;y=index//8*160+40
        draw.line((x+8,y+104,x+72,y+104),fill=(91,78,62),width=1)
        sheet.alpha_composite(frames[name],(x+14,y))
        draw.text((x+2,y+128),name.replace("reference_",""),font=font(9),fill=(232,214,180))
    sheet.save(OUTPUT/"전체_픽셀_시트.png")
    compare=Image.new("RGBA",(720,600),(54,42,33,255));draw=ImageDraw.Draw(compare)
    draw.text((16,12),"기존 그림과 동일한 64×128 캔버스 · 표시 2배 최근접",font=font(18),fill="white")
    examples=[("기존 문",references[0]),("새 닫힘",frames["entrance_0_closed"]),("새 열림",frames["entrance_0_open"]),("기존 진열대",Image.open(ROOT/"art/received/furniture/shelf_1x1/rotation_0.png").convert("RGBA")),("높은 벽",frames["wall_full_0"]),("유리창",frames["window_0"])]
    for index,(label,image) in enumerate(examples):
        x=30+index%3*230;y=65+index//3*265
        draw.text((x,y-24),label,font=font(16),fill=(255,236,190))
        draw.line((x,y+208,x+128,y+208),fill=(116,95,71),width=1)
        compare.alpha_composite(image.resize((128,256),Image.Resampling.NEAREST),(x,y))
    compare.save(OUTPUT/"기존_그림_크기_비교.png")
    print("PIXEL_SHELL_CANDIDATES frames=48 failures=0; original images unchanged; runtime geometry not yet verified")

if __name__=="__main__":run()
