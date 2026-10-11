from pathlib import Path
import json, shutil, hashlib, itertools
from collections import Counter
from PIL import Image, ImageDraw, ImageFont

HERE=Path('docs/그림_작업/받은그림/낚시_타일').resolve()
ROOT=HERE.parents[3]
RAW=HERE/'생성_원본'; OUT=HERE/'픽셀_정리'; MATERIAL=HERE/'재질_정리'
for p in [RAW,OUT,MATERIAL]:p.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def uv(x,y):return (x+.5)/64+(y+.5)/32-.5,(y+.5)/32-(x+.5)/64+.5
wood=Image.open(ROOT/'art/received/floors/wood_1.png').convert('RGBA')
grass=Image.open(ROOT/'art/received/floors/grass_1.png').convert('RGBA')
mask=wood.getchannel('A')
POINTS=[(x,y) for y in range(32) for x in range(64) if mask.getpixel((x,y))]
assert len(POINTS)==1024 and mask.tobytes()==grass.getchannel('A').tobytes()
config=read(HERE/'프롬프트.json'); materials={}; source_checks=[]
for spec in config['assets']:
 raw=RAW/(spec['id']+'.png')
 if not raw.exists():shutil.copyfile(spec['generated'],raw)
 im=Image.open(raw).convert('RGBA');alpha=im.getchannel('A').point(lambda a:255 if a>=128 else 0);bbox=alpha.getbbox();assert bbox
 assert abs((bbox[2]-bbox[0])/(bbox[3]-bbox[1])-2)<.06,'등각 비율 불일치'
 im.putalpha(alpha);im=im.crop(bbox).resize((64,32),Image.Resampling.NEAREST)
 sample=[p[:3] for p in im.get_flattened_data() if p[3]];strip=Image.new('RGB',(len(sample),1));strip.putdata(sample)
 q=strip.quantize(colors=12,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
 pal=q.getpalette();palette=[tuple(pal[i*3:i*3+3]) for _,i in q.getcolors()]
 common=Counter(sample).most_common(1)[0][0];common=min(palette,key=lambda p:sum((p[c]-common[c])**2 for c in range(3)))
 out=Image.new('RGBA',(64,32));missing=0
 for x,y in POINTS:
  p=im.getpixel((x,y));u,v=uv(x,y)
  if not p[3]:p=(*common,255);missing+=1
  rgb=min(palette,key=lambda c:sum((c[i]-p[i])**2 for i in range(3)))
  if min(u,v,1-u,1-v)<.12:rgb=common
  out.putpixel((x,y),(*rgb,255))
 out.save(MATERIAL/(spec['id']+'.png'));materials[spec['id']]=out
 source_checks.append(dict(id=spec['id'],crop=list(bbox),source_sha256=sha(raw),common_edge_color=list(common),filled_mask_edge_pixels=missing))
water=materials['water_base'];soil=materials['shore_sediment']
assets=[]
def write_asset(id,im,**extra):
 path=OUT/(id+'.png');im.save(path,optimize=True)
 assert im.size==(64,32) and im.getchannel('A').tobytes()==mask.tobytes()
 assert all(p==(0,0,0,0) for p in im.get_flattened_data() if not p[3])
 colors=len({p[:3] for p in im.get_flattened_data() if p[3]});assert colors<=64,(id,colors)
 assets.append(dict(id=id,sprite='픽셀_정리/'+path.name,canvas=[64,32],anchor=[32,16],colors=colors,sha256=sha(path),**extra))
for number in range(1,4):
 im=water.copy()
 if number>1:
  for x,y in POINTS:
   u,v=uv(x,y)
   if min(u,v,1-u,1-v)<.16:continue
   if (((x//3+number*17)*734287)^((y//2+number*23)*912271))%19>2:continue
   p=water.getpixel((x,y)); delta=2 if number==2 else -2
   im.putpixel((x,y),tuple(max(0,min(255,c+delta)) for c in p[:3])+(255,))
 write_asset('water_'+str(number),im,kind='water',variant=number,walkable=False)
directions=['nx','ny','px','py'];pairs=[('nx','ny'),('ny','px'),('px','py'),('py','nx')]
def distance(x,y,d):
 u,v=uv(x,y);return dict(nx=u,ny=v,px=1-u,py=1-v)[d]
def bank_image(edges,inner=False):
 im=water.copy()
 for x,y in POINTS:
  distances=[distance(x,y,d) for d in edges];d=max(distances) if inner else min(distances)
  if d<.17:p=grass.getpixel((x,y))
  elif d<.30:p=soil.getpixel((x,y))
  elif d<.37:
   p=water.getpixel((x,y));p=tuple(min(255,c+9) for c in p[:3])+(255,)
  else:continue
  im.putpixel((x,y),p)
 return im
for count in range(1,4):
 for edges in itertools.combinations(directions,count):
  write_asset('shore_'+'_'.join(edges),bank_image(edges),kind='shore',land_neighbors=list(edges),corner=None,walkable='split_by_land_water_mask')
for pair in pairs:
 write_asset('shore_corner_'+'_'.join(pair),bank_image(pair,True),kind='shore',land_neighbors=[],corner=list(pair),walkable='split_by_land_water_mask')
for i in range(1,4):
 src=ROOT/f'art/received/floors/wood_{i}.png';dest=OUT/f'dock_planks_{i}.png';shutil.copyfile(src,dest)
 im=Image.open(dest).convert('RGBA');assert sha(src)==sha(dest)
 assets.append(dict(id=f'dock_planks_{i}',sprite='픽셀_정리/'+dest.name,canvas=[64,32],anchor=[32,16],kind='dock',walkable=True,colors=len({p[:3] for p in im.get_flattened_data() if p[3]}),sha256=sha(dest),reused_from=f'res://art/received/floors/wood_{i}.png'))
assert len(assets)==24
save(HERE/'후보_목록.json',dict(status='candidate_not_installed',tool='built-in image_gen + authorized Python pixel composition',runtime_applied=False,animation=False,canvas=[64,32],display_cell=[96,48],anchor=[32,16],anchor_provisional=True,generated_sources=2,water_variants=3,shore_variants=18,reused_dock_variants=3,assets=assets))
# Three layout candidates composed only from prepared tiles and existing nature sprites.
font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',18);small=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',13)
layouts=[]
# Coordinate x/y are logical tile axes, not screen coordinates.
layouts.append(dict(id='fish_bank',name='가게 옆 개울',water={(x,y) for x in range(8) for y in range(3,6)},dock={(x,3) for x in range(1,4)},stand=(3,3),float=(3,4)))
layouts.append(dict(id='fish_reeds',name='갈대가 둘러싼 못',water={(x,y) for x in range(2,8) for y in range(2,7)},dock={(2,y) for y in range(2,5)}|{(3,4),(4,4)},stand=(4,4),float=(5,4)))
layouts.append(dict(id='fish_pond',name='숲가의 작은 연못',water={(x,y) for x in range(1,8) for y in range(2,8)}-{(1,2),(7,2),(1,7),(7,7)},dock={(x,4) for x in range(1,5)},stand=(4,4),float=(5,4)))
# Let the stream touch opposite map sides and piers touch dry ground for a clear route.
layouts[0]['dock']={(2,y) for y in range(2,5)};layouts[0]['stand']=(2,4);layouts[0]['float']=(3,4)
layouts[1]['dock']={(x,4) for x in range(1,5)}|{(4,5)};layouts[1]['stand']=(4,5);layouts[1]['float']=(5,5)
asset_map={a['id']:Image.open(HERE/a['sprite']).convert('RGBA') for a in assets}
comparison=Image.new('RGB',(1536,524),(47,40,33));draw=ImageDraw.Draw(comparison)
layout_data=[]
for index,layout in enumerate(layouts):
 tilemap=[];canvas=Image.new('RGBA',(512,400));dock=layout['dock'];wet=layout['water']
 for x,y in sorted(itertools.product(range(9),range(9)),key=lambda p:(sum(p),p[0])):
  cell=(x,y);kind='grass';im=grass
  if cell in wet:
   ne={'nx':(x-1,y),'ny':(x,y-1),'px':(x+1,y),'py':(x,y+1)}
   edges=[d for d in directions if ne[d] not in wet]
   # At the outer view boundary the stream continues instead of being capped.
   if layout['id']=='fish_bank':edges=[d for d in edges if d not in ['nx','px'] or 0<x<7]
   if edges:
    assert len(edges)<4,'고립된 물 한 칸은 별도 네 방향 물가 교차 타일 필요'
    kind='shore_'+'_'.join(edges)
   else:
    diagonal=[pair for pair in pairs if tuple((ne[pair[0]][0]+ne[pair[1]][0]-x,ne[pair[0]][1]+ne[pair[1]][1]-y)) not in wet]
    kind=('shore_corner_'+'_'.join(diagonal[0])) if diagonal else 'water_'+str(1+(x*17+y*31)%3)
   im=asset_map[kind]
  at=(256+(x-y)*32-32,80+(x+y)*16)
  canvas.alpha_composite(im,at);tilemap.append(dict(cell=[x,y],base_tile=kind,dock=cell in dock))
  if cell in dock:canvas.alpha_composite(asset_map['dock_planks_'+str(1+(x+y)%3)],at)
 # Distinct decoration uses existing sprites, not newly generated full scenes.
 decorations=[]
 if layout['id']=='fish_reeds':
  p=ROOT/'docs/그림_작업/받은그림/일반_채집물/픽셀_정리/marsh_reed.png'
  if p.is_file():
   reed=Image.open(p).convert('RGBA')
   for x,y in [(1,2),(7,3),(6,7)]:canvas.alpha_composite(reed,(256+(x-y)*32-32,80+(x+y)*16-40));decorations.append(dict(cell=[x,y],source=p.relative_to(ROOT).as_posix()))
 if layout['id']=='fish_pond':
  p=ROOT/'docs/그림_작업/받은그림/자연물/tree_pine.png'
  tree=Image.open(p).convert('RGBA')
  for x,y in [(0,3),(8,2),(8,7)]:
   canvas.alpha_composite(tree,(256+(x-y)*32-tree.width//2,80+(x+y)*16+16-tree.height));decorations.append(dict(cell=[x,y],source=p.relative_to(ROOT).as_posix()))
 label=layout['name'];draw.text((index*512+16,12),label,font=font,fill=(241,218,172))
 comparison.paste(canvas,(index*512,55),canvas)
 draw.text((index*512+16,460),'공통 물/경계 + 기존 나무판자 · 배치 후보',font=small,fill=(221,206,178))
 draw.text((index*512+16,487),'게임 미연결 · 동일 64×32 규격',font=small,fill=(184,174,150))
 canvas.save(HERE/(layout['id']+'_배치.png'))
 layout_data.append(dict(id=layout['id'],cells=tilemap,stand_cell=list(layout['stand']),float_cell=list(layout['float']),decorations=decorations))
comparison.save(HERE/'낚시터_배치_비교.png')
save(HERE/'배치_후보.json',dict(status='visual_layout_candidate_not_runtime',locations=layout_data,notice='실제 충돌/해금/서기·찌 위치는 연결 후 검증. 플레이어 건설 비용을 추가하지 않는다.'))
# A repeat patch makes seams visible independently from shoreline composition.
patch=Image.new('RGBA',(448,240))
for x in range(7):
 for y in range(7):
  tile=asset_map['water_'+str(1+(x*17+y*31)%3)];patch.alpha_composite(tile,(224+(x-y)*32-32,(x+y)*16))
patch.save(HERE/'물_반복_확인.png')
checks=[]
for a in assets:
 im=asset_map[a['id']];checks.append(dict(id=a['id'],canvas=list(im.size),alpha=[0,255],opaque_pixels=sum(bool(p[3]) for p in im.get_flattened_data()),transparent_rgb_zero=all(p==(0,0,0,0) for p in im.get_flattened_data() if not p[3]),colors=a['colors'],sha256=sha(HERE/a['sprite'])))
for i in [2,3]:
 variant=asset_map['water_'+str(i)]
 for x,y in POINTS:
  u,v=uv(x,y)
  if min(u,v,1-u,1-v)<.16:assert variant.getpixel((x,y))==water.getpixel((x,y))
  assert max(abs(variant.getpixel((x,y))[c]-water.getpixel((x,y))[c]) for c in range(3))<=2
# Tile-center route audit for these preview layouts only, not engine collision validation.
layout_checks=[]
for layout in layouts:
 dry={(x,y) for x in range(9) for y in range(9)}-layout['water']
 walk=dry|layout['dock']; start=(0,0);visited={start};todo=[start]
 while todo:
  x,y=todo.pop()
  for n in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
   if n in walk and n not in visited:visited.add(n);todo.append(n)
 assert layout['stand'] in visited and layout['stand'] in layout['dock']
 assert layout['float'] in layout['water'] and layout['float'] not in layout['dock']
 assert sum(abs(a-b) for a,b in zip(layout['stand'],layout['float']))==1
 layout_checks.append(dict(id=layout['id'],dry_to_stand_route=True,float_on_water=True,adjacent_cast=True,runtime_collision_test=False))
sheet=Image.new('RGB',(1680,760),(47,40,33));d=ImageDraw.Draw(sheet)
for i,a in enumerate(assets):
 x,y=(i%6)*280,(i//6)*190;im=asset_map[a['id']].resize((256,128),Image.Resampling.NEAREST)
 sheet.paste(im,(x+12,y+28),im);d.text((x+12,y+160),a['id'],font=small,fill=(241,218,172))
sheet.save(HERE/'타일_24장_비교.png')
save(HERE/'검사_결과.json',dict(source_checks=source_checks,layout_checks=layout_checks,checks=checks,water_edge_common=True,water_variant_max_channel_delta=2,reused_wood_bytes_equal=True,godot_runtime_test=False))
print('PASS 2 sources, water3, shore18, reused dock3; layouts3')
