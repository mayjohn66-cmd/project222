"""원본 기반 정지 방향을 분리한다. 기본은 읽기 전용 재현 검사, --install만 기록한다.

AI가 없는 면을 그린 원본은 보존한다. 기존 남서 PNG는 수정하지 않는다.
허용된 픽셀 보정: 알파 정리, 전체 균일 최근접 축소, 기존 팔레트, 좌우 반전.
"""
from pathlib import Path
from collections import deque
from io import BytesIO
import argparse
import hashlib
import json
import re
import shutil
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / 'docs/그림_작업/받은그림/NPC_추가_방향'
DIRECTIONS = ['south', 'south-east', 'east', 'north-east', 'north', 'north-west', 'west', 'south-west']
NAMES = {'blacksmith': '대장장이', 'commuter': '현대 직장인'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encoded(image):
    stream = BytesIO()
    image.save(stream, format='PNG')
    return stream.getvalue()


def sheet_subjects(image, columns):
    """반투명 생성 여백/분리된 작은 점만 제거. 원본 남서에는 사용하지 않는다."""
    image = image.convert('RGBA')
    mask = image.getchannel('A').point(lambda a: 255 if a >= 200 else 0)
    width, height = image.size
    data = bytearray(mask.tobytes())
    components = []
    for start, value in enumerate(data):
        if not value:
            continue
        data[start] = 0
        todo, found = deque([start]), []
        while todo:
            at = todo.pop()
            found.append(at)
            x, y = at % width, at // width
            for dx, dy in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    other = ny * width + nx
                    if data[other]:
                        data[other] = 0
                        todo.append(other)
        if len(found) > 300:
            components.append(found)
    chosen = sorted(components,key=len,reverse=True)[:columns*2]
    assert len(chosen) == columns*2, 'incomplete isolated sheet'
    subjects = []
    for component in chosen:
        xs, ys = [at % width for at in component], [at // width for at in component]
        bounds = (min(xs),min(ys),max(xs)+1,max(ys)+1)
        assert bounds[0] > 0 and bounds[1] > 0 and bounds[2] < width and bounds[3] < height, 'native sheet clipped'
        cropped = image.crop(bounds)
        local_width, local_height = cropped.size
        cleaned = bytearray(local_width * local_height)
        for at in component:
            x, y = at % width - bounds[0], at // width - bounds[1]
            cleaned[y*local_width+x] = 255
        cropped.putalpha(Image.frombytes('L',cropped.size,bytes(cleaned)))
        subjects.append((cropped,bounds))
    subjects.sort(key=lambda pair:(pair[1][1]+pair[1][3])/2)
    # 생성기가 셀 중심을 정확히 지키지 않아도 실제 그림의 전체 경계를 읽는다.
    return sorted(subjects[:columns],key=lambda pair:pair[1][0])+sorted(subjects[columns:],key=lambda pair:pair[1][0])


def frame(subjects, index, flip, base, target_height):
    subject, bounds = subjects[index]
    native_size = subject.size
    if flip:
        subject = ImageOps.mirror(subject)
    # 전체에 같은 배율만 사용한다. 세로만 압축하지 않는다.
    scaled_width = round(subject.width * target_height / subject.height)
    assert 1 <= scaled_width <= 86, 'sprite too wide for safe canvas'
    subject = subject.resize((scaled_width,target_height), Image.Resampling.NEAREST)
    colors = sorted({p[:3] for p in base.get_flattened_data() if p[3]})
    assert len(colors) <= 96
    palette = Image.new('P',(1,1))
    values = [value for color in colors for value in color]
    palette.putpalette(values + [0]*(768-len(values)))
    alpha = subject.getchannel('A')
    subject = subject.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGBA')
    subject.putalpha(alpha)
    result = Image.new('RGBA',(96,96))
    occupied = subject.getbbox()
    # 최근접 축소에서 외곽 한 줄이 빠질 수 있으므로 실제 발 끝을 지면에 맞춘다.
    result.alpha_composite(subject,(48-scaled_width//2,90-occupied[3]))
    pixels = [(r,g,b,a) if a else (0,0,0,0) for r,g,b,a in result.get_flattened_data()]
    result.putdata(pixels)
    return result, {'cell':index,'mirrored':flip,'native_subject_size':list(native_size),
                    'native_bounds':list(bounds),'uniform_scale':target_height/native_size[1]}


def write(path, data, install):
    if install:
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(data)
    else:
        assert path.exists() and path.read_bytes() == data, 'not reproducible: '+str(path.relative_to(ROOT))


def apply(install):
    inputs = json.loads((HERE/'제작_입력.json').read_text(encoding='utf-8'))
    npcs = json.loads((ROOT/'data/art/npc_sprite_assets.json').read_text(encoding='utf-8'))
    poses = json.loads((ROOT/'data/art/actor_pose_assets.json').read_text(encoding='utf-8'))
    output, report, pictures = {}, [], {}
    for entry in inputs['entries']:
        identity = entry['id']
        base_row = (npcs if identity in npcs else poses)[identity]
        base_path = ROOT / base_row['path'].removeprefix('res://')
        reference = ROOT / entry['reference']
        original_sha, reference_sha = sha(base_path), sha(reference)
        base = Image.open(base_path).convert('RGBA')
        height = base.getbbox()[3] - base.getbbox()[1]
        raw_path = HERE / '생성_원본' / (identity+'.png')
        if install:
            raw_path.parent.mkdir(parents=True,exist_ok=True)
            native = Path(entry['generated_path'])
            if native.exists():
                assert sha(native) == entry['generated_sha256']
                shutil.copy2(native,raw_path)
        assert sha(raw_path) == entry['generated_sha256'], 'native output bytes changed'
        sheet = Image.open(raw_path).convert('RGBA')
        assert sheet.getchannel('A').getextrema()[0] == 0, 'not transparent'
        subjects = sheet_subjects(sheet,entry['columns'])
        row = {'name':base_row.get('name',NAMES.get(identity,identity)),
               'base_path':base_row['path'],'base_sha256':original_sha,'reference':entry['reference'],
               'reference_sha256':reference_sha,'reference_height':height,'directions':{}}
        pictures[identity] = {}
        for direction in DIRECTIONS:
            if direction == 'south-west':
                image, path = base, base_path
                info = {'source_kind':'unchanged_existing'}
            else:
                path = ROOT/'art/actors/directions'/identity/(direction.replace('-','_')+'.png')
                if direction == 'south-east':
                    image = ImageOps.mirror(base)
                    info = {'source_kind':'mirror_of_existing','mirrored':True,'source_path':base_row['path']}
                else:
                    index, flip = entry['cells'][direction]
                    image, info = frame(subjects,index,flip,base,height)
                    info.update(source_kind='native_turnaround',source=raw_path.relative_to(ROOT).as_posix())
                write(path,encoded(image),install)
                imported = Path(str(path)+'.import')
                if install and not imported.exists():
                    template = Path(str(base_path)+'.import').read_text(encoding='utf-8')
                    template = re.sub(r'^uid=.*\n','',template,flags=re.MULTILINE)
                    resource = 'res://'+path.relative_to(ROOT).as_posix()
                    template = template.replace(base_row['path'],resource)
                    target = 'res://.godot/imported/'+path.name+'-'+hashlib.md5(resource.encode()).hexdigest()+'.ctex'
                    template = re.sub(r'res://\.godot/imported/[^"\]]+',lambda match:target,template)
                    imported.write_text(template,encoding='utf-8')
                assert imported.exists() and 'compress/mode=0' in imported.read_text(encoding='utf-8')
            used = image.getbbox()
            assert image.size == (96,96) and abs(used[1]-(90-height)) <= 2 and used[3] == 90, (identity,direction,used,height)
            assert set(image.getchannel('A').get_flattened_data()) <= {0,255}
            assert len({p[:3] for p in image.get_flattened_data() if p[3]}) <= 96
            row['directions'][direction] = {'path':'res://'+path.relative_to(ROOT).as_posix(),
                                          'sha256':sha(path),'feet':[48,90],**info}
            pictures[identity][direction] = image
        assert sha(base_path) == original_sha and sha(reference) == reference_sha, 'existing original modified'
        output[identity] = row
        report.append({'id':identity,'raw':raw_path.relative_to(ROOT).as_posix(),'raw_sha256':sha(raw_path),
                       'reference_sha256':reference_sha,'base_sha256':original_sha,'size':list(sheet.size),
                       'height':height,'frames':8,'existing_preserved':True})
    write(ROOT/'data/art/npc_direction_assets.json',
          (json.dumps(output,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),install)
    write(HERE/'검사_결과.json',(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),install)
    if install:
        rejected = HERE/'생성_원본'/'naru_scaled_reference_rejected.png'
        if Path(inputs['rejected']['path']).exists(): shutil.copy2(inputs['rejected']['path'],rejected)
        assert sha(rejected) == inputs['rejected']['sha256']
        gallery(pictures,output)
    print('PASS characters=',len(output),' directions=',len(output)*8,' new PNG=',len(output)*7,
          '; existing south-west and source originals unchanged; mode=', 'install' if install else 'read-only')


def gallery(pictures,metadata):
    font = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',16)
    ids = list(pictures)
    for group in range(3):
        sheet = Image.new('RGB',(8*300,4*322),(55,48,41))
        draw = ImageDraw.Draw(sheet)
        for row, identity in enumerate(ids[group*4:group*4+4]):
            for col,direction in enumerate(DIRECTIONS):
                x,y = col*300,row*322
                draw.text((x+8,y+5),metadata[identity]['name']+' '+direction,font=font,fill=(240,218,180))
                shown = pictures[identity][direction].resize((288,288),Image.Resampling.NEAREST)
                sheet.paste(shown,(x+6,y+30),shown)
        sheet.save(HERE/('방향_비교_'+str(group+1)+'.png'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install',action='store_true')
    apply(parser.parse_args().install)
