"""도시 생성 원본을 보존하고 균일 축소/프레임 분리한다. 기본 읽기 전용, --install 기록."""
from pathlib import Path
from collections import deque
from io import BytesIO
import argparse
import hashlib
import json
import re
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT/'docs/그림_작업/받은그림/프롤로그_도시'
GAME = ROOT/'art/received/opening_city'
CAR_DIRS = ['south_east','south_west','side_right','north_east','north_west','side_left']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def png(image):
    stream = BytesIO()
    image.save(stream,format='PNG')
    return stream.getvalue()


def subjects(image, count):
    mask = bytearray(image.getchannel('A').point(lambda a:255 if a>=200 else 0).tobytes())
    w,h = image.size
    components = []
    for start,value in enumerate(mask):
        if not value: continue
        mask[start]=0
        todo,found=deque([start]),[]
        while todo:
            at=todo.pop();found.append(at)
            x,y=at%w,at//w
            for dx,dy in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]:
                nx,ny=x+dx,y+dy
                if 0<=nx<w and 0<=ny<h:
                    other=ny*w+nx
                    if mask[other]:mask[other]=0;todo.append(other)
        if len(found)>300:components.append(found)
    selected=sorted(components,key=len,reverse=True)[:count]
    assert len(selected)==count
    output=[]
    for component in selected:
        xs,ys=[p%w for p in component],[p//w for p in component]
        box=(min(xs),min(ys),max(xs)+1,max(ys)+1)
        assert box[0]>0 and box[1]>0 and box[2]<w and box[3]<h,('native source clipped',box,(w,h))
        subject=image.crop(box)
        alpha=bytearray(subject.width*subject.height)
        for p in component:alpha[(p//w-box[1])*subject.width+p%w-box[0]]=255
        subject.putalpha(Image.frombytes('L',subject.size,bytes(alpha)))
        output.append((subject,box))
    output.sort(key=lambda pair:(pair[1][1]+pair[1][3])/2)
    if count==6:output=sorted(output[:3],key=lambda pair:pair[1][0])+sorted(output[3:],key=lambda pair:pair[1][0])
    return output


def prepare(subject, canvas, kind):
    ratio=min((canvas[0]-16)/subject.width,(canvas[1]-24)/subject.height)
    subject=subject.resize((round(subject.width*ratio),round(subject.height*ratio)),Image.Resampling.NEAREST)
    alpha=subject.getchannel('A')
    subject=subject.convert('RGB').quantize(colors=96,dither=Image.Dither.NONE).convert('RGBA')
    subject.putalpha(alpha)
    result=Image.new('RGBA',canvas)
    result.alpha_composite(subject,((canvas[0]-subject.width)//2,canvas[1]-12-subject.getbbox()[3]))
    result.putdata([(r,g,b,a) if a else (0,0,0,0) for r,g,b,a in result.get_flattened_data()])
    box=result.getbbox();width=box[2]-box[0]
    x=(box[0]+box[2])/2
    if kind=='pole':
        bottom=box[3]-max(2,round((box[3]-box[1])*.03))
        xs=[px for py in range(bottom,box[3]) for px in range(canvas[0]) if result.getpixel((px,py))[3]]
        x=sum(xs)/len(xs)+.5
    y=box[3]-width/4 if kind=='iso' else box[3]-(3 if kind=='pole' else 0)
    return result,[x,y],width,ratio


def write(path,data,install):
    if install:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    else:assert path.exists() and path.read_bytes()==data,'not reproducible:'+str(path)


def apply(install):
    inputs=json.loads((HERE/'제작_입력.json').read_text(encoding='utf-8'))
    rows=[];pictures=[]
    for entry in inputs['assets']:
        print('prepare',entry['id'],flush=True)
        native=Path(entry['generated_path']);raw=HERE/'생성_원본'/(entry['id']+'.png')
        if install and native.exists():raw.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(native,raw)
        assert sha(raw)==entry['generated_sha256']
        source=Image.open(raw).convert('RGBA')
        if entry['group']=='background':
            assert source.getchannel('A').getextrema()==(255,255)
            path=GAME/(entry['id']+'.png');write(path,raw.read_bytes(),install)
            rows.append({'id':entry['id'],'group':'background','path':'res://'+path.relative_to(ROOT).as_posix(),'sha256':sha(path),'size':list(source.size),'source':raw.relative_to(ROOT).as_posix()})
            continue
        found=subjects(source,6 if entry['group']=='vehicle' else 1)
        for index,(subject,box) in enumerate(found):
            identity=entry['id']+('_'+CAR_DIRS[index] if entry['group']=='vehicle' else '')
            side=entry['group']=='vehicle' and index in [2,5]
            kind='pole' if entry['id'] in ['streetlamp','traffic_signal','bus_stop'] else 'side' if side else 'iso'
            canvas=(256,320) if entry['group']=='building' else (80,208) if entry['id']=='streetlamp' else (80,192) if kind=='pole' else (160,112) if side or entry['id']=='planter' else (160,128)
            image,anchor,width,ratio=prepare(subject,canvas,kind)
            path=GAME/(identity+'.png');write(path,png(image),install)
            group='vehicle_side' if side else 'vehicle_iso' if entry['group']=='vehicle' else entry['group']
            rows.append({'id':identity,'group':group,'path':'res://'+path.relative_to(ROOT).as_posix(),'sha256':sha(path),'anchor':anchor,'footprint_width':width,'size':list(canvas),'source':raw.relative_to(ROOT).as_posix(),'source_sha256':sha(raw),'source_bounds':list(box),'uniform_scale':ratio})
            assert set(image.getchannel('A').get_flattened_data())<={0,255}
            assert len({p[:3] for p in image.get_flattened_data() if p[3]})<=96
            pictures.append((identity,image))
    for row in rows:
        path=ROOT/row['path'][6:];imported=Path(str(path)+'.import')
        if install and not imported.exists():
            template=(ROOT/'art/received/village/village_well_drawn.png.import').read_text(encoding='utf-8')
            template=re.sub(r'^uid=.*\n','',template,flags=re.MULTILINE)
            template=template.replace('res://art/received/village/village_well_drawn.png',row['path'])
            target='res://.godot/imported/'+path.name+'-'+hashlib.md5(row['path'].encode()).hexdigest()+'.ctex'
            template=re.sub(r'res://\.godot/imported/[^"\]]+',lambda m:target,template)
            imported.write_text(template,encoding='utf-8')
        assert 'compress/mode=0' in imported.read_text(encoding='utf-8')
    write(ROOT/'data/art/opening_city_assets.json',(json.dumps({'assets':rows},ensure_ascii=False,indent=2)+'\n').encode('utf-8'),install)
    if install:
        sheet=Image.new('RGB',(1200,((len(pictures)+5)//6)*360),(55,48,41));draw=ImageDraw.Draw(sheet)
        font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',13)
        for i,(identity,image) in enumerate(pictures):
            x,y=i%6*200,i//6*360;draw.text((x+8,y+8),identity,font=font,fill=(245,220,190))
            shown=image.copy();shown.thumbnail((190,320),Image.Resampling.NEAREST)
            sheet.paste(shown,(x+(200-shown.width)//2,y+30),shown)
        sheet.save(HERE/'게임용_전체.png')
    print('PASS native originals',len(inputs['assets']),' game PNG',len(rows),'; no axis compression;', 'install' if install else 'read-only')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--install',action='store_true');apply(parser.parse_args().install)
