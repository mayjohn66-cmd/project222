"""Reproduce the drawn well sprite; no axis-specific scaling. --install writes selected files."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs/그림_작업/받은그림/우물_다시그림'
SOURCE = DOC / '원본.png'
TARGET = ROOT / 'art/received/village/village_well_drawn.png'


def prepare():
    image = Image.open(SOURCE).convert('RGBA')
    alpha = image.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
    image.putalpha(alpha)
    bounds = alpha.getbbox()
    assert bounds, 'Empty source'
    body = image.crop(bounds)
    # Live player is ~44 screen pixels high; keep the roof close to the previous 99px landmark.
    factor = min(96 / body.width, 112 / body.height)
    size = (round(body.width * factor), round(body.height * factor))
    body = body.resize(size, Image.Resampling.NEAREST)
    alpha = body.getchannel('A')
    body = body.convert('RGB').quantize(colors=64, method=Image.Quantize.MEDIANCUT,
                                       dither=Image.Dither.NONE).convert('RGBA')
    body.putalpha(alpha)
    out = Image.new('RGBA', (128, 192))
    out.alpha_composite(body, ((128-size[0])//2, 152-size[1]))
    return out, {'source_size': list(image.size), 'source_bounds': list(bounds),
                 'uniform_scale': factor, 'selected_body_size': list(size),
                 'canvas': [128,192], 'anchor': [64,128], 'ground_front_y': 152,
                 'palette_limit': 64, 'alpha_threshold': 128, 'filter': 'NEAREST'}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--install', action='store_true')
    args = ap.parse_args()
    image, recipe = prepare()
    if args.install:
        image.save(TARGET)
        recipe.update(source=SOURCE.relative_to(ROOT).as_posix(),
                      path='res://'+TARGET.relative_to(ROOT).as_posix(),
                      source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                      sha256=hashlib.sha256(TARGET.read_bytes()).hexdigest(),
                      colors=len({p for p in image.get_flattened_data() if p[3]}))
        (DOC/'선택_기록.json').write_text(json.dumps(recipe,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        image.resize((512,768),Image.Resampling.NEAREST).save(DOC/'게임용_4배.png')
    else:
        selected = Image.open(TARGET).convert('RGBA')
        assert image.size == selected.size and image.tobytes() == selected.tobytes(), 'Selected sprite changed'
        recipe = json.loads((DOC/'선택_기록.json').read_text(encoding='utf-8'))
        assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == recipe['source_sha256']
        assert hashlib.sha256(TARGET.read_bytes()).hexdigest() == recipe['sha256']
    print('Drawn well: source preserved, uniform scale, 128x192, <=64 colors, binary alpha, reproducible')


if __name__ == '__main__':
    main()
