"""Build the user-authorized priority-2 pixel candidates with Pillow.
Original runtime art and CSV data stay untouched. Outputs are NOT runtime-connected.
Run from repo root: python -X utf8 docs/그림_작업/받은그림/진열대_상태/build_pack.py
Existing outputs are protected from overwrite.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops
import csv, hashlib, json, math, sys, subprocess
BASE=Path(__file__).resolve().parent
ROOT=BASE.parents[3]
OUT=BASE/"픽셀_정리"
THRESHOLD=160
STEP=56
SAMPLES=["raw_water","forest_herb","iron_ore","bread","water","herb_drink"]

def read_csv(path):
    with (ROOT/path).open(encoding="utf-8-sig",newline="") as f:
        return list(csv.DictReader(f))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save_json(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def alpha_clean(image):
    image=image.convert("RGBA")
    image.putalpha(image.getchannel("A").point(lambda a:255 if a>=THRESHOLD else 0))
    result=Image.new("RGBA",image.size)
    result.paste(image,(0,0),image.getchannel("A"))
    return result

def pieces(path,cols,rows):
    image=alpha_clean(Image.open(path))
    width,height=image.size;raw=image.getchannel("A").tobytes()
    parent=[];runs=[];previous=[]
    def find(x):
        while parent[x]!=x:parent[x]=parent[parent[x]];x=parent[x]
        return x
    for y in range(height):
        row=raw[y*width:(y+1)*width];current=[];position=0
        while position<width:
            start=row.find(b"\xff",position)
            if start<0:break
            end=row.find(b"\x00",start)
            if end<0:end=width
            idx=len(parent);parent.append(idx);runs.append((start,end,y));current.append(idx)
            for other in previous:
                l,r,_=runs[other]
                if l<=end and r>=start:
                    a,b=find(idx),find(other)
                    if a!=b:parent[a]=b
            position=end
        previous=current
    stats={}
    for idx,(l,r,y) in enumerate(runs):
        key=find(idx)
        v=stats.setdefault(key,[0,l,y,r,y+1])
        v[0]+=r-l;v[1]=min(v[1],l);v[2]=min(v[2],y);v[3]=max(v[3],r);v[4]=max(v[4],y+1)
    found=[v for v in stats.values() if v[0]>1500]
    assert len(found)==cols*rows,(path,len(found))
    found.sort(key=lambda v:(v[2]+v[4])/2)
    ordered=[]
    for row in range(rows):ordered.extend(sorted(found[row*cols:(row+1)*cols],key=lambda v:v[1]))
    return [(image.crop(v[1:]),v[1:]) for v in ordered]

def palette(images):
    images=list(images)
    sample=Image.new("RGB",(len(images)*128,128))
    for idx,im in enumerate(images):sample.paste(im,(idx*128,0),im.getchannel("A"))
    return sample.quantize(colors=32,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)

def reduce_colors(image,pal):
    result=image.convert("RGB").quantize(palette=pal,dither=Image.Dither.NONE).convert("RGBA")
    result.putalpha(image.getchannel("A"))
    return alpha_clean(result)

def native(source,size,max_w,max_h,bottom):
    scale=min(max_w/source.width,max_h/source.height)
    frame=source.resize((round(source.width*scale),round(source.height*scale)),Image.Resampling.NEAREST)
    result=Image.new("RGBA",size)
    result.alpha_composite(frame,((size[0]-frame.width)//2,bottom-frame.height))
    return result,scale

def font(size):
    return ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",size)

def run():
    if (OUT/"frames.json").exists():
        tracked=subprocess.check_output(["git","ls-files","--",str(BASE.relative_to(ROOT))],cwd=ROOT)
        assert "--rebuild-draft" in sys.argv and not tracked.strip(),"Committed/selected candidates must not be overwritten."

    OUT.mkdir(exist_ok=True)
    for folder in ["units","bodies","goods","examples","layers","review"]:(OUT/folder).mkdir(exist_ok=True)
    records=[];manifest=[]
    def emit(relative,image,kind,limit=32):
        path=OUT/relative;image.save(path)
        pixels=list(image.getdata());alphas=set(image.getchannel("A").getdata())
        colors=len({p[:3] for p in pixels if p[3]})
        assert image.mode=="RGBA" and alphas<={0,255} and colors<=limit and image.getbbox(),relative
        assert all(p[:3]==(0,0,0) for p in pixels if not p[3]),relative
        records.append({"file":relative,"kind":kind,"size":list(image.size),"bounds":image.getbbox(),
                        "opaque_colors":colors,"palette_limit":limit,"sha256":sha(path)})
        return relative
    raw=pieces(BASE/"shelf_empty_source.png",4,4)
    units={};unit_info=[]
    for row,grade in enumerate(["salvaged","wood","reinforced","modern"]):
        reduced=[]
        for d in range(4):
            image,bounds=raw[row*4+d]
            frame,scale=native(image,(64,128),55,78,118)
            reduced.append(frame)
            unit_info.append({"grade":grade,"view":d,"source_bounds":bounds,"scale":scale})
        pal=palette(reduced)
        for d,frame in enumerate(reduced):
            frame=reduce_colors(frame,pal);units[grade,d]=frame
            emit(f"units/{grade}_{d}.png",frame,"empty_shelf_unit")
    merchandise=[r for r in read_csv("data/core/items.csv") if r["shelf_allowed"]=="true"]
    def icon_source(row):
        if row["icon_path"]:
            return row["icon_path"].removeprefix("res://")
        candidate=f"docs/그림_작업/받은그림/아이템/{row['id']}/{row['id']}_64.png"
        assert (ROOT/candidate).is_file(),row["id"]
        return candidate
    raw_goods={}
    for row in merchandise:
        path=icon_source(row)
        if path in raw_goods:continue
        image=alpha_clean(Image.open(ROOT/path))
        assert image.getbbox(),path
        image=image.crop(image.getbbox());scale=min(12/image.width,12/image.height)
        small=image.resize((max(1,round(image.width*scale)),max(1,round(image.height*scale))),Image.Resampling.NEAREST)
        canvas=Image.new("RGBA",(16,16));canvas.alpha_composite(small,((16-small.width)//2,14-small.height))
        raw_goods[path]=canvas
    goods_pal=palette(raw_goods.values());goods={};item_map=[]
    names={}
    for path,im in raw_goods.items():
        name=Path(path).stem
        assert name not in names,name
        names[name]=path;im=reduce_colors(im,goods_pal);goods[path]=im
        emit("goods/"+name+".png",im,"merchandise_glyph")
    for row in merchandise:
        path=icon_source(row)
        item_map.append({"item_id":row["id"],"name":row["name"],"glyph":"goods/"+Path(path).stem+".png",
                         "source":path,"source_sha256":sha(ROOT/path),"runtime_icon_connected":bool(row["icon_path"]),"anchor":[8,14]})
    by_id={row["item_id"]:goods[row["source"]] for row in item_map}
    config=read_csv("data/shop/catalogs/furniture/shelf_data.csv")
    builds={r["id"]:r for r in read_csv("data/shop/catalogs/furniture/build_objects.csv")}
    cases={}
    def layers(body,anchors,spl,capacity,rack=False,view=0):
        outputs={}
        for state in ["sparse","full"]:
            layer=Image.new("RGBA",body.size);stocks=[]
            for j,(x,y,seg_width) in enumerate(anchors):
                count=min(6 if rack else 5,capacity) if state=="full" else (1 if j%2==0 else 0)
                item_id=SAMPLES[j%len(SAMPLES)];stocks.append({"item_id":item_id,"stock":count})
                if count==0:continue
                glyph=by_id[item_id].crop(by_id[item_id].getbbox())
                budget=max(4,int(seg_width/count)-1)
                scale=min(1,budget/glyph.width)
                glyph=glyph.resize((max(1,round(glyph.width*scale)),max(1,round(glyph.height*scale))),Image.Resampling.NEAREST)
                for n in range(count):
                    nx=x+(n-(count-1)/2)*(min(budget+1,seg_width/max(1,count)))
                    ny=y+(nx-x)*(0.5 if view==0 else -0.5)
                    px,py=round(nx-glyph.width/2),round(ny-glyph.height)
                    assert px>=0 and py>=0 and px+glyph.width<=body.width and py+glyph.height<=body.height
                    layer.alpha_composite(glyph,(px,py))
            if not rack:
                layer.putalpha(ImageChops.multiply(layer.getchannel("A"),body.getchannel("A")))
                layer=alpha_clean(layer)
            composite=body.copy();composite.alpha_composite(layer)
            outputs[state]=(layer,composite,stocks)
        return outputs
    for row in config:
        build_id=row["id"];span=int(builds[build_id]["grid_w"]);spl=int(row["slots_per_level"])
        max_stack=int(row["max_stack_level"]);capacity=int(row["slot_capacity"])
        grade=("wood" if build_id.startswith("wood_") else "reinforced" if build_id.startswith("reinforced_")
               else "modern" if build_id.startswith("modern_") else "salvaged")
        for stack in range(1,max_stack+1):
            width=span*64;height=128+64*(stack-1)+(64 if span==3 else 0)
            anchor=[width//2,height-(40 if span==3 else 24)]
            for d in range(4):
                body=Image.new("RGBA",(width,height));unit=units[grade,d];placements=[]
                for level in reversed(range(stack)):
                    for i in range(span):
                        offset=(i-(span-1)/2)
                        x=round(width/2-32+(32 if d in [0,2] else -32)*offset)
                        y=round(anchor[1]-104+16*offset-level*STEP)
                        assert x>=0 and x+64<=width
                        # Transparent canvas beyond the frame can exceed the output; opaque pixels must fit.
                        b=unit.getbbox();assert 0<=x+b[0] and x+b[2]<=width and 0<=y+b[1] and y+b[3]<=height
                        body.alpha_composite(unit,(x,y));placements.append({"level":level,"unit":i,"offset":[x,y]})
                key=f"{build_id}_{d}_stack{stack}"
                filename=emit("bodies/"+key+".png",body,"empty_shelf_body")
                anchors=[]
                per_board=math.ceil(spl/2);l,t,r,b=unit.getbbox()
                a=l+4 if d==0 else l+14
                z=r-14 if d==0 else r-4
                face=max(16,z-a)
                if d<2:
                    for level in range(stack):
                        for j in range(spl):
                            u=(j//2+0.5)/per_board*span
                            i=min(span-1,int(u));fraction=u-i
                            offset=i-(span-1)/2
                            xx=width/2-32+(32 if d==0 else -32)*offset
                            yy=anchor[1]-104+16*offset-level*STEP
                            local_x=a+face*fraction if d==0 else z-face*fraction
                            local_y=b-7-face/2+face*fraction/2-(24 if j%2 else 0)
                            anchors.append([round(xx+local_x),round(yy+local_y),face*span/per_board])
                record={"build_id":build_id,"view":d,"candidate_rotation_mapping":None,"stack":stack,"grade":grade,
                        "body":filename,"canvas":[width,height],"anchor":anchor,"slots_per_level":spl,
                        "slot_capacity":capacity,"max_stack_level":max_stack,"slot_anchors":anchors,
                        "unit_placements":placements,"visible_front":d<2,"geometry_verified":False}
                state_images={"empty":body}
                if d<2:
                    for state,(layer,composite,stocks) in layers(body,anchors,spl,capacity,view=d).items():
                        record[state]={"goods_layer":emit("layers/"+key+"_"+state+".png",layer,"sample_goods_layer"),
                                       "example":emit("examples/"+key+"_"+state+".png",composite,"sample_composite",64),
                                       "sample_stock":stocks}
                        state_images[state]=composite
                else:
                    # Rear backing hides the products; do not invent rear stock visibility.
                    record["sparse"]=record["full"]={"example":filename,"goods_layer":None}
                    state_images["sparse"]=state_images["full"]=body
                manifest.append(record);cases[build_id,d,stack]=state_images
    rack_raw=pieces(BASE/"rack_empty_source.png",4,3)
    rack_cases={}
    def add_rack_plane(image,view):
        # Duplicate one board band along its isometric slope, keeping the feet fixed.
        # The original upper board becomes a cap; three lower load planes remain.
        output=Image.new("RGBA",image.size)
        for x in range(image.width):
            cut=round(66+(x-64)*(0.5 if view in [0,2] else -0.5))
            for y in range(image.height):
                if y<cut-22:source_y=y+22
                elif y<cut:source_y=y+22
                else:source_y=y
                if 0<=source_y<image.height:output.putpixel((x,y),image.getpixel((x,source_y)))
        return output
    for row,build_id in enumerate(["warehouse_rack","wood_warehouse_rack","steel_warehouse_rack"]):
        native_frames=[];original_rack_bounds={}
        for d in range(4):
            frame,_=native(rack_raw[row*4+d][0],(128,128),91,100,126);original_rack_bounds[d]=frame.getbbox();native_frames.append(add_rack_plane(frame,d))
        pal=palette(native_frames)
        for d,im in enumerate(native_frames):
            im=reduce_colors(im,pal);key=f"{build_id}_{d}"
            file=emit("bodies/"+key+".png",im,"empty_warehouse_body")
            record={"build_id":build_id,"view":d,"body":file,"canvas":[128,128],"anchor":[64,104],
                    "storage_visible_types":3,"board_planes":4,"visible_front":d<2,"geometry_verified":False}
            states={"empty":im}
            if d<2:
                # Lower to upper, matching existing rack's first-seen distinct item order.
                left,top,right,bottom=original_rack_bounds[d]
                anchors=[[64,round(top+(bottom-top)*factor),58] for factor in [0.75,0.5,0.25]]
                record["slot_anchors"]=anchors
                for state,(layer,composite,stocks) in layers(im,anchors,3,6,True,view=d).items():
                    record[state]={"goods_layer":emit("layers/"+key+"_"+state+".png",layer,"sample_goods_layer"),
                                   "example":emit("examples/"+key+"_"+state+".png",composite,"sample_composite",64),
                                   "sample_stock":stocks}
                    states[state]=composite
            else:
                record["sparse"]=record["full"]={"example":file,"goods_layer":None}
                states["sparse"]=states["full"]=im
            manifest.append(record);rack_cases[build_id,d]=states
    def review(file,title,cells,columns,cell_w,cell_h,scale=1):
        sheet=Image.new("RGBA",(columns*cell_w,48+math.ceil(len(cells)/columns)*cell_h),(54,42,33,255))
        draw=ImageDraw.Draw(sheet);draw.text((12,10),title,font=font(18),fill="white")
        for index,(label,im) in enumerate(cells):
            x=index%columns*cell_w;y=48+index//columns*cell_h
            draw.text((x+8,y+3),label,font=font(13),fill=(242,220,182))
            show=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
            sheet.alpha_composite(show,(x+(cell_w-show.width)//2,y+28))
        sheet.save(OUT/"review"/file)
    review("재질과_재고.png","빈 틀 + 별도 상품 레이어 · 상품은 비교용 예시",[
        (label+" · "+state,cases[key,0,1][state])
        for key,label in [("shelf_1x1","간이"),("wood_shelf_1x1","나무"),("reinforced_shelf_2x1","철제"),("modern_shelf_1x1","현대")]
        for state in ["empty","sparse","full"]],3,288,292,2)
    review("크기와_쌓기.png","현재 데이터 기준 · 한 칸/두 칸/세 칸 · 최대 쌓기",[
        (key+" · "+state,cases[key,0,int(row["max_stack_level"])][state])
        for row in config for key in [row["id"]] for state in ["empty","full"]],3,240,380)
    review("창고_상태.png","창고 선반 · 비어 있음 / 일부 입고 / 입고 예시",[
        (label+" · "+state,rack_cases[key,0][state])
        for key,label in [("warehouse_rack","기존"),("wood_warehouse_rack","나무"),("steel_warehouse_rack","철제")]
        for state in ["empty","sparse","full"]],3,288,292,2)
    review("네_방향.png","앞면과 뒷면 후보 · 회전 대응은 실제 지도에서 확인",[
        (grade+" "+str(d),units[grade,d]) for grade in ["salvaged","wood","reinforced","modern"] for d in range(4)],4,144,284,2)
    review("상품_글리프.png","기존 아이콘을 줄인 상품 그림 · 상품 종류별 매핑 별도",[
        (name,goods[path]) for name,path in names.items()],8,112,90,3)
    save_json(OUT/"frames.json",{"runtime_imported":False,"geometry_verified":False,"tile":[64,32],
        "max_visible_goods":5,"warehouse_max_visible_goods":6,"stack_step_pixels":STEP,"units":unit_info,"frames":manifest,"files":records})
    save_json(OUT/"items.json",{"shelf_allowed_items":len(item_map),"unique_glyphs":len(names),"items":item_map})
    save_json(BASE/"manifest.json",{"date":"2026-10-10","tool":"built-in image_gen + user-authorized Pillow processing",
        "status":"pixel_candidates_not_runtime_connected","source_assets":[{"file":p.name,"sha256":sha(p),"size":list(Image.open(p).size)} for p in [BASE/"shelf_empty_source.png",BASE/"rack_empty_source.png"]],
        "catalogs":[{"path":p,"sha256":sha(ROOT/p),"normalized_sha256":hashlib.sha256((ROOT/p).read_bytes().replace(b"\r\n",b"\n")).hexdigest()} for p in ["data/core/items.csv","data/shop/catalogs/furniture/shelf_data.csv","data/shop/catalogs/furniture/build_objects.csv"]],
        "counts":{"shelf_bodies":84,"warehouse_bodies":12,"empty_units":16,"glyphs":len(names),"mapped_items":len(item_map),"native_pngs":len(records),"runtime_icon_items":sum(r["runtime_icon_connected"] for r in item_map),"received_fish_candidate_items":sum(not r["runtime_icon_connected"] for r in item_map)},
        "references":[{"path":p,"sha256":sha(ROOT/p)} for p in [*[f"art/received/furniture/shelf_1x1/rotation_{d}.png" for d in range(4)],*[f"art/received/furniture/{name}/rotation_0.png" for name in ["warehouse_rack","wood_warehouse_rack","steel_warehouse_rack"]]]],
        "authorization":"User requested priority 2 continuation after approving Codex image generation and Python pixel processing. General Claude/Pixel Lab policy remains unchanged.",
        "warehouse_plane_edit":"Middle shelf band duplicated along its isometric slope; feet fixed; cap plus 3 load planes; geometry unverified.",
        "remaining":["user selection","runtime 2D adapter","rotation matching","modular seam and stacking overlap calibration","goods plane positions and front edge occlusion","warehouse rear braces and three distinct items in runtime"]})
    print(f"SHELF_PACK shelf_bodies=84 warehouse_bodies=12 mapped_items={len(item_map)} glyphs={len(names)} native_pngs={len(records)} failures=0")

if __name__=="__main__":run()
