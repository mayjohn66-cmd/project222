#!/usr/bin/env python3
"""그림 요청 문서·시트 생성기. Godot 의 art_request_export.tscn 이 만든 assets.json + 면 질감 틀 PNG 로부터
  docs/그림_작업/00_먼저읽기.md   (사용법 + 진행 현황 + 자산 목록, 가장 먼저 열 파일)
  docs/그림_작업/요청서.md        (자산별 요청서: 면 표, 크기, 영문 프롬프트)
  docs/그림_작업/faces.csv        (면 목록: 파일명, 크기, 반복 여부, 법선 필요, 설명, 영문 프롬프트)
  docs/그림_작업/시트/<id>.png    (미리보기 + 2D 원본 + 면 틀을 나란히 놓은 한 장 요약)
폴더는 이 한 곳만 보면 된다: 시트/ (자산별 요약 그림), 지시/ (Pixel Lab 작업 지시), 받은그림/ (결과 임시 보관), 틀/ (면 질감 틀 PNG, 평평하게 <id>__<면>.png).
을 만든다.

사용:
  godot --path . res://dev/spike3d/art_request_export.tscn      (xvfb 필요한 환경이면 xvfb-run)  → docs/그림_작업/ 에 틀 PNG/JSON
  python tools/art/build_art_request_doc.py                          → 문서·CSV·시트
Pillow 만 필요하다.
"""
import csv
import json
import os
import sys

# Windows 한국어 환경(cp949)에서 한글·기호 출력 시 UnicodeEncodeError 로 멈추지 않게 한다.
for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "docs", "그림_작업")
TEMPLATES = os.path.join(ART, "틀")
SHEETS = os.path.join(ART, "시트")
DOC = os.path.join(ART, "요청서.md")
README = os.path.join(ART, "00_먼저읽기.md")

COMMON = "pixel art texture, flat unlit colors, no outline, no cast shadows, no baked lighting, limited palette 8-12 colors, crisp single pixels, nearest-neighbor, {w}x{h} pixels"

# 면 이름 → 영문 설명 {rc} = 지붕 색, {wc} = 벽 색, {ac} = 차양 색
PHRASE = {
    "wall_front": "front wall of a small medieval village building seen straight-on, plaster color {wc}, dark brown timber frame beams, one wooden door at the center, small windows with white frames and blue glass at the layout positions of the template, grey stone foundation strip at the bottom",
    "wall_side": "side wall of a small medieval village building seen straight-on, plaster color {wc}, dark brown timber frame beams, small windows with blue glass at the layout positions of the template, grey stone foundation strip at the bottom",
    "roof_tiles": "seamless clay roof tiles texture, color {rc}, overlapping rounded tile rows with darker gaps",
    "gable_wall": "seamless plaster wall texture color {wc} with faint timber beam, small repeating tile",
    "roof_trim": "seamless dark wood or dark roof tile trim texture, darker version of {rc}",
    "chimney_stone": "seamless grey stone brick chimney texture with dark mortar lines",
    "awning": "seamless vertical striped cloth awning texture, cream and {ac} stripes",
    "step": "seamless light grey stone step texture",
    "planter_box": "seamless wooden planter box texture, brown planks",
    "planter_flowers": "seamless flowers and leaves texture seen from above and side, green leaves with pink flower dots",
    "sign_bracket": "dark wood bracket texture, flat brown",
    "sign_board": "small hanging shop sign: wooden board with dark frame and a simple white symbol",
    "apron_stone": "seamless light stone paving texture seen from above, grey stone slabs with dark joints",
    "barrel": "wooden barrel side texture: vertical brown planks with two dark iron hoops",
    "crate": "wooden crate texture: planks with dark corner frame and diagonal cross brace",
    "sack": "seamless beige cloth sack texture",
    "hay": "seamless yellow straw hay texture",
    "bush": "seamless green bush leaves texture with small pink flower dots",
    "bark": "seamless dark brown tree bark texture, vertical grooves",
    "tree_foliage": "seamless apple tree leaves texture: dark green leaves with lighter highlights and small red apples",
    "well_stone": "seamless grey stone block texture with dark mortar lines",
    "well_water": "flat dark blue water color texture with tiny lighter pixels",
    "stall_counter": "seamless brown wooden counter planks texture",
    "stall_awning": "seamless vertical striped market awning cloth, cream and {rc} stripes",
    "stall_goods": "seamless texture of market goods (bread, fish, cloth rolls or herbs depending on the stall) as colored dots",
    "low_wall_stone": "seamless grey stone wall texture with dark mortar lines",
    "low_wall_cap": "seamless lighter grey stone cap texture",
    "cart_bed": "seamless brown wooden cart planks texture",
    "cart_side": "seamless dark brown wooden planks texture",
    "cart_handle": "dark brown wooden handle texture",
    "iron": "flat dark iron color texture",
    "noticeboard_face": "village notice board face: cork brown background with several cream paper notes pinned",
    "small_roof_tiles": "seamless small roof tile texture, color {rc}",
    "bench_wood": "seamless brown wooden bench planks texture",
    "lantern_glass": "flat warm yellow lantern glass color texture (will glow at night)",
    "flower_bush": "seamless green bush with pink flowers texture",
    "road_sign_board": "wooden road sign board: brown planks, dark border, white arrow pointing right",
    "fence_wood": "seamless light brown wooden fence planks texture",
    "plinth_stone": "seamless grey stone foundation block texture, three-tone blocks with dark mortar lines",
    "shutter_wood": "seamless window shutter wood texture, green-painted vertical planks",
    "wood": "seamless brown wood planks texture",
    "stone": "seamless grey stone texture",
}


