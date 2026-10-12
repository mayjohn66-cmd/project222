"""Shared nature palette, uniform resizing and shape-only normals. Default verifies; --install writes."""
from pathlib import Path
from io import BytesIO
import argparse, hashlib, json, math, shutil
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'docs/그림_작업/받은그림/자연물_통일'
PALETTE = [
    (31,61,39),(42,80,44),(53,99,48),(67,120,54),(87,142,61),(111,162,69),(141,184,81),(174,203,102),(199,216,124),
    (62,35,31),(86,45,34),(112,58,38),(138,73,42),(162,92,49),(183,113,63),(203,139,82),(220,165,105),(237,194,139),
    (48,48,55),(68,69,77),(91,92,102),(116,119,127),(143,146,151),(173,175,174),(202,201,188),(229,224,205),
    (95,43,59),(133,59,82),(169,77,110),(200,105,140),(226,140,167),(240,178,190),
    (96,35,35),(134,45,38),(169,56,39),(198,76,47),(222,106,66),
    (142,120,47),(169,146,59),(197,172,76),(219,195,103),(238,218,145),
    (102,90,69),(140,127,101),(178,162,126),(211,195,157),(237,224,186)
]
SPECS = {
    'iso_tree_round':(96,128,86,106,120), 'tree_pine':(96,128,78,110,120),
    'tree_dead':(96,128,90,104,120), 'tree_birch':(96,128,78,110,120),
    'tree_big_oak':(128,128,108,112,120), 'tree_apple':(96,128,90,108,120),
    'tree_cherry':(96,128,92,108,120), 'tree_poplar':(96,128,60,112,120),
    'tree_willow':(96,128,92,110,120), 'bush':(64,64,50,40,56),
    'flower_bush':(64,64,44,34,56), 'rocks':(64,64,50,40,56),
    'mushroom':(64,64,46,45,56), 'iso_stump':(64,64,50,42,56),
    'iso_log':(64,64,48,30,56)
}
VARIANTS = {'round':'iso_tree_round','birch':'tree_birch','big_oak':'tree_big_oak',
            'cherry':'tree_cherry','poplar':'tree_poplar','willow':'tree_willow'}
FALL = {'orange':('ffffff',[10,11,12,13,14,15,16,39,41]),
        'red':('ff9a84',[9,32,33,34,35,36,16,17,41]),
        'gold':('ffe48a',[10,11,37,38,39,40,41,41,46]),
        'amber':('ffc070',[9,10,11,12,13,14,15,16,17])}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def packed(image):
    stream=BytesIO(); image.save(stream,format='PNG'); return stream.getvalue()

def palette_image():
    image=Image.new('P',(1,1)); values=PALETTE+[PALETTE[-1]]*(256-len(PALETTE))
    image.putpalette([v for colour in values for v in colour]); return image

