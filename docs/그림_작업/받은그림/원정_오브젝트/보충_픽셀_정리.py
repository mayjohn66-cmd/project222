from pathlib import Path
import argparse, json, hashlib, shutil
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def accent(rgb, mode):
    r, g, b = rgb
    if mode == 'gold': return r > 170 and g > 115 and b < 110
    if mode == 'cyan': return b > r + 15 and g > r + 10
    if mode == 'moss': return g > r + 12 and g > b + 15
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
    config = json.loads((HERE/'보충_프롬프트.json').read_text(encoding='utf-8-sig'))
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
        result = Image.new('RGBA',(64,64),(0,0,0,0))
        position = ((64-size[0])//2,56-size[1])
        result.paste(reduced,position)
        output = out_dir/(spec['id']+'.png')
        result.save(output,optimize=True)
        count = len(set(p[:3] for p in result.get_flattened_data() if p[3]))
        accent_count = sum(1 for p in result.get_flattened_data() if p[3] and accent(p[:3],spec['accent']))
        assert count <= 32 and accent_count >= 10
        assert result.getbbox()[3] == 56
        checks.append(dict(id=spec['id'],crop=list(bbox),source_size=list(source.size),scaled_size=list(size),position=list(position),canvas=[64,64],anchor=[32,56],colors=count,alpha=[0,255],accent=spec['accent'],accent_pixels=accent_count,source_sha256=digest(raw),sha256=digest(output)))
        assets.append(dict(id=spec['id'],item=spec['item'],selector=spec['selector'],item_hint=spec.get('item_hint'),guaranteed_item=spec.get('guaranteed_item'),kind=spec['kind'],gather_table=spec['table'],sprite='픽셀_정리/'+output.name,source='생성_원본/'+raw.name,sha256=digest(output),state=spec['state']))
    for name,data in [('보충_검사_결과.json',dict(method='uniform_nearest_24_base_8_accent',checks=checks)),('보충_후보_목록.json',dict(status='candidate_not_installed',tool='built-in image_gen',runtime_applied=False,canvas=[64,64],anchor=[32,56],view='south-west',assets=assets))]:
        (HERE/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    preview = Image.new('RGB',(840,360),(47,40,33))
    draw = ImageDraw.Draw(preview)
    font_path = Path('C:/Windows/Fonts/malgun.ttf')
    font = ImageFont.truetype(str(font_path),18)
    small = ImageFont.truetype(str(font_path),12)
    for i,spec in enumerate(config['assets']):
        x = i*280
        draw.text((x+14,12),spec['name'],fill=(241,218,172),font=font)
        im = Image.open(out_dir/(spec['id']+'.png')).convert('RGBA')
        preview.paste(im.resize((256,256),Image.Resampling.NEAREST),(x+12,42),im.resize((256,256),Image.Resampling.NEAREST))
        draw.text((x+14,304),'64 × 64 · 4배 확대 · 후보',fill=(221,206,178),font=small)
        draw.text((x+14,325),spec['id'],fill=(184,174,150),font=small)
    preview.save(HERE/'보충_오브젝트_비교.png')
    print(json.dumps(checks,ensure_ascii=False,indent=2))

if __name__ == '__main__':
    main()
