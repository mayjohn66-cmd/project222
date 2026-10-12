"""Install native imagegen backgrounds once, or verify sources and cosmetic profiles read-only."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'data/art/expedition_scene_compositions.json'
RECEIVED = ROOT / 'docs/그림_작업/받은그림/원정_배경'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inputs', type=Path)
    args = parser.parse_args()
    data = json.loads(CONFIG.read_text(encoding='utf-8'))
    profiles = data['profiles']
    if args.inputs:
        rows = json.loads(args.inputs.read_text(encoding='utf-8'))
        assert set(profiles) == {r['region'] for r in rows}
        RECEIVED.mkdir(parents=True, exist_ok=True)
        for row in rows:
            profile = profiles[row['region']]
            source = ROOT / profile['source']
            target = ROOT / profile['background_path'].removeprefix('res://')
            assert not source.exists() and not target.exists(), 'Preserve installed source and background'
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(row['path'], source)
            shutil.copyfile(row['path'], target)
            image = Image.open(target)
            profile.update(sha256=sha(target), source_sha256=sha(source), width=image.width, height=image.height)
        CONFIG.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        (RECEIVED / 'prompts.json').write_text(json.dumps(
            [{'region':r['region'],'prompt':r['prompt']} for r in rows],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    mapping = json.loads((ROOT/'data/art/expedition_environment_assets.json').read_text(encoding='utf-8'))
    known = {r['id'] for r in mapping['assets']}
    for region, profile in profiles.items():
        source = ROOT / profile['source']
        target = ROOT / profile['background_path'].removeprefix('res://')
        image = Image.open(target).convert('RGBA')
        assert sha(source) == profile['source_sha256'] == sha(target) == profile['sha256']
        assert image.size == (profile['width'],profile['height'])
        assert abs(image.width/image.height - 16/9) < .01
        assert image.getchannel('A').getextrema() == (255,255)
        assert len(profile['outside']) + profile['floor_limit'] <= 10
        trail = profile['exit_path']
        assert trail['kind'] in {'dirt','wood','paving'}
        assert 0 < trail['width'] <= 2 and trail['length'] > trail['inside'] > 0
        for i in range(1,4):
            assert (ROOT / f"art/received/floors/{trail['kind']}_{i}.png").is_file()
        for entry in profile['outside'] + profile['floor']:
            key = entry['key']
            assert key in known or key+'_rot0' in known, key
            assert entry['scale'] > 0
        for entry in profile['outside']:
            assert not (0 <= entry['x'] <= 8 and 0 <= entry['y'] <= 8)
            assert not (2.45 <= entry['x'] <= 4.55 and -2.2 <= entry['y'] <= .3)
        print(f"PASS {region}: native {image.width}x{image.height}, unchanged pixels/SHA, cosmetic cap {len(profile['outside'])+profile['floor_limit']}")

if __name__ == '__main__': main()
