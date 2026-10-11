"""Normalize approved imagegen digits to transparent 12x16 PNGs; keep received originals.

Usage: python tools/prepare_damage_digits.py --inputs /path/to/damage-digit-inputs.json
Without --inputs, verify/reproduce the installed set from the recorded received sources.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RECEIVED = ROOT / 'docs/그림_작업/받은그림/피해_숫자'
ART = ROOT / 'art/ui/damage_digits'
MANIFEST = ROOT / 'data/art/damage_digit_assets.json'
PALETTE = [(51, 34, 28), (233, 183, 101), (255, 244, 207)]

def normalize(path):
    image = Image.open(path).convert('RGBA')
    alpha = image.getchannel('A').point(lambda value: 255 if value >= 128 else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f'Empty numeral: {path}')
    image = image.crop(bounds)
    factor = min(10 / image.width, 14 / image.height)
    target = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
    image = image.resize(target, Image.Resampling.NEAREST)
    pixels = []
    for r, g, b, a in image.get_flattened_data():
        if a < 128:
            pixels.append((0, 0, 0, 0))
        else:
            color = min(PALETTE, key=lambda rgb: sum((v - w) ** 2 for v, w in zip(rgb, (r, g, b))))
            pixels.append((*color, 255))
    image.putdata(pixels)
    canvas = Image.new('RGBA', (12, 16))
    canvas.alpha_composite(image, ((12 - image.width) // 2, 15 - image.height))
    return canvas

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inputs', type=Path)
    args = parser.parse_args()
    installing = args.inputs is not None
    if installing:
        incoming = json.loads(args.inputs.read_text(encoding='utf-8'))['sources']
        assert [row['digit'] for row in incoming] == list(range(10))
        RECEIVED.mkdir(parents=True, exist_ok=True)
        ART.mkdir(parents=True, exist_ok=True)
        for row in incoming:
            destination = RECEIVED / f"digit_{row['digit']}_received.png"
            assert not destination.exists(), f'Received source already exists: {destination}'
            shutil.copyfile(row['path'], destination)
        (RECEIVED / 'prompts.json').write_text(json.dumps(
            [{'digit': row['digit'], 'prompt': row['prompt']} for row in incoming],
            ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    rows = []
    preview = Image.new('RGBA', (640, 104), (45, 35, 29, 255))
    for digit in range(10):
        source = RECEIVED / f'digit_{digit}_received.png'
        target = ART / f'digit_{digit}.png'
        image = normalize(source)
        if installing:
            image.save(target)
        else:
            assert Image.open(target).convert('RGBA').tobytes() == image.tobytes(), f'Non-reproducible digit {digit}'
        assert set(image.getchannel('A').get_flattened_data()) == {0, 255}
        assert not image.getbbox() is None
        preview.alpha_composite(image.resize((48, 64), Image.Resampling.NEAREST), (8 + digit * 64, 20))
        rows.append({'id': str(digit), 'path': 'res://' + target.relative_to(ROOT).as_posix(),
            'source': source.relative_to(ROOT).as_posix(), 'sha256': sha(target), 'source_sha256': sha(source),
            'width': 12, 'height': 16})
    if installing:
        preview.save(RECEIVED / '숫자_비교.png')
        MANIFEST.write_text(json.dumps({'palette': PALETTE, 'assets': rows}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    else:
        assert json.loads(MANIFEST.read_text(encoding='utf-8'))['assets'] == rows
    print('PASS: 10 individual 12x16 digit PNGs, binary alpha, shared 3-color palette, sources/hash/reproduction.')

if __name__ == '__main__':
    main()