def hexs(v):
    return "#" + str(v).lstrip("#")


def prompt_for(face, asset):
    base = PHRASE.get(face["name"], "texture for %s" % face["name"])
    base = base.format(rc=hexs(asset["roof_tint"]), wc=hexs(asset["tint"]), ac=hexs(asset["awning_tint"]))
    return (base + ", " + COMMON).format(w=face["w"], h=face["h"])


def _font(size):
    for cand in ("/usr/share/fonts/truetype/nanum/NanumGothic.ttf", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", "C:/Windows/Fonts/malgun.ttf", "/System/Library/Fonts/AppleSDGothicNeo.ttc"):
        if os.path.exists(cand):
            try:
                return ImageFont.truetype(cand, size)
            except OSError:
                pass
    return ImageFont.load_default()


def make_sheet(asset):
    """미리보기 + 2D 원본 참고 + 면 틀(4배 확대)을 한 장에."""
    preview = Image.open(os.path.join(TEMPLATES, "%s__preview.png" % asset["id"])).convert("RGB")
    ref_path = os.path.join(ROOT, asset["sprite"].replace("res://", ""))  # 2D 원본(art/ 에 있는 것을 그대로 읽음, 복사하지 않음)
    pad = 10
    tiles = []
    for fc in asset["faces"]:
        im = Image.open(os.path.join(TEMPLATES, fc["file"])).convert("RGBA")
        scale = 4 if max(im.size) <= 64 else 3
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        tiles.append((fc, im))
    row_h = max([t[1].height for t in tiles] + [20]) + 30
    cols = 4
    tile_w = max([t[1].width for t in tiles] + [60]) + pad
    rows = (len(tiles) + cols - 1) // cols
    top_h = preview.height
    ref = None
    if os.path.exists(ref_path):
        ref = Image.open(ref_path).convert("RGBA")
        ratio = top_h / ref.height
        ref = ref.resize((max(1, int(ref.width * ratio)), top_h), Image.LANCZOS)
    width = max(preview.width + (ref.width + pad if ref else 0), cols * tile_w) + pad * 2
    sheet = Image.new("RGB", (width, top_h + pad * 3 + rows * row_h + 24), (36, 36, 40))
    d = ImageDraw.Draw(sheet)
    f = _font(13)
    d.text((pad, 3), "%s (%s)  size %.1f x %.1f cells / height %.1f blocks   [left: 3D preview, right: 2D original]" % (asset["label"], asset["id"], asset["canon_w"], asset["canon_d"], asset["total_blocks"]), fill=(255, 255, 255), font=f)
    sheet.paste(preview, (pad, 20))
    if ref:
        bg = Image.new("RGB", ref.size, (60, 70, 60))
        bg.paste(ref, (0, 0), ref)
        sheet.paste(bg, (preview.width + pad * 2, 20))
    y0 = top_h + 40
    for i, (fc, im) in enumerate(tiles):
        x = pad + (i % cols) * tile_w
        y = y0 + (i // cols) * row_h
        bg = Image.new("RGB", im.size, (90, 90, 96))
        bg.paste(im, (0, 0), im)
        sheet.paste(bg, (x, y))
        d.text((x, y + im.height + 2), "%s %dx%d" % (fc["name"], fc["w"], fc["h"]), fill=(230, 230, 230), font=f)
    os.makedirs(SHEETS, exist_ok=True)
    sheet.save(os.path.join(SHEETS, "%s.png" % asset["id"]))


def write_readme(assets, rows):
    """00_먼저읽기.md — 가장 먼저 열 한 장: 쓰는 법, 폴더 안내, 자산별 진행 현황과 시트 링크."""
    real_dir = os.path.join(ROOT, "art", "world3d")
    done_by = {}
    for r in rows:
        done_by.setdefault(r["asset"], [0, 0])
        done_by[r["asset"]][1] += 1
        if os.path.exists(os.path.join(real_dir, r["asset"], r["face"] + ".png")):
            done_by[r["asset"]][0] += 1
    total_done = sum(v[0] for v in done_by.values())
    total = sum(v[1] for v in done_by.values())
    L = []
    A = L.append
    A("# 3D 마을 그림 작업 — 먼저 읽기")
    A("")
    A("> 자동 생성 파일(`tools/art/build_art_request_doc.py`). 직접 고치지 말 것. 진행 현황은 이 파일을 다시 만들 때 갱신된다.")
    A("")
    A("## 한 줄 사용법")
    A("")
    A("1. PC 터미널에서 `tools\\art\\run_world3d.bat` (또는 `python tools/art/world3d_menu.py`) 실행.")
    A("2. **6번 「Pixel Lab 으로 만들기」** → 자산 선택 → PC 의 Claude Code 가 Pixel Lab MCP 로 한 면씩 만들어 보여 줌.")
    A("3. 마음에 들면 3번 「그림 넣기」(또는 Claude Code 가 `tools/art/ingest_world3d.py` 실행) → Godot 한 번 열기 → 4번 「가져오기 설정·검증」 → 게임에서 **F8**.")
    A("")
    A("## 폴더 (이 폴더 `docs/그림_작업/` 하나만 보면 됨)")
    A("")
    A("| 이름 | 용도 |")
    A("|---|---|")
    A("| `시트/<자산id>.png` | **자산별 한 장 요약**: 3D 미리보기 + 2D 원본 + 면 질감 틀과 크기. 어떤 그림이 필요한지 눈으로 볼 때 이것만 열면 됨 |")
    A("| `요청서.md` | 자산별 면 표(크기·반복·법선·영문 프롬프트), 공통 규칙 |")
    A("| `지시/<자산id>.md` | Pixel Lab 작업 지시(메뉴 6번이 만듦) |")
    A("| `받은그림/<자산id>/` | Pixel Lab 결과 임시 보관(확인 후 넣음) |")
    A("| `틀/` | 면 질감 틀 PNG(임시 그림, 정확한 크기). 평평하게 `<자산id>__<면>.png` |")
    A("| `faces.csv`, `assets.json` | 도구가 읽는 표 |")
    A("")
    A("최종 그림이 들어가는 곳: `art/world3d/<자산id>/<면>.png` (게임이 자동으로 읽음).")
    A("")
    A("## 진행 현황 (실제 그림이 들어온 면 / 전체 면): %d / %d" % (total_done, total))
    A("")
    A("| 자산 | 이름 | 진행 | 시트 |")
    A("|---|---|---|---|")
    order = ["moss_cottage", "red_house", "bakery", "tool_shop", "blacksmith", "ochre_townhouse", "stable", "granary"]
    ids = [a["id"] for a in assets]
    ids.sort(key=lambda i: (order.index(i) if i in order else 99, i))
    labels = {a["id"]: a["label"] for a in assets}
    for i in ids:
        d, t = done_by.get(i, [0, 0])
        A("| `%s` | %s | %d / %d | [시트](시트/%s.png) |" % (i, labels[i], d, t, i))
    A("")
    A("요청 순서 제안: 이끼 오두막 → 나머지 건물 → 개수 많은 소품(사과나무·꽃 덤불·가로등·울타리).")
    open(README, "w", encoding="utf-8").write("\n".join(L) + "\n")


def main():
    path = os.path.join(ART, "assets.json")
    if not os.path.exists(path):
        sys.exit("assets.json 이 없음: 먼저 Godot 에서 art_request_export.tscn 을 실행하세요.")
    assets = json.load(open(path, encoding="utf-8"))

    rows = []
    for a in assets:
        make_sheet(a)
        for fc in a["faces"]:
            rows.append({
                "asset": a["id"], "asset_label": a["label"], "face": fc["name"], "file": "틀/%s" % fc["file"],
                "width": fc["w"], "height": fc["h"], "repeat": "반복(이음매 없이)" if fc["tileable"] else "한 장(면 전체)",
                "normal_map": "틀/%s" % fc["normal_file"] if fc["normal_file"] else "선택", "note": fc["note"],
                "prompt_en": prompt_for(fc, a),
            })
    with open(os.path.join(ART, "faces.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    # ---------------- 문서
    buildings = [a for a in assets if a["group"] == "building"]
    props = [a for a in assets if a["group"] == "prop"]
    unique_names = {}
    for r in rows:
        unique_names.setdefault(r["face"], []).append(r["asset"])
    lines = []
    A = lines.append
    A("# 그림 요청 — 3D 마을 건물·소품 (자동 생성)")
    A("")
    A("> 이 문서는 `tools/art/build_art_request_doc.py` 가 만든다. 직접 고치지 말고 `data/shop/catalogs/village_3d.csv`·`village_3d_assets.csv` 를 고친 뒤 다시 생성한다.")
    A("> 폴더는 `docs/그림_작업/` 하나만 보면 된다: **`시트/<자산id>.png`**(자산별 한 장 요약: 3D 미리보기 + 2D 원본 + 면 틀과 크기), `틀/`(면 질감 틀 PNG, 평평하게 `<자산id>__<면>.png`), `지시/`(Pixel Lab 작업 지시 `<자산id>.md`), `받은그림/<자산id>/`(결과 임시 보관). 2D 원본은 각 자산의 `art/…` 경로에 있다.")
    A("")
    A("> **터미널 도우미**: `python tools/art/world3d_menu.py` (Windows: `tools\\art\\run_world3d.bat`) — 진행 현황, 다음에 그릴 면의 크기·프롬프트(클립보드 복사), 그림 넣기, 가져오기 설정·검증, 그리고 **6번 「Pixel Lab 으로 만들기」**(자산 하나의 작업 지시 파일 TASK.md 를 만들고, Pixel Lab MCP 가 연결된 PC 의 Claude Code `claude` 를 그 지시와 함께 실행)를 번호 메뉴로 진행한다.")
    A("")
    A("## 0. 한눈에")
    A("")
    A("- 자산 %d종(건물 %d, 소품 %d), 면 질감 틀 총 %d장(자산별 중복 포함)." % (len(assets), len(buildings), len(props), len(rows)))
    A("- 면 이름이 같은 것(예: `crate`, `barrel`, `wood`)은 **한 번만 그려서 여러 자산이 같이 써도 된다**(아래 5장 공용 면 목록).")
    A("- 지금 질감은 모두 코드로 칠한 임시 그림이라, 같은 크기·같은 배치로 새로 그리면 그대로 교체된다.")
    A("")
    A("## 1. 공통 규칙 (그림 담당 전달)")
    A("")
    A("1. **크기는 틀 PNG 와 같게**: 틀 크기가 곧 최종 크기다. 확대·축소하지 않는다(도트 한 칸 = 낮은 해상도 한 픽셀, 게임이 3배로 키운다).")
    A("2. **그림에 외곽선·그림자·빛을 넣지 않는다**: 윤곽선은 게임이 후처리로 그리고, 밝고 어두움·그림자는 게임의 빛이 만든다(낮/밤이 바뀜). 그림은 \"빛이 없을 때의 색\"을 평평하게 칠한다. 벽돌 줄눈·나무결·창틀 같은 **안쪽 선**은 그려도 된다.")
    A("3. **알파(투명)는 쓰지 않는다**: 모든 면은 불투명.")
    A("4. **색**: 한 장 8~12색, 같은 자산의 면끼리 팔레트를 공유(예: 빵집의 벽·기단·창틀 색).")
    A("5. **반복(이음매) 면**: 표에서 \"반복\"인 면은 위아래·좌우가 이어져야 한다(가장자리를 맞춘다).")
    A("6. **법선 맵**(`_n` 접미): 지붕 기와는 필수 규격이 있다(기와 한 장 한 장의 불룩함). Pixel Lab 이 법선 맵을 못 내면 **높이 맵(회색조, 밝을수록 높음)** 을 같은 크기로 주면 `tools/art/height_to_normal.py` 로 변환한다. 다른 면은 선택.")
    A("7. **파일 이름·위치**: `art/world3d/<자산id>/<면이름>.png`(알베도), `<면이름>_n.png`(법선 맵). 면 이름은 아래 표의 이름 그대로. **넣는 법**: `python tools/art/ingest_world3d.py <자산id> <그림 파일 또는 폴더>`(파일 이름은 `<면이름>.png` 또는 `<자산id>__<면이름>.png`) — 크기·불투명·색 수를 검사하고 위 위치에 넣어 준다(`--resize` 로 최근접 크기 맞춤).")
    A("8. 넣은 뒤: Godot 를 한 번 열어 `.import` 를 만들고 `python tools/art/fix_texture_import.py` 로 무손실 설정을 맞춘 다음 `python tools/art/validate_assets.py .` 로 검증. 게임(`dev/spike3d/game_3d_view.tscn`)에서는 **F8** 로 새 그림을 다시 읽는다. 그림이 없는 면은 임시 질감이 계속 쓰이므로 **면 하나씩 넣어도 된다**.")
    A("")
    A("공통 영문 문구(프롬프트 끝에 붙임): `%s`" % COMMON)
    A("")

    def asset_section(a, idx):
        out = []
        out.append("### %s. %s (`%s`)" % (idx, a["label"], a["id"]))
        out.append("")
        out.append("- 용도: %s" % a["notes"])
        out.append("- 기준 크기: **%.1f × %.1f 칸**, 높이 약 %.1f 블록(1블록 = 낮은 해상도 22px). 2D 원본 그림: `%s`" % (a["canon_w"], a["canon_d"], a["total_blocks"], a["sprite"]))
        out.append("- 시트: `docs/그림_작업/시트/%s.png`" % a["id"])
        out.append("")
        out.append("| 면 | 크기(px) | 반복 | 법선 맵 | 설명 | 영문 프롬프트 |")
        out.append("|---|---|---|---|---|---|")
        for fc in a["faces"]:
            out.append("| `%s` | %d×%d | %s | %s | %s | %s |" % (fc["name"], fc["w"], fc["h"], "반복" if fc["tileable"] else "한 장", "필수" if fc["normal_file"] else "선택", fc["note"].replace("|", "/"), prompt_for(fc, a).replace("|", "/")))
        out.append("")
        return out

    A("## 2. 건물 (우선 요청)")
    A("")
    for i, a in enumerate(buildings, 1):
        lines.extend(asset_section(a, "2.%d" % i))
    A("## 3. 소품")
    A("")
    for i, a in enumerate(props, 1):
        lines.extend(asset_section(a, "3.%d" % i))
    A("## 4. 요청 순서 제안")
    A("")
    A("1. **이끼 오두막**(마을에 가장 많이 놓임) → 벽 앞·옆, 지붕 기와(+법선), 굴뚝 돌, 박공 벽, 지붕 두께 — 한 건물 완성본으로 \"그림이 들어간 3D 마을\" 느낌을 먼저 확인.")
    A("2. 다른 건물 7종(빵집·대장간·도구점 등): 벽 앞·옆과 지붕 색만 새로 그리면 되고, 굴뚝·기단·마당 등은 위에서 만든 것을 재사용.")
    A("3. 소품: 사과나무·꽃 덤불·가로등·울타리처럼 개수가 많은 것부터.")
    A("")
    A("## 5. 공용 면 목록 (이름이 같은 면은 한 번만 그림)")
    A("")
    A("| 면 이름 | 쓰이는 자산 수 | 자산 |")
    A("|---|---|---|")
    for name, users in sorted(unique_names.items(), key=lambda kv: -len(kv[1])):
        uniq = sorted(set(users))
        A("| `%s` | %d | %s |" % (name, len(uniq), ", ".join(uniq)))
    A("")
    A("> 같은 이름이어도 크기가 자산마다 다른 면(`wall_front`, `wall_side`, `sign_board` 등)은 자산별로 따로 그려야 한다(각 표의 크기를 따른다).")
    A("")
    A("## 6. 알려진 한계")
    A("")
    A("- 3D 모양(지붕 각도, 굴뚝, 창문 위치 등)은 임시이며 질감 그림과 함께 조정될 수 있다.")
    A("- 문은 카메라에 보이는 앞벽(왼쪽 아래를 보는 면)에 고정이다(2D 원본의 문 방향은 반영하지 않음).")
    A("- 창 위치·문 위치는 틀 PNG 의 배치를 따라야 3D 의 화분·계단 위치와 맞는다.")
    A("- 실제 PC(GPU) 확인 전. 면 크기는 이 환경의 기준 해상도(칸 36×18, 질감 18)로 계산했다.")
    open(DOC, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    write_readme(assets, rows)
    print("doc:", DOC, " faces:", len(rows), " sheets:", len(assets))


if __name__ == "__main__":
    main()
