"""플레이어의 도트 체형에 맞춰 얼굴을 보존하고 몸통/하체 길이를 정리한다.

기존 원본은 유지한다. 픽셀_정리.py 뒤에 실행해 정지/좌식 선택본을 갱신한다.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / '체형_정리'
SPEC = {'naru': (44, 76), 'doyun': (32, 66), 'sora': (36, 68),
        'neighbor_bread': (38, 70), 'child_berries': (38, 72),
        'traveler_water': (36, 66), 'gatherer_herbs': (36, 68),
        'miner_ore': (48, 80), 'healer_moss': (36, 68), 'delvin': (36, 68),
        'blacksmith': (35, 70), 'commuter': (35, 70)}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def compact(source, cut, height):
    top = source.getbbox()[1]
    head = source.crop((0, top, 96, cut))
    body = source.crop((0, cut, 96, 90))
    new_body_height = height - head.height
    assert 0 < new_body_height <= body.height
    body = body.resize((96, new_body_height), Image.Resampling.NEAREST)
    selected = Image.new('RGBA', (96, 96))
    selected.paste(head, (0, 90-height))
    selected.paste(body, (0, 90-height+head.height))
    assert selected.crop((0, 90-height, 96, 90-height+head.height)).tobytes() == head.tobytes()
    assert selected.getbbox()[3] == 90
    assert set(selected.getchannel('A').getdata()) <= {0, 255}
    assert len({p[:3] for p in selected.getdata() if p[3]}) <= 96
    return selected, hashlib.sha256(head.tobytes()).hexdigest()


def apply():
    OUT.mkdir(exist_ok=True)
    npc_path = ROOT/'data/art/npc_sprite_assets.json'
    pose_path = ROOT/'data/art/actor_pose_assets.json'
    npcs = json.loads(npc_path.read_text(encoding='utf-8'))
    poses = json.loads(pose_path.read_text(encoding='utf-8'))
    heads = json.loads((HERE/'검사_결과.json').read_text(encoding='utf-8'))['preserved_heads']
    report = {'method': 'original head pixels + nearest body resampling; uniform runtime scale', 'assets': []}
    originals = {}
    for identity, (cut, height) in SPEC.items():
        row = (npcs if identity in npcs else poses)[identity]
        original = row.get('original_path', row['path'])
        source_path = ROOT/original.removeprefix('res://')
        originals[identity] = Image.open(source_path).convert('RGBA')
        selected, head_sha = compact(originals[identity], cut, height)
        write(row, source_path, selected, identity, head_sha, height, report)
        if identity in poses:
            row['reference_height'] = height
    # 주민 좌식도 같은 얼굴 픽셀 배율을 사용한다. 앉을 때 머리만 작아지지 않도록 한다.
    for key, row in poses.items():
        identity = row.get('identity', '')
        if identity not in npcs:
            continue
        cut, standing_height = SPEC[identity]
        head_info = next(h for h in heads if h['key'] == identity+'_seat')
        head_end = head_info['source_head_box'][3] + head_info['shift_y']
        original = row.get('original_path', row['path'])
        source_path = ROOT/original.removeprefix('res://')
        source = Image.open(source_path).convert('RGBA')
        ratio = (standing_height-(cut-6))/(90-cut)
        selected_height = head_end-source.getbbox()[1]+round((90-head_end)*ratio)
        selected, head_sha = compact(source, head_end, selected_height)
        write(row, source_path, selected, key.replace(':','_'), head_sha, standing_height, report)
        row['reference_height'] = standing_height
    for path, data in [(npc_path, npcs), (pose_path, poses), (HERE/'체형_검사.json', report)]:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    comparison(npcs, poses, originals)
    gallery(poses)
    print('compact actor images:', len(report['assets']), '; preserved head crops:', len(report['assets']))


def write(row, source_path, selected, identity, head_sha, reference_height, report):
    destination = source_path.with_name(source_path.stem+'_compact.png')
    selected.save(destination)
    copy = OUT/(identity+'.png')
    selected.save(copy)
    row['original_path'] = 'res://'+source_path.relative_to(ROOT).as_posix()
    row['path'] = 'res://'+destination.relative_to(ROOT).as_posix()
    row['source'] = copy.relative_to(ROOT).as_posix()
    row['sha256'] = sha(destination)
    report['assets'].append({'id': identity, 'path': row['path'], 'source_path': row['original_path'],
                             'source_sha256': sha(source_path), 'sha256': row['sha256'],
                             'head_sha256': head_sha, 'bounds': list(selected.getbbox()),
                             'standing_reference_height': reference_height})
    # UID는 Godot이 처음 가져올 때 새로 부여한다. 기존 UID를 복제하지 않는다.
    imported = Path(str(destination)+'.import')
    if not imported.exists():
        text = Path(str(source_path)+'.import').read_text(encoding='utf-8')
        text = re.sub(r'^uid=.*\n', '', text, flags=re.MULTILINE)
        text = text.replace(row['original_path'], row['path'])
        target = 'res://.godot/imported/'+destination.name+'-'+hashlib.md5(row['path'].encode()).hexdigest()+'.ctex'
        text = re.sub(r'res://\.godot/imported/[^"\]]+', lambda m: target, text)
        imported.write_text(text, encoding='utf-8')


def comparison(npcs, poses, originals):
    # Godot 프레임셋과 같은 기준높이로 확대한다. 여백/원본 해상도를 키로 착각하지 않는다.
    names = ['player_male', 'player_female', *SPEC]
    font = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf', 14)
    sheet = Image.new('RGB', (1200, 1760), (55, 48, 41))
    draw = ImageDraw.Draw(sheet)
    for i, identity in enumerate(names):
        x = i % 6 * 200
        y = i // 6 * 580
        if identity.startswith('player_'):
            source = Image.open(ROOT/'art/actors'/identity/'rotations/south_west.png').convert('RGBA')
            height = 64 if identity == 'player_male' else 61
            pairs = [(source, .987268956/height)]*2
        else:
            row = (npcs if identity in npcs else poses)[identity]
            selected = Image.open(ROOT/row['path'][6:]).convert('RGBA')
            display_height = row.get('display_height', .987268956)
            pairs = [(originals[identity], display_height/84), (selected, display_height/SPEC[identity][1])]
        for offset, (image, unit) in zip([0, 280], pairs):
            cropped = image.crop(image.getbbox())
            enlarged = cropped.resize(tuple(round(n*unit*180) for n in cropped.size), Image.Resampling.NEAREST)
            sheet.paste(enlarged, (x+100-enlarged.width//2, y+offset+225-enlarged.height), enlarged)
            draw.text((x+5, y+offset+235), identity+(' 기준' if identity.startswith('player') else (' 이전' if offset == 0 else ' 보정')), font=font, fill='white')
    sheet.save(HERE/'플레이어_체형_비교.png')


def gallery(poses):
    cards = json.loads((HERE/'검사_결과.json').read_text(encoding='utf-8'))['assets']
    selected = {key.replace(':','_').replace('-','_'): row['path'] for key, row in poses.items()}
    sheet = Image.new('RGB', (896, ((len(cards)+3)//4)*320), (56,48,42))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf', 13)
    for index, row in enumerate(cards):
        path = selected.get(row['id'], 'res://'+row['path'])
        image = Image.open(ROOT/path[6:]).convert('RGBA')
        image = image.resize((image.width*2, image.height*2), Image.Resampling.NEAREST)
        x = index%4*224+(224-image.width)//2
        y = index//4*320+270-image.height
        sheet.paste(image, (x,y), image)
        draw.multiline_text((index%4*224+8,index//4*320+276),row['id'].replace('_south_','\nsouth_').replace('_north_','\nnorth_'),font=font,fill=(240,220,190))
    sheet.save(HERE/'게임용_목록.png')


if __name__ == '__main__':
    apply()
