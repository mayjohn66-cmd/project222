"""사용자가 승인한 원본 픽셀 합성. 파일을 덮어쓰지 않고 기본 얼굴을 공통 레이어로 사용한다."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, hashlib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/그림_작업/받은그림/초상화/주인공_후보"
OUTPUT = SOURCE / "표정_픽셀보정"
EXPRESSIONS = ["neutral","smile","flustered","surprised","worried","tired","determined"]
SPEC = {
 "male": {
  "base":"male_B_1x.png", "eyes":[(30,30,39,37),(44,30,53,37)], "nose":(37,36,42,40),
  "brows":[(31,27,36,30),(45,27,51,30)], "mouth_clear":(34,40,47,46), "mouth_center":(40,43),
  "donor_eyes":{
   "smile":[(27,28,36,35),(44,28,53,35)],
   "flustered":[(28,29,37,36),(44,29,53,36)],
   "surprised":[(27,28,36,36),(43,28,52,36)],
   "worried":[(29,30,38,37),(44,30,53,37)],
   "tired":[(28,30,37,37),(44,30,53,37)],
   "determined":[(29,29,38,36),(45,29,54,36)]},
  "donor_mouth":{
   "smile":((35,40,45,46),(9,5)),
   "flustered":((35,40,47,46),(9,4)),
   "surprised":((34,39,45,48),(7,6)),
   "worried":((35,40,45,44),(9,3)),
   "tired":((37,40,44,44),(7,3)),
   "determined":((36,40,47,44),(9,3))},
  "cheeks":[(29,36,35,39),(45,36,50,39)]},
 "female": {
  "base":"female_C_1x.png", "eyes":[(25,29,33,36),(41,29,50,36)], "nose":(32,35,37,40),
  "brows":[(27,26,33,29),(42,26,49,29)], "mouth_clear":(30,40,44,46), "mouth_center":(36,43),
  "donor_eyes":{
   "smile":[(26,29,34,36),(42,29,51,36)],
   "flustered":[(26,29,34,36),(42,29,51,36)],
   "surprised":[(25,29,33,37),(42,29,50,37)],
   "worried":[(27,30,35,37),(43,30,51,37)],
   "tired":[(27,29,35,36),(43,29,52,36)],
   "determined":[(26,29,34,36),(42,29,51,36)]},
  "donor_mouth":{
   "smile":((32,40,44,47),(9,5)),
   "flustered":((32,42,45,46),(10,3)),
   "surprised":((33,42,42,47),(7,5)),
   "worried":((32,42,44,46),(10,3)),
   "tired":((32,42,43,47),(9,4)),
   "determined":((33,43,44,46),(9,3))},
  "cheeks":[(27,36,31,40),(43,36,47,40)]}
}

def within(box, x, y):
 return box[0] <= x < box[2] and box[1] <= y < box[3]

def compose(base, donor, spec, expression):
 result = base.copy()
 mask = Image.new("L",base.size,0)
 palette = sorted(set(base.get_flattened_data()) - {p for p in base.get_flattened_data() if p[3] == 0})
 cache = {}
 def nearest(pixel):
  if pixel not in cache:
   cache[pixel] = min(palette,key=lambda c:sum((c[i]-pixel[i])**2 for i in range(3)))
  return cache[pixel]
 def put(x,y,pixel,protect_hair=False):
  old = base.getpixel((x,y))
  if old[3] == 0 or pixel[3] < 128 or within(spec["nose"],x,y):
   return
  # Lock bangs along the upper edge, even when a generated eyebrow overlaps them.
  if protect_hair and max(old[:3]) < 140:
   return
  result.putpixel((x,y),nearest(pixel))
  mask.putpixel((x,y),255)
 for target, source in zip(spec["eyes"],spec["donor_eyes"][expression]):
  patch = donor.crop(source).resize((target[2]-target[0],target[3]-target[1]),Image.Resampling.NEAREST)
  for py in range(patch.height):
   for px in range(patch.width):
    x,y=target[0]+px,target[1]+py
    if spec["base"].startswith("female"):
     # Eye contours only: lock the fringe at x32/y29 and the right hair edge.
     if (x == 32 and y == 29) or (x == 49 and y >= 34):
      continue
     put(x,y,patch.getpixel((px,py)))
    else:
     if (x == 30 and y < 32) or x == 52:
      continue
     put(x,y,patch.getpixel((px,py)))
 for target, source in zip(spec["brows"],spec["donor_eyes"][expression]):
  patch = donor.crop((source[0],source[1]-3,source[2],source[1])).resize((target[2]-target[0],target[3]-target[1]),Image.Resampling.NEAREST)
  for py in range(patch.height):
   for px in range(patch.width):
    put(target[0]+px,target[1]+py,patch.getpixel((px,py)),True)
 # Erase only the neutral mouth's pink marks, using adjacent original skin.
 clear=spec["mouth_clear"]
 for y in range(clear[1],clear[3]):
  for x in range(clear[0],clear[2]):
   color=base.getpixel((x,y))
   if color[3] and color[0] > 150 and color[0] > color[1]*1.2 and color[1] < 195:
    skin=base.getpixel((x,clear[1]-1))
    if skin[0] > 220 and skin[1] > 190:
     put(x,y,skin)
 source,size=spec["donor_mouth"][expression]
 patch=donor.crop(source).resize(size,Image.Resampling.NEAREST)
 start=(spec["mouth_center"][0]-size[0]//2,spec["mouth_center"][1]-size[1]//2)
 for py in range(patch.height):
  for px in range(patch.width):
   put(start[0]+px,start[1]+py,patch.getpixel((px,py)))
 if expression == "flustered":
  # Original blush shade; fixed cheeks without moving facial structure.
  pink = nearest((218,142,146,255))
  for box in spec["cheeks"]:
   for y in range(box[1],box[3]):
    for x in range(box[0],box[2]):
     c=base.getpixel((x,y))
     if c[0] > 220 and c[1] > 185:
      put(x,y,pink)
 return result,mask

def main():
 source_files=[SOURCE/spec["base"] for spec in SPEC.values()]
 source_files += [SOURCE/"표정_inpaint"/f"{gender}_{expression}_1x.png"
                  for gender in SPEC for expression in EXPRESSIONS[1:]]
 source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}
 OUTPUT.mkdir(parents=True,exist_ok=True)
 sheet=Image.new("RGB",(1192,460),(58,46,36))
 draw=ImageDraw.Draw(sheet)
 font=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",14)
 report=[]
 for row,(gender,spec) in enumerate(SPEC.items()):
  base=Image.open(SOURCE/spec["base"]).convert("RGBA")
  assert base.size == (80,96), "unexpected neutral dimensions"
  permitted=Image.new("L",base.size,0)
  allowed_draw=ImageDraw.Draw(permitted)
  for box in spec["eyes"]+spec["brows"]+spec["cheeks"]+[spec["mouth_clear"]]:
   allowed_draw.rectangle((box[0],box[1],box[2]-1,box[3]-1),fill=255)
  for col,expression in enumerate(EXPRESSIONS):
   result=base.copy();mask=Image.new("L",base.size,0)
   if expression != "neutral":
    donor=Image.open(SOURCE/"표정_inpaint"/f"{gender}_{expression}_1x.png").convert("RGBA")
    assert donor.size == base.size, "unexpected expression dimensions"
    result,mask=compose(base,donor,spec,expression)
   delta=0
   for y in range(base.height):
    for x in range(base.width):
     a,b=base.getpixel((x,y)),result.getpixel((x,y))
     assert a[3]==b[3], "alpha silhouette changed"
     if a != b:
      assert mask.getpixel((x,y)), "pixel changed outside permitted mask"
      assert permitted.getpixel((x,y)), "pixel changed outside fixed feature regions"
      assert not within(spec["nose"],x,y), "nose changed"
      delta+=1
   assert set(result.get_flattened_data()) <= set(base.get_flattened_data()), "palette expanded"
   path=OUTPUT/f"player_{gender}_{expression}_1x.png"
   result.save(path)
   enlarged=result.resize((160,192),Image.Resampling.NEAREST)
   assert enlarged.resize(base.size,Image.Resampling.NEAREST).tobytes() == result.tobytes(), "scaling mismatch"
   for y in range(result.height):
    for x in range(result.width):
     assert all(enlarged.getpixel((2*x+dx,2*y+dy)) == result.getpixel((x,y))
                for dx in (0,1) for dy in (0,1)), "non-integer pixel scaling"
   enlarged.save(OUTPUT/f"player_{gender}_{expression}.png")
   x=8+col*168;y=32+row*220
   sheet.paste(enlarged,(x,y),enlarged)
   draw.text((x,10+row*220),("남" if gender=="male" else "여")+" "+expression,fill=(212,191,155),font=font)
   if expression!="neutral":
    mask.save(OUTPUT/f"mask_{gender}_{expression}.png")
   report.append({"gender":gender,"expression":expression,"changed_pixels":delta,"outside_mask_changes":0,"outside_feature_regions_changes":0,"nose_changes":0,"alpha_changes":0,"palette_expansion":0,"nearest_2x":True})
 sheet.save(OUTPUT/"_표정_픽셀보정.png")
 assert all(hashlib.sha256(p.read_bytes()).hexdigest() == source_hashes[str(p.relative_to(ROOT))]
            for p in source_files), "source file changed"
 (OUTPUT/"pixel_integrity.json").write_text(json.dumps({"spec":SPEC,"source_sha256":source_hashes,"source_files_changed":0,"checks":report},ensure_ascii=False,indent=2),encoding="utf-8")
 print(json.dumps(report))
if __name__=="__main__":
 main()
