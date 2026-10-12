from pathlib import Path
import json,hashlib,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'docs/그림_작업/받은그림/환경_정지_전환/렌더_원본'
DOC=ROOT/'docs/그림_작업/받은그림/환경_정지_전환'
(DOC/'렌더_원본').mkdir(parents=True,exist_ok=True)
manifest=json.loads((SOURCE/'render_manifest.json').read_text(encoding='utf-8'))
font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',14)
sheet=Image.new('RGB',(1024,((len(manifest['assets'])+4)//5)*210),(51,45,39));draw=ImageDraw.Draw(sheet)
for i,r in enumerate(manifest['assets']):
    source=SOURCE/(r['id']+'.png')
    image=Image.open(source).convert('RGBA')
    alpha=image.getchannel('A');binary=alpha.point(lambda a:255 if a>=128 else 0)
    image.putalpha(binary)
    colors=len({p for p in image.get_flattened_data() if p[3]})
    if colors>96:
        image=image.convert('RGB').quantize(colors=96,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).convert('RGBA')
        image.putalpha(binary)
    r['source']='res://'+(DOC/'렌더_원본'/source.name).relative_to(ROOT).as_posix()
    r['source_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
    group='village' if r['id'].startswith(('village_well','low_wall')) else 'expedition/background'
    target=ROOT/'art/received'/group/(r['id']+'.png');target.parent.mkdir(parents=True,exist_ok=True)
    image.save(target)
    r['path']='res://'+target.relative_to(ROOT).as_posix();r['sha256']=hashlib.sha256(target.read_bytes()).hexdigest()
    r['colors']=len({p for p in image.get_flattened_data() if p[3]});r['alpha_binary']=True
    bounds=image.getbbox();assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<image.width and bounds[3]<image.height,(r['id'],bounds)
    im=image if image.width>=128 else image.resize((image.width*2,image.height*2),Image.Resampling.NEAREST)
    # Contact sheet can crop empty padding without changing the runtime sprite.
    im=im.crop(im.getbbox());x=i%5*204+(204-im.width)//2;y=i//5*210+5
    sheet.paste(im,(x,y),im);draw.text((i%5*204+4,i//5*210+185),r['id'],font=font,fill='wheat')
(DOC/'환경_정지_선택.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sheet.save(DOC/'환경_정지_비교.png')
print('32 native-rendered transparent sprites prepared. No geometric/image-axis scaling.')
