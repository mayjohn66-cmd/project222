"""Verify priority-2 candidate pixels, compositions, catalog coverage and unchanged sources.
Run from repo root: python -X utf8 docs/그림_작업/받은그림/진열대_상태/verify_pack.py
This does not validate runtime geometry or Godot integration.
"""
from pathlib import Path
from PIL import Image
import hashlib,json,csv,subprocess
base=Path(__file__).resolve().parent;root=base.parents[3];out=base/"픽셀_정리"
m=json.loads((base/"manifest.json").read_text(encoding="utf-8"))
f=json.loads((out/"frames.json").read_text(encoding="utf-8"))
items=json.loads((out/"items.json").read_text(encoding="utf-8"))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def unchanged(path):
    disk=(root/path).read_bytes()
    committed=subprocess.check_output(["git","show","HEAD:"+path],cwd=root)
    if path.endswith(".csv"):
        # Git's working-tree checkout may use CRLF while its blob uses LF.
        assert disk.replace(b"\r\n",b"\n")==committed.replace(b"\r\n",b"\n"),path
    else:assert disk==committed,path
assert len(f["files"])==372 and len({r["file"] for r in f["files"]})==372
for record in f["files"]:
    p=out/record["file"];im=Image.open(p)
    pixels=list(im.getdata());alphas={v[3] for v in pixels};colors={v[:3] for v in pixels if v[3]}
    assert im.mode=="RGBA" and list(im.size)==record["size"] and im.getbbox(),p
    assert alphas<={0,255} and len(colors)<=record["palette_limit"],p
    assert all(v[:3]==(0,0,0) for v in pixels if not v[3]),p
    assert sha(p)==record["sha256"] and list(im.getbbox())==record["bounds"],p
for record in m["source_assets"]:
    assert sha(base/record["file"])==record["sha256"],record["file"]
for record in m["catalogs"]+m["references"]:
    path=record["path"]
    if path.endswith(".csv"):
        # A subsequent Git checkout can alter line endings, so verify semantic bytes.
        assert hashlib.sha256((root/path).read_bytes().replace(b"\r\n",b"\n")).hexdigest()==record["normalized_sha256"],path
        unchanged(path)
    else:assert sha(root/path)==record["sha256"],path
    unchanged(path)
with (root/"data/shop/catalogs/furniture/shelf_data.csv").open(encoding="utf-8-sig") as stream:
    configs={r["id"]:r for r in csv.DictReader(stream)}
expected={(key,d,stack) for key,row in configs.items() for d in range(4) for stack in range(1,int(row["max_stack_level"])+1)}
actual=set();compositions=0
for row in f["frames"]:
    body=Image.open(out/row["body"])
    if row["build_id"] in configs:
        config=configs[row["build_id"]];actual.add((row["build_id"],row["view"],row["stack"]))
        assert row["slots_per_level"]==int(config["slots_per_level"])
        assert row["slot_capacity"]==int(config["slot_capacity"])
        assert row["max_stack_level"]==int(config["max_stack_level"])
        assert len(row["slot_anchors"])==(row["slots_per_level"]*row["stack"] if row["visible_front"] else 0)
    else:assert row["storage_visible_types"]==3 and row["board_planes"]==4
    for state in ["sparse","full"]:
        data=row[state]
        if not row["visible_front"]:
            assert data["goods_layer"] is None and data["example"]==row["body"];continue
        layer=Image.open(out/data["goods_layer"]);example=Image.open(out/data["example"])
        assert body.size==layer.size==example.size
        result=body.copy();result.alpha_composite(layer)
        assert result.tobytes()==example.tobytes(),data["example"];compositions+=1
        if state=="sparse":assert all(r["stock"]==(1 if idx%2==0 else 0) for idx,r in enumerate(data["sample_stock"]))
        else:assert all(r["stock"]>0 for r in data["sample_stock"])
assert actual==expected and len(actual)==84 and len(f["frames"])==96 and compositions==96
with (root/"data/core/items.csv").open(encoding="utf-8-sig") as stream:
    allowed={r["id"] for r in csv.DictReader(stream) if r["shelf_allowed"]=="true"}
assert {r["item_id"] for r in items["items"]}==allowed and len(allowed)==81
assert len({r["glyph"] for r in items["items"]})==68
assert sum(not r["runtime_icon_connected"] for r in items["items"])==18
for row in items["items"]:
    assert sha(root/row["source"])==row["source_sha256"],row["source"]
    unchanged(row["source"])
    assert (out/row["glyph"]).is_file()
print("SHELF_VERIFY native_pngs=372 bodies=96 composites=96 catalog_cases=84 item_ids=81 glyphs=68 preserved_references=7 failures=0")
