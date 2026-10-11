from pathlib import Path
import argparse, json, hashlib, shutil, csv
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
import sys
sys.path.insert(0, str(HERE.parent))
from 목록_갱신 import known_ids, refresh_catalog


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def accent(rgb, mode):
    r, g, b = rgb
    if mode == 'yellow': return r > 150 and g > 120 and b < 130
    if mode == 'gold': return r > 170 and g > 115 and b < 110
    if mode == 'cyan': return b > r + 15 and g > r + 10
    if mode == 'moss': return g >= r * 0.85 and g > b + 20
    if mode == 'turquoise': return g > r + 12 and b > r + 12
    if mode == 'purple': return b > g + 25 and r > g + 15
    if mode == 'brass': return r > 130 and g > 95 and r > b + 50 and g > b + 25 and r - g < 85
    return False

def palette(samples, count):
    if not samples: return []
    strip = Image.new('RGB', (len(samples), 1))
    strip.putdata(samples)
    quant = strip.quantize(colors=count, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    colors = quant.getpalette()
    return [tuple(colors[i * 3:i * 3 + 3]) for _, i in quant.getcolors()]

def closest(color, choices):
    return min(choices, key=lambda p: sum((a-b)**2 for a,b in zip(color,p)))

def main():
    parser = argparse.ArgumentParser(description='허용된 Python 픽셀 정리: 비율 유지, 최근접, 강조색 보존')
    parser.add_argument('--source-root', type=Path)
    args = parser.parse_args()
    config = json.loads((HERE/'프롬프트.json').read_text(encoding='utf-8-sig'))
    root = HERE.parents[4]
    with (root/'data/expedition/enemies.csv').open(encoding='utf-8-sig',newline='') as stream:
        enemies = list(csv.DictReader(stream))
    with (root/'data/expedition/expedition_events.csv').open(encoding='utf-8-sig',newline='') as stream:
        events = list(csv.DictReader(stream))
    enemy_lookup = {e['id']:e for e in enemies}
    generated_ids = known_ids(HERE.parent, (a["id"] for a in config["assets"]))
    remaining = [dict(id=e['id'],name=e['name'],boss=e['loot_table'].endswith('_boss'),status='not_generated')
                 for e in enemies if e['id'] not in generated_ids]
    coverage = dict(enemy_ids=len(enemies),generated_ids=len(generated_ids),remaining_ids=len(remaining),
                    ordinary_remaining=sum(not e['boss'] for e in remaining),boss_remaining=sum(e['boss'] for e in remaining))
    (HERE/'미제작_목록.json').write_text(json.dumps(dict(source='data/expedition/enemies.csv',remaining=remaining),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

    raw_dir, out_dir = HERE/'생성_원본', HERE/'픽셀_정리'
    raw_dir.mkdir(exist_ok=True)
    out_dir.mkdir(exist_ok=True)
    checks, assets = [], []
    for spec in config['assets']:
        raw = raw_dir/(spec['id']+'.png')
        if args.source_root:
            src = args.source_root/spec['generated']
            if raw.exists():
                assert digest(raw) == digest(src), '생성 원본 덮어쓰기 금지'
            else:
                shutil.copyfile(src, raw)
        source = Image.open(raw).convert('RGBA')
        alpha = source.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
        bbox = alpha.getbbox()
        assert bbox, '빈 이미지'
        source.putalpha(alpha)
        cropped = source.crop(bbox)
        factor = min(spec['max_size'][0]/cropped.width, spec['max_size'][1]/cropped.height)
        size = (max(1,round(cropped.width*factor)),max(1,round(cropped.height*factor)))
        reduced = cropped.resize(size, Image.Resampling.NEAREST)
        feature_pixels = []
        if spec.get('preserve_small_features'):
            # 눈 색이 최근접 축소에서 사라지지 않도록 원본 색 영역 중심을 한 픽셀로 표본화.
            points = {(i % cropped.width, i // cropped.width): p[:3]
                      for i, p in enumerate(cropped.get_flattened_data())
                      if p[3] and accent(p[:3], spec['accent'])}
            components = []
            remaining = set(points)
            while remaining:
                start = min(remaining)
                remaining.remove(start)
                group, todo = [start], [start]
                while todo:
                    x, y = todo.pop()
                    for neighbor in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                        if neighbor in remaining:
                            remaining.remove(neighbor); group.append(neighbor); todo.append(neighbor)
                components.append(group)
            largest = max((len(g) for g in components), default=0)
            for group in sorted(components, key=lambda g: (-len(g), min(g))):
                if len(group) < max(20, largest * 0.025): continue
                x = min(size[0]-1, int(sum(p[0] for p in group)/len(group)*size[0]/cropped.width))
                y = min(size[1]-1, int(sum(p[1] for p in group)/len(group)*size[1]/cropped.height))
                assert reduced.getpixel((x,y))[3], '눈 표본이 실루엣 밖에 있음'
                rgb = tuple(sorted(points[p][c] for p in group)[len(group)//2] for c in range(3))
                reduced.putpixel((x,y), (*rgb,255))
                feature_pixels.append(dict(pixel=[x,y],source_area=len(group),rgb=list(rgb)))
        opaque = [p[:3] for p in reduced.get_flattened_data() if p[3]]
        highlights = [p for p in opaque if accent(p,spec['accent'])]
        base = [p for p in opaque if not accent(p,spec['accent'])]
        base_colors, accent_colors = palette(base,24), palette(highlights,8)
        normalized = []
        for r,g,b,a in reduced.get_flattened_data():
            if not a: normalized.append((0,0,0,0)); continue
            rgb = (r,g,b)
            colors = accent_colors if accent(rgb,spec['accent']) else base_colors
            normalized.append((*closest(rgb,colors),255))
        reduced.putdata(normalized)
        result = Image.new('RGBA',(128,128),(0,0,0,0))
        position = ((128-size[0])//2,112-size[1])
        result.paste(reduced,position)
        output = out_dir/(spec['id']+'.png')
        result.save(output,optimize=True)
        count = len(set(p[:3] for p in result.get_flattened_data() if p[3]))
        accent_count = sum(1 for p in result.get_flattened_data() if p[3] and accent(p[:3],spec['accent']))
        assert count <= 32 and accent_count >= spec['min_accent'], (spec['id'], count, accent_count)
        assert result.getbbox()[3] == 112
        checks.append(dict(id=spec['id'],crop=list(bbox),source_size=list(source.size),scaled_size=list(size),position=list(position),canvas=[128,128],anchor=[64,112],colors=count,alpha=[0,255],accent=spec['accent'],accent_pixels=accent_count,feature_samples=feature_pixels,source_sha256=digest(raw),sha256=digest(output)))
        assets.append(dict(id=spec['id'],enemy_id=spec['id'],name=spec['name'],data_name=enemy_lookup[spec['id']]['name'],loot_table=enemy_lookup[spec['id']]['loot_table'],events=[e['event_id'] for e in events if e['result_type']=='battle' and e['target_id']==spec['id']],source_sha256=digest(raw),sprite='픽셀_정리/'+output.name,source='생성_원본/'+raw.name,sha256=digest(output),state='idle',frames=1,anchor=[64,112]))
    for name,data in [('검사_결과.json',dict(method='uniform_nearest_24_base_8_accent_with_eye_centroid_samples',checks=checks)),('후보_목록.json',dict(status='candidate_not_installed',tool='built-in image_gen',runtime_applied=False,canvas=[128,128],anchor=[64,112],view='south-west',anchors_provisional=True,animation=False,subjects=len(config['assets']),frames=len(assets),coverage=coverage,assets=assets))]:
        (HERE/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    refresh_catalog(HERE.parent)
    preview = Image.new('RGB',(1200,900),(47,40,33))
    draw = ImageDraw.Draw(preview)
    font = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',18)
    small = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',12)
    for i,spec in enumerate(config['assets']):
        x,y = (i%3)*400,(i//3)*450
        draw.text((x+14,y+12),spec['name'],fill=(241,218,172),font=font)
        im = Image.open(out_dir/(spec['id']+'.png')).convert('RGBA').resize((384,384),Image.Resampling.NEAREST)
        preview.paste(im,(x+8,y+38),im)
        draw.text((x+14,y+416),'128 × 128 · 3배 확대 · 후보 / '+spec['id'],fill=(221,206,178),font=small)
    preview.save(HERE/'보스_6종_비교.png')
    comparison = Image.new('RGB',(1200,460),(47,40,33))
    draw = ImageDraw.Draw(comparison)
    normal = ['field_slime','일반_추가/mine_shardling','swamp_slime','ruins_sentinel','일반_추가/meadow_fluffling','일반_추가/river_pebbling']
    for i,(normal_id,spec) in enumerate(zip(normal,config['assets'])):
        parts = normal_id.split('/')
        normal_path = HERE.parent.joinpath(*parts[:-1],'픽셀_정리',parts[-1]+'.png')
        for row,path in enumerate([normal_path,out_dir/(spec['id']+'.png')]):
            im = Image.open(path).convert('RGBA'); im = im.crop(im.getbbox())
            im = im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
            comparison.paste(im,(i*200+(200-im.width)//2,190+row*230-im.height),im)
        draw.text((i*200+10,202),'일반 → 보스 · 같은 2배 확대',font=small,fill=(241,218,172))
    comparison.save(HERE/'일반_보스_크기_비교.png')
    print(json.dumps(checks,ensure_ascii=False,indent=2))

if __name__ == '__main__':
    main()
