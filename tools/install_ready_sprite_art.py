"""선택된 원정·낚시 그림을 재현/검사한다. 기본은 읽기 전용, --install은 실행 경로 복원.

python tools/install_ready_sprite_art.py [--install]
팔레트가 32색을 넘는 낚시 아이콘 3장만 원본 색 중 빈도가 높은 32색으로 정리한다.
캔버스/좌표/알파/형태는 그대로이며 받은 원본은 수정하지 않는다.
"""
from pathlib import Path
from collections import Counter
from io import BytesIO
import argparse
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def selected_bytes(row):
    source = ROOT / row['source']
    raw = source.read_bytes()
    if digest(raw) != row['source_sha256']:
        raise ValueError('받은 원본 변경: ' + row['id'])
    if 'palette_cleanup' not in row:
        return raw
    image = Image.open(BytesIO(raw)).convert('RGBA')
    pixels = list(image.getdata())
    colors = Counter(pixel[:3] for pixel in pixels if pixel[3])
    palette = [color for color, count in colors.most_common(32)]
    mapped = {color: min(palette, key=lambda target: sum((a-b)**2 for a,b in zip(color,target))) for color in colors}
    image.putdata([(*mapped[pixel[:3]], pixel[3]) if pixel[3] else pixel for pixel in pixels])
    output = BytesIO()
    image.save(output, format='PNG')
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    rows = []
    for name in ['expedition_sprite_assets', 'fishing_item_assets']:
        rows += json.loads((ROOT / f'data/art/{name}.json').read_text(encoding='utf-8'))['assets']
    for row in rows:
        path = ROOT / row['path'].removeprefix('res://')
        if not path.resolve().is_relative_to(ROOT / 'art'):
            raise ValueError('실행 그림 경로가 art 밖임: ' + str(path))
        raw = selected_bytes(row)
        if digest(raw) != row['sha256']:
            raise ValueError('선택본 재현 불일치: ' + row['id'])
        if args.install:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        if digest(path.read_bytes()) != row['sha256']:
            raise ValueError('실행 그림 불일치: ' + row['id'])
    print(f'PASS: {len(rows)} selected drawings and original hashes')


if __name__ == '__main__':
    main()
