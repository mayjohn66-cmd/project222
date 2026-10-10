from pathlib import Path
from collections import deque
import argparse,hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont

HERE=Path(__file__).resolve().parent

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def palette(samples,count):
    im=Image.new('RGB',(len(samples),1));im.putdata(samples)
    q=im.quantize(colors=count,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
    p=q.getpalette()
    return [tuple(p[i*3:i*3+3]) for _,i in q.getcolors()]

def closest(p,colors):return min(colors,key=lambda c:sum((a-b)**2 for a,b in zip(p,c)))

def quantize(im,colors):
    out=im.copy()
    out.putdata([(*closest(p[:3],colors),255) if p[3] else (0,0,0,0) for p in im.get_flattened_data()])
    return out

def fit(source,spec,bbox=None,size=None,position=None):
    im=source.copy();im.putalpha(im.getchannel('A').point(lambda a:255 if a>=128 else 0))
    bbox=bbox or im.getbbox();crop=im.crop(bbox)
    if size is None:
        f=min(spec['max_size'][0]/crop.width,spec['max_size'][1]/crop.height)
        size=(max(1,round(crop.width*f)),max(1,round(crop.height*f)))
    position=position or ((spec['canvas'][0]-size[0])//2,spec['bottom']-size[1])
    out=Image.new('RGBA',tuple(spec['canvas']),(0,0,0,0))
    out.paste(crop.resize(size,Image.Resampling.NEAREST),position)
    out.putdata([p if p[3] else (0,0,0,0) for p in out.get_flattened_data()])
    return out,bbox,size,position

def opening(im):
    w,h=im.size;a=im.getchannel('A');seen=set();holes=[]
    for y in range(h):
        for x in range(w):
            if a.getpixel((x,y)) or (x,y) in seen:continue
            todo=deque([(x,y)]);seen.add((x,y));part=[];border=False
            while todo:
                px,py=todo.popleft();part.append((px,py))
                border=border or px in (0,w-1) or py in (0,h-1)
                for nx,ny in [(px+1,py),(px-1,py),(px,py+1),(px,py-1)]:
                    if 0<=nx<w and 0<=ny<h and (nx,ny) not in seen and not a.getpixel((nx,ny)):
                        seen.add((nx,ny));todo.append((nx,ny))
            if not border:holes.append(part)
    assert holes,'문틀 안쪽이 외부와 연결되어 있음'
    part=max(holes,key=len);assert len(part)>=100,'문틀 구멍이 너무 작음'
    mask=Image.new('L',im.size,0)
    for p in part:mask.putpixel(p,255)
    return mask

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source-root',type=Path);args=ap.parse_args()
    specs=json.loads((HERE/'프롬프트.json').read_text(encoding='utf-8-sig'))['assets']
    raw=HERE/'생성_원본';outdir=HERE/'픽셀_정리';raw.mkdir(exist_ok=True);outdir.mkdir(exist_ok=True)
    sources={};images={};records=[];items=[]
    for s in specs:
        p=raw/(s['id']+'.png')
        if args.source_root:
            src=args.source_root/s['generated']
            if p.exists():assert sha(p)==sha(src),'원본 덮어쓰기 금지'
            else:shutil.copyfile(src,p)
        sources[s['id']]=Image.open(p).convert('RGBA')
    gate_meta=None;hole=None;gate_bars=0
    for s in specs:
        key=s['id'];source=sources[key]
        if key=='exit_closed':
            assert source.size==sources['exit_open'].size
            candidate,bbox,size,pos=fit(source,s,*gate_meta)
            im=images['exit_open'].copy()
            bars=[candidate.getpixel((x,y))[:3] for y in range(im.height) for x in range(im.width) if hole.getpixel((x,y)) and candidate.getpixel((x,y))[3]]
            assert len(bars)>=30,'쇠창살 누락'
            colors=palette(bars,8)
            for y in range(im.height):
                for x in range(im.width):
                    p=candidate.getpixel((x,y))
                    if hole.getpixel((x,y)) and p[3]:im.putpixel((x,y),(*closest(p[:3],colors),255));gate_bars+=1
        else:
            im,bbox,size,pos=fit(source,s)
            px=[p[:3] for p in im.get_flattened_data() if p[3]]
            if key=='wall_torch':
                hot=lambda p:p[0]>180 and p[1]>90 and p[2]<175
                base=palette([p for p in px if not hot(p)],24);fire=palette([p for p in px if hot(p)],8)
                im.putdata([(*closest(p[:3],fire if hot(p[:3]) else base),255) if p[3] else (0,0,0,0) for p in im.get_flattened_data()])
            else:im=quantize(im,palette(px,24 if key=='exit_open' else 32))
            if key=='exit_open':gate_meta=(bbox,size,pos);hole=opening(im)
        images[key]=im;p=outdir/(key+'.png');im.save(p,optimize=True)
        colors=len(set(p[:3] for p in im.get_flattened_data() if p[3]));assert colors<=32
        records.append(dict(id=key,source_size=list(source.size),crop=list(bbox),scaled_size=list(size),position=list(pos),canvas=s['canvas'],anchor=s['anchor'],alpha=[0,255],colors=colors,source_sha256=sha(raw/(key+'.png')),sha256=sha(p)))
        items.append(dict(id=key,state=s['state'],selector=s['selector'],canvas=s['canvas'],anchor=s['anchor'],sprite='픽셀_정리/'+key+'.png',source='생성_원본/'+key+'.png',sha256=sha(p)))
    left=images['exit_open'];right=images['exit_closed'];changed=[]
    for y in range(left.height):
        for x in range(left.width):
            if left.getpixel((x,y))!=right.getpixel((x,y)):
                assert hole.getpixel((x,y));changed.append((x,y))
    assert len(changed)==gate_bars
    hole.save(HERE/'출구_변경_마스크.png')
    for name,data in [('검사_결과.json',dict(method='uniform_nearest_binary_alpha128_shared_gate_frame',checks=records,gate=dict(opening_pixels=sum(1 for p in hole.get_flattened_data() if p),changed_pixels=gate_bars,frame_pixels_identical=True,change_mask='출구_변경_마스크.png'))),('후보_목록.json',dict(status='candidate_not_installed',tool='built-in image_gen',runtime_applied=False,view='south-west',subjects=3,frames=4,anchors_provisional=True,assets=items))]:
        (HERE/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    sheet=Image.new('RGB',(1120,620),(47,40,33));d=ImageDraw.Draw(sheet)
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',18);small=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',12)
    for i,s in enumerate(specs):
        x=i*280;d.text((x+14,10),s['name'],font=font,fill=(241,218,172))
        im=images[s['id']].resize((s['canvas'][0]*4,s['canvas'][1]*4),Image.Resampling.NEAREST)
        sheet.paste(im,(x+12,42+(128-s['canvas'][1])*4),im)
        d.text((x+14,562),f"{s['canvas'][0]} × {s['canvas'][1]} · 4배 확대 · 후보",font=small,fill=(221,206,178))
        d.text((x+14,584),s['id'],font=small,fill=(184,174,150))
    sheet.save(HERE/'환경_소품_비교.png')
    print(json.dumps(dict(checks=records,gate_changed_pixels=gate_bars),ensure_ascii=False,indent=2))

if __name__=='__main__':main()
