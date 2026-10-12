"""생성 원본에서 기록된 프레임을 분리한다. 기본은 검사, --write는 연결 PNG 갱신."""
from pathlib import Path
from PIL import Image
import argparse, hashlib, json

parser = argparse.ArgumentParser()
parser.add_argument('--write', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent
repo = root.parents[3]
manifest = json.loads((root/'제작_목록.json').read_text(encoding='utf-8'))
source = root/'생성_원본.png'
assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest['source_sha256']
image = Image.open(source).convert('RGBA')
for frame in manifest['frames']:
    output = image.crop(frame['source_rect']).resize(frame['size'], Image.Resampling.NEAREST).convert('RGB')
    output = output.quantize(colors=16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGBA')
    target = repo/'art/ui/controls'/(frame['id']+'.png')
    if args.write:
        output.save(target)
        output.save(root/target.name)
    current = Image.open(target).convert('RGBA')
    assert current.size == output.size and current.tobytes() == output.tobytes(), frame['id']
    assert hashlib.sha256(target.read_bytes()).hexdigest() == frame['sha256'], frame['id']
print('CONTROL_ART: 12 frames match generated source and manifest')