def prepare_base(name):
    source=DOC/'생성원본'/(name+'.png'); image=Image.open(source).convert('RGBA')
    alpha=image.getchannel('A').point(lambda a:255 if a>=128 else 0); image.putalpha(alpha)
    bounds=alpha.getbbox(); assert bounds, name
    body=image.crop(bounds); cw,ch,mw,mh,end=SPECS[name]
    factor=min(mw/body.width,mh/body.height)
    size=(round(body.width*factor),round(body.height*factor))
    body=body.resize(size,Image.Resampling.NEAREST); alpha=body.getchannel('A')
    body=body.convert('RGB').quantize(palette=palette_image(),dither=Image.Dither.NONE).convert('RGBA')
    body.putalpha(alpha)
    selected=Image.new('RGBA',(cw,ch)); selected.alpha_composite(body,((cw-size[0])//2,end-size[1]))
    selected_bounds=selected.getbbox()
    return selected,dict(source=source.relative_to(ROOT).as_posix(),source_sha256=sha(source),
        source_bounds=list(bounds),uniform_scale=factor,body_size=list(size),anchor=[(selected_bounds[0]+selected_bounds[2])/2,selected_bounds[3]],
        canvas=[cw,ch],filter='NEAREST',palette_limit=len(PALETTE),alpha_threshold=128)

def shape_normal(image):
    # Bevel from alpha geometry only. Colour/berries/seasonal paint never act as height.
    alpha=image.getchannel('A'); height=alpha.filter(ImageFilter.GaussianBlur(3.0))
    out=Image.new('RGB',image.size,(128,128,255)); hp=height.load(); ap=alpha.load(); np=out.load()
    w,h=image.size
    for y in range(h):
        for x in range(w):
            if not ap[x,y]: continue
            dx=(hp[min(w-1,x+1),y]-hp[max(0,x-1),y])/255.0
            dy=(hp[x,min(h-1,y+1)]-hp[x,max(0,y-1)])/255.0
            nx,ny=-dx*1.8,dy*1.8; length=math.sqrt(nx*nx+ny*ny+1)
            np[x,y]=tuple(round((v/length*.5+.5)*255) for v in (nx,ny,1))
    return out

def autumn(image,variant,colour):
    out=image.copy(); greens={p:i for i,p in enumerate(PALETTE[:9])}
    blossom={p:i for i,p in enumerate(PALETTE[26:32])}
    replacements=FALL[colour][1]
    def recolour(p):
        if p[3] and p[:3] in greens: return (*PALETTE[replacements[greens[p[:3]]]],p[3])
        if p[3] and variant=='cherry' and p[:3] in blossom:
            return (*PALETTE[replacements[min(8,blossom[p[:3]]+2)]],p[3])
        return p
    out.putdata([recolour(p) for p in image.get_flattened_data()]); return out

def berry_ready(empty):
    out=empty.copy(); draw=ImageDraw.Draw(out); bounds=out.getbbox(); placed=[]
    # Five fixed clusters inside existing foliage; no change to shrub outline or size.
    for fx,fy in [(.22,.42),(.65,.28),(.78,.57),(.42,.66),(.30,.76)]:
        x=round(bounds[0]+(bounds[2]-bounds[0])*fx); y=round(bounds[1]+(bounds[3]-bounds[1])*fy)
        points=[(x,y-1),(x-1,y),(x,y),(x+1,y),(x,y+1)]
        if not all(out.getpixel(p)[3] for p in points): continue
        for p in points: draw.point(p,fill=(*PALETTE[33],255))
        draw.point((x,y),fill=(*PALETTE[35],255)); draw.point((x,y-1),fill=(*PALETTE[36],255)); placed.append([x,y])
    assert len(placed)>=4,placed
    return out,placed

def build():
    images,records={},{}
    for name in SPECS:
        image,record=prepare_base(name); path=ROOT/'art/received/nature'/(name+'.png')
        images[path]=image; records[name]=record|dict(path='res://'+path.relative_to(ROOT).as_posix())
    states={}
    for variant,name in VARIANTS.items():
        base=images[ROOT/'art/received/nature'/(name+'.png')]
        for colour,(tint,_) in FALL.items():
            key='autumn_'+(variant+'_' if variant!='round' else '')+colour
            file='tree_'+key if variant!='round' else 'tree_autumn_'+colour
            image=autumn(base,variant,colour); path=ROOT/'art/received/nature_states'/(file+'.png'); images[path]=image
            states[key]=dict(path='res://'+path.relative_to(ROOT).as_posix(),anchor=records[name]['anchor'],
                normal_source=records[name]['path'],leaf_tint=tint,base_variant=variant,
                reference_sha256=hashlib.sha256(packed(base)).hexdigest(),changed_leaf_pixels=sum(a!=b for a,b in zip(base.get_flattened_data(),image.get_flattened_data())))
    bush=images[ROOT/'art/received/nature/bush.png']; ready,points=berry_ready(bush)
    for key,image in [('berry_empty',bush),('berry_ready',ready)]:
        path=ROOT/'art/received/nature_states'/(key+'.png'); images[path]=image
        states[key]=dict(path='res://'+path.relative_to(ROOT).as_posix(),anchor=records['bush']['anchor'],
            normal_source=records['bush']['path'],reference_sha256=hashlib.sha256(packed(bush)).hexdigest())
    images[ROOT/'art/received/village/village_flower_bush.png']=images[ROOT/'art/received/nature/flower_bush.png']
    normals={p.with_name(p.stem+'_n.png'):shape_normal(im) for p,im in images.items() if '/nature_states/' not in p.as_posix()}
    return images,normals,records,states,points

def preview(images,old=False):
    sheet=Image.new('RGB',(1344,1560),(48,43,38)); draw=ImageDraw.Draw(sheet)
    for i,name in enumerate(SPECS):
        path=ROOT/'art/received/nature'/(name+'.png')
        im=Image.open(DOC/'변경전'/'nature'/(name+'.png')).convert('RGBA') if old else images[path]
        im=im.crop(im.getbbox()); zoom=3
        im=im.resize((im.width*zoom,im.height*zoom),Image.Resampling.NEAREST)
        x=i%4*336;y=i//4*390;sheet.paste(im,(x+(336-im.width)//2,y+370-im.height),im);draw.text((x+8,y+8),name,fill='white')
    return sheet

def install(images,normals,records,states,points):
    (DOC/'선택본').mkdir(parents=True,exist_ok=True)
    for path in images:
        historical = path.parent.name != 'nature_states' or path.stem in ['berry_empty','berry_ready','tree_autumn_orange','tree_autumn_red','tree_autumn_gold','tree_autumn_amber']
        if path.exists() and historical:
            backup=DOC/'변경전'/path.parent.name/path.name;backup.parent.mkdir(parents=True,exist_ok=True)
            if not backup.exists(): shutil.copy2(path,backup)
    for path,image in (images|normals).items():
        path.parent.mkdir(parents=True,exist_ok=True);image.save(path)
        copy=DOC/'선택본'/path.parent.name/path.name;copy.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,copy)
    for key,row in states.items():
        path=ROOT/row['path'].removeprefix('res://');row.update(sha256=sha(path),source=(DOC/'선택본'/path.parent.name/path.name).relative_to(ROOT).as_posix())
    (ROOT/'data/art/nature_state_assets.json').write_text(json.dumps(states,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    # Refresh every live manifest that reuses a changed PNG, including gathering scenery.
    for name in ['received_assets','expedition_sprite_assets','expedition_environment_assets','village_sprite_assets']:
        path=ROOT/'data/art'/(name+'.json');data=json.loads(path.read_text(encoding='utf8'))
        for row in data['assets']:
            target=ROOT/row['path'].removeprefix('res://')
            if target not in images: continue
            image=images[target]; old_anchor=row.get('anchor',[0,0]); bounds=image.getbbox()
            anchor=[(bounds[0]+bounds[2])/2,bounds[3]]
            if row.get('footprint'):
                row['footprint']=[[round(x-old_anchor[0]+anchor[0],4),round(y-old_anchor[1]+anchor[1],4)] for x,y in row['footprint']]
            row.update(anchor=anchor,sha256=sha(target),source=(DOC/'선택본'/target.parent.name/target.name).relative_to(ROOT).as_posix(),
                       source_sha256=sha(target),colors=len({p[:3] for p in image.get_flattened_data() if p[3]}),alpha_binary=True)
            for field in ['canvas','size']:
                if field in row:row[field]=list(image.size)
            if row.get('normal_source'):
                row['normal_source']=states.get('berry_ready',{}).get('normal_source',row['normal_source']) if 'berry' in target.stem else row['path']
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    previous=json.loads((DOC/'선택_기록.json').read_text(encoding='utf8')) if (DOC/'선택_기록.json').exists() else {}
    original_assets=previous.get('original_assets') or [dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p)) for p in sorted((DOC/'변경전').rglob('*.png'))]
    summary=dict(palette=PALETTE,base_assets=records,states=states,berry_points=points,original_assets=original_assets,
        selected=[dict(path='res://'+p.relative_to(ROOT).as_posix(),sha256=sha(p),canvas=list(im.size),normal_method='alpha silhouette bevel, no luminance height' if p in normals else None) for p,im in (images|normals).items()])
    (DOC/'선택_기록.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    preview(images).save(DOC/'보정후_비교.png');preview(images,True).save(DOC/'보정전_비교.png')

def verify(images,normals):
    record=json.loads((DOC/'선택_기록.json').read_text(encoding='utf8'))
    assert len(record['original_assets'])==22
    for row in record['original_assets']: assert sha(ROOT/row['path'])==row['sha256'],'Historical source changed'
    for row in record['base_assets'].values(): assert sha(ROOT/row['source'])==row['source_sha256'],'Generated source changed'
    for path,image in (images|normals).items():
        assert path.exists() and path.read_bytes()==packed(image),'Reproduction mismatch: '+str(path)
        if path in images:
            assert set(image.getchannel('A').get_flattened_data())<={0,255}
            assert {p[:3] for p in image.get_flattened_data() if p[3]}<=set(PALETTE)
    original=Image.open(DOC/'변경전/nature/tree_dead.png');new=images[ROOT/'art/received/nature/tree_dead.png']
    assert new.getbbox()[3]-new.getbbox()[1]>=100
    assert new.getbbox()[3]-new.getbbox()[1]>2*(original.getbbox()[3]-original.getbbox()[1])
    print(f'PASS: {len(images)} diffuse images, {len(normals)} shape normals, shared {len(PALETTE)}-colour palette; originals preserved')

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--install',action='store_true');args=parser.parse_args()
    images,normals,records,states,points=build()
    if args.install: install(images,normals,records,states,points)
    verify(images,normals)

if __name__=='__main__': main()
