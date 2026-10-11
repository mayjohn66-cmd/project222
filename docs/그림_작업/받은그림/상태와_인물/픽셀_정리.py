"""기존 도형/인물 머리를 보존하고 생성된 상태/하체만 정리한다. Pillow 사용."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps, ImageFont
import colorsys
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / '픽셀_정리'
OUT.mkdir(exist_ok=True)
REPORT = {'preserved_heads': [], 'assets': []}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def save(image, name, destination):
    path = OUT / (name + '.png')
    image.save(path)
    runtime = ROOT / destination
    runtime.parent.mkdir(parents=True, exist_ok=True)
    image.save(runtime)
    colors = {p[:3] for p in image.getdata() if p[3]}
    assert len(colors) <= 96, (name, len(colors))
    assert set(image.getchannel('A').getdata()) <= {0, 255}
    REPORT['assets'].append({'id': name, 'path': destination, 'sha256': sha(runtime), 'size': list(image.size), 'colors': len(colors)})
    return {'path': 'res://' + destination, 'source': str(path.relative_to(ROOT)).replace('\\','/'), 'sha256': sha(runtime)}

def quantize(image, source=None):
    alpha = image.getchannel('A').point(lambda a: 255 if a >= 220 else 0)
    if source is None:
        rgb = image.convert('RGB').quantize(colors=80, dither=Image.Dither.NONE).convert('RGB')
    else:
        colors = sorted({p[:3] for p in source.getdata() if p[3]})
        assert len(colors) <= 96
        palette = Image.new('P', (1,1))
        flat = [c for color in colors for c in color]
        palette.putpalette(flat + [0] * (768-len(flat)))
        rgb = image.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE).convert('RGB')
    image = rgb.convert('RGBA')
    image.putalpha(alpha)
    return image

# 단풍은 생성안의 따뜻한 색 방향만 참고하고 실제 선택본의 실루엣/줄기/발자국을 보존한다.
tree_path = ROOT / 'art/received/nature/iso_tree_round.png'
tree = Image.open(tree_path).convert('RGBA')
nature = {}
for name, hue, tint in [('orange', .073, 'ffffff'), ('red', .025, 'ff9a84'), ('gold', .13, 'ffe48a'), ('amber', .095, 'ffc070')]:
    image = tree.copy()
    changed = 0
    for y in range(82):
        for x in range(image.width):
            r,g,b,a = tree.getpixel((x,y))
            h,s,v = colorsys.rgb_to_hsv(r/255,g/255,b/255)
            if a and .15 < h < .48 and s > .18:
                rgb = colorsys.hsv_to_rgb(hue + (h-.28)*.035, min(.9,max(s,.65)), v)
                image.putpixel((x,y), (*[round(c*255) for c in rgb],a))
                changed += 1
    # 이미 선택본은 binary alpha/80색 이하이며 좌표와 불투명 픽셀은 정확히 유지된다.
    assert image.getchannel('A').tobytes() == tree.getchannel('A').tobytes()
    assert image.crop((0,82,image.width,image.height)).tobytes() == tree.crop((0,82,tree.width,tree.height)).tobytes()
    row = save(image, 'tree_autumn_'+name, 'art/received/nature_states/tree_autumn_'+name+'.png')
    nature['autumn_'+name] = {**row,'anchor':[49,115],'normal_source':'res://art/received/nature/iso_tree_round.png','leaf_tint':tint,'changed_leaf_pixels':changed,'reference_sha256':sha(tree_path)}

# 열매는 생성안의 빨간 부분만 기존 빈 덤불 위에 합성한다. 수확 전후 잎/그림자/발자국은 동일하다.
bush_path = ROOT / 'art/received/nature/bush.png'
bush = Image.open(bush_path).convert('RGBA')
berry = Image.open(HERE/'생성_원본/state_berry.png').convert('RGBA')
berry = berry.crop(berry.getchannel('A').point(lambda a: 255 if a>=220 else 0).getbbox()).resize((50,48),Image.Resampling.NEAREST)
ready = bush.copy()
berry_pixels = []
for y in range(48):
    for x in range(50):
        r,g,b,a = berry.getpixel((x,y))
        px,py=x+7,y+8
        if a>=220 and r>g*1.6 and r>b*1.35 and r>75 and bush.getpixel((px,py))[3]:
            ready.putpixel((px,py), (196,47,68,255) if r>180 else (116,27,46,255))
            berry_pixels.append([px,py])
for state,image in [('empty',bush),('ready',ready)]:
    row=save(image,'berry_'+state,'art/received/nature_states/berry_'+state+'.png')
    nature['berry_'+state]={**row,'anchor':[32,56],'normal_source':'res://art/received/nature/bush.png','reference_sha256':sha(bush_path)}
REPORT['berry_pixels']=berry_pixels
assert ready.getchannel('A').tobytes()==bush.getchannel('A').tobytes()

actors = {}
def actor_image(key, identity=None, kind='', back=False):
    src=HERE/'생성_원본'/('actor_'+key+'.png')
    image=Image.open(src).convert('RGBA')
    mask=image.getchannel('A').point(lambda a:255 if a>=220 else 0)
    image=image.crop(mask.getbbox())
    height=84 if not kind else (60 if kind=='floor' else (70 if identity.startswith('player_') else 61))
    width=round(image.width*height/image.height)
    image=quantize(image.resize((width,height),Image.Resampling.NEAREST))
    canvas=Image.new('RGBA',(96,96))
    canvas.paste(image,(48-width//2,90-height))
    if identity:
        if identity.startswith('player_'):
            ref=ROOT/'art/actors'/identity/'rotations'/('north_west.png' if back else 'south_west.png')
            standing=Image.open(ref).convert('RGBA').resize((85,85),Image.Resampling.NEAREST)
            cut=29 if identity.endswith('male') else 34
            standing85=Image.new('RGBA',(96,96)); standing85.paste(standing,(6,5)); standing=standing85
            cut+=5
            fraction=.43 if kind=='floor' else .38
        else:
            ref=ROOT/'art/actors/npc'/identity/'south_west.png'
            standing=Image.open(ref).convert('RGBA')
            cut={'doyun':32,'naru':44,'sora':36}[identity]
            fraction={'doyun':.34,'naru':.42,'sora':.35}[identity]
        # 생성된 하체를 원본 인물 팔레트로 맞춘 뒤 머리/얼굴을 복사한다.
        canvas=quantize(canvas,standing)
        head=standing.crop((0,0,96,cut))
        old_box=head.getbbox()
        neck_y=90-height+round(height*fraction)
        shift=neck_y-cut
        canvas.paste((0,0,0,0),(0,0,96,neck_y))
        canvas.alpha_composite(head,(0,shift))
        # 투명 위쪽 여백까지 포함해 실제 복사된 머리 RGB/알파를 검증한다.
        expected=head.crop(old_box)
        observed=canvas.crop((old_box[0],old_box[1]+shift,old_box[2],old_box[3]+shift))
        assert expected.tobytes()==observed.tobytes(), key
        REPORT['preserved_heads'].append({'key':key,'reference':str(ref.relative_to(ROOT)).replace('\\','/'),'reference_sha256':sha(ref),'source_head_box':list(old_box),'shift_y':shift,'head_sha256':hashlib.sha256(expected.tobytes()).hexdigest()})
    assert canvas.getbbox()[1]>=0 and canvas.getbbox()[3]==90
    return canvas

for identity in ['blacksmith','commuter']:
    image=actor_image(identity)
    row=save(image,identity,'art/actors/poses/'+identity+'_south_west.png')
    actors[identity]={**row,'feet':[48,90],'direction':'south-west','reference_height':84,'display_height':1.14*.8660254,'pose':'standing'}

for identity in ['player_male','player_female','doyun','naru','sora']:
    variants=[('seat',False)]
    if identity.startswith('player_'): variants+=[('floor',False),('seat',True)]
    for kind,back in variants:
        key=identity+'_'+kind+('_back' if back else '')
        image=actor_image(key,identity,kind,back)
        direction='north-west' if back else 'south-west'
        for flip in [False,True]:
            direct=direction.replace('west','east') if flip else direction
            picked=ImageOps.mirror(image) if flip else image
            name=identity+'_'+kind+'_'+direct.replace('-','_')
            row=save(picked,name,'art/actors/poses/'+name+'.png')
            actors[identity+':'+kind+':'+direct]={**row,'feet':[48,90],'direction':direct,'reference_height':84,'display_height':1.14*.8660254,'pose':kind,'mirrored':flip,'identity':identity}

for filename,data in [('nature_state_assets.json',nature),('actor_pose_assets.json',actors)]:
    (ROOT/'data/art'/filename).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'검사_결과.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',13)
cards=REPORT['assets']
sheet=Image.new('RGB',(896,((len(cards)+3)//4)*320),(56,48,42))
draw=ImageDraw.Draw(sheet)
for index,row in enumerate(cards):
    image=Image.open(ROOT/row['path']).convert('RGBA')
    image=image.resize((image.width*2,image.height*2),Image.Resampling.NEAREST)
    x=index%4*224+(224-image.width)//2; y=index//4*320+270-image.height
    sheet.paste(image,(x,y),image)
    label=row['id'].replace('_south_','\nsouth_').replace('_north_','\nnorth_')
    draw.multiline_text((index%4*224+8,index//4*320+276),label,font=font,fill=(240,220,190))
sheet.save(HERE/'게임용_목록.png')
print(f"runtime {len(cards)} PNG, preserved heads {len(REPORT['preserved_heads'])}, berry overlay {len(berry_pixels)} pixels")
