from pathlib import Path
import json, hashlib
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parent
NAMES={'naru':'타블렌','doyun':'코르빈','sora':'이세르','neighbor_bread':'오렐','child_berries':'피니아','traveler_water':'라슈','gatherer_herbs':'엘미','miner_ore':'바르크','healer_moss':'세이나','delvin':'델빈'}
OUT=ROOT/'픽셀_정리';OUT.mkdir(exist_ok=True)
rows=[]
font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',16)
sheet=Image.new('RGB',(960,480),'#383129');draw=ImageDraw.Draw(sheet)
for i,(key,name) in enumerate(NAMES.items()):
    source=ROOT/'생성_원본'/(key+'.png')
    if not source.exists():continue
    im=Image.open(source).convert('RGBA')
    mask=im.getchannel('A').point(lambda a:255 if a>=128 else 0)
    bbox=mask.getbbox();assert bbox
    im.putalpha(mask);im=im.crop(bbox)
    height=84
    width=round(im.width*height/im.height)
    assert width<=90,(key,width)
    im=im.resize((width,height),Image.Resampling.NEAREST)
    mask=im.getchannel('A')
    opaque_rgb=im.convert('RGB')
    opaque_rgb.paste((56,49,41),mask=mask.point(lambda v:255-v))
    rgb=opaque_rgb.quantize(colors=96,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).convert('RGB').convert('RGBA')
    rgb.putalpha(mask)
    sprite=Image.new('RGBA',(96,96));sprite.alpha_composite(rgb,((96-width)//2,90-height))
    sprite.putdata([(r,g,b,a) if a else (0,0,0,0) for r,g,b,a in sprite.get_flattened_data()])
    dest=OUT/(key+'_south_west_96.png');sprite.save(dest)
    assert sprite.size==(96,96)
    assert set(sprite.getchannel('A').get_flattened_data())<={0,255}
    assert len({p[:3] for p in sprite.get_flattened_data() if p[3]})<=96
    rows.append({'id':key,'name':name,'direction':'south-west','file':dest.relative_to(ROOT).as_posix(),'size':[96,96],'feet':[48,90],'opaque_bbox':sprite.getbbox(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'status':'corrected_static_candidate_not_runtime'})
    x=(i%5)*192;y=(i//5)*240
    sheet.paste(sprite.resize((192,192),Image.Resampling.NEAREST),(x,y+2),sprite.resize((192,192),Image.Resampling.NEAREST))
    draw.text((x+8,y+200),name,font=font,fill='#f6e5c8')
    draw.text((x+8,y+222),key,font=font,fill='#c5bdab')
sheet.save(ROOT/'전신_비교.png')
(ROOT/'후보_목록.json').write_text(json.dumps({'status':'corrected_static_candidate_not_runtime','assets':rows,'rejected_outputs':{key:'픽셀_정리/'+key+'_south_west.png' for key in NAMES},'reason':'64 canvas / 52px content sampled below source pixel density; faces and outlines lost'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(ROOT/'검사_결과.json').write_text(json.dumps({'count':len(rows),'failures':0,'checks':['96x96','binary_alpha','transparent_RGB_zero','opaque_colors<=96','feet_bottom90','sha256'],'runtime_connected':False,'animation':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('NPC static candidates',len(rows),'failures 0')
