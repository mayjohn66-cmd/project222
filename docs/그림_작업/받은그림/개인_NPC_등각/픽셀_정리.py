from pathlib import Path
import json, hashlib
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parent
NAMES={'naru':'타블렌','doyun':'코르빈','sora':'이세르','neighbor_bread':'오렐','child_berries':'피니아','traveler_water':'라슈','gatherer_herbs':'엘미','miner_ore':'바르크','healer_moss':'세이나','delvin':'델빈'}
OUT=ROOT/'픽셀_정리';OUT.mkdir(exist_ok=True)
rows=[]
font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',16)
sheet=Image.new('RGB',(1000,510),'#383129');draw=ImageDraw.Draw(sheet)
for i,(key,name) in enumerate(NAMES.items()):
    source=ROOT/'생성_원본'/(key+'.png')
    if not source.exists():continue
    im=Image.open(source).convert('RGBA')
    mask=im.getchannel('A').point(lambda a:255 if a>=128 else 0)
    bbox=mask.getbbox();assert bbox
    im.putalpha(mask);im=im.crop(bbox)
    height=52
    width=round(im.width*height/im.height)
    assert width<=60,(key,width)
    im=im.resize((width,height),Image.Resampling.NEAREST)
    mask=im.getchannel('A')
    rgb=im.convert('RGB').quantize(colors=48,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).convert('RGB').convert('RGBA')
    rgb.putalpha(mask)
    sprite=Image.new('RGBA',(64,64));sprite.alpha_composite(rgb,((64-width)//2,60-height))
    sprite.putdata([(r,g,b,a) if a else (0,0,0,0) for r,g,b,a in sprite.getdata()])
    dest=OUT/(key+'_south_west.png');sprite.save(dest)
    assert sprite.size==(64,64)
    assert set(sprite.getchannel('A').getdata())<={0,255}
    assert len({p[:3] for p in sprite.getdata() if p[3]})<=48
    rows.append({'id':key,'name':name,'direction':'south-west','file':dest.relative_to(ROOT).as_posix(),'size':[64,64],'feet':[32,60],'opaque_bbox':sprite.getbbox(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'status':'static_candidate_not_runtime'})
    x=(i%5)*200;y=(i//5)*255
    sheet.paste(sprite.resize((192,192),Image.Resampling.NEAREST),(x+4,y+5),sprite.resize((192,192),Image.Resampling.NEAREST))
    draw.text((x+8,y+205),name,font=font,fill='#f6e5c8')
    draw.text((x+8,y+230),key,font=font,fill='#c5bdab')
sheet.save(ROOT/'전신_비교.png')
(ROOT/'후보_목록.json').write_text(json.dumps({'status':'static_candidate_not_runtime','assets':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(ROOT/'검사_결과.json').write_text(json.dumps({'count':len(rows),'failures':0,'checks':['64x64','binary_alpha','transparent_RGB_zero','opaque_colors<=48','feet_bottom60','sha256'],'runtime_connected':False,'animation':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('NPC static candidates',len(rows),'failures 0')
