#!/usr/bin/env python3
"""Pixel Lab(REST v2)로 아이템 아이콘을 자동으로 만들어 받은그림 폴더에 모으는 도구.

흐름(사용자는 결과만 고른다):
  1. 목록: docs/그림_3D/이미지_제작_목록.md 의 "아이템 아이콘" 표(ID·파일·프롬프트용 대상)에서 아직 그림이 없는 항목을 읽는다.
  2. 요청: 공통 프롬프트 + "Subject: <대상>" 으로 create-image-pixflux 를 부른다(32x32, 투명 배경). 동기 API라 바로 PNG가 온다.
  3. 보관: docs/그림_작업/받은그림/아이템/<id>/ 에 원본(32x32)과 64x64 확대본을 저장하고, 한 장짜리 확인용 시트(contact sheet)를 만든다.
  4. 반영(별도 단계): 사용자가 고른 id만 `--ingest id,id` 로 art/items/pixel_v1/ 에 넣고 validate_assets 를 돌린다.

안전장치:
  - 기본은 모의 실행(dry run). 실제 요청은 `--run` 을 줘야 한다.
  - 토큰은 환경 변수 PIXELLAB_TOKEN 에서만 읽는다(출력·저장하지 않는다). 저장소 파일에 쓰지 말 것.
  - 시작 전 잔액을 확인하고, 한 번에 `--limit`(기본 6)개까지만, `--budget-usd`(기본 1.0) 넘으면 멈춘다.
  - 이미 art/ 에 파일이 있는 항목은 건너뛴다(덮어쓰지 않는다). 받은그림에 이미 있으면 `--redo` 가 있어야 다시 만든다.

사용:
  python tools/art/pixellab_batch.py --list                      # 만들 목록만 보기
  python tools/art/pixellab_batch.py                             # 모의 실행(요청 내용 출력)
  python tools/art/pixellab_batch.py --run --limit 6             # 6개 생성
  python tools/art/pixellab_batch.py --run --ids wild_berry,coal # 지정한 것만
  python tools/art/pixellab_batch.py --ingest wild_berry,coal    # 확인한 것만 게임 폴더에 넣기(64x64 확대 + 검사)
Pillow 필요: pip install pillow
"""
import argparse
import base64
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

from PIL import Image, ImageDraw

BASE_URL = "https://api.pixellab.ai/v2"
LIST_DOC = "docs/그림_3D/이미지_제작_목록.md"
OUT_ROOT = "docs/그림_작업/받은그림/아이템"
TOKEN_ENV = "PIXELLAB_TOKEN"
SIZE = 32                 # 만드는 격자(정수 배 확대 규칙: 32 -> 64)
SCALE = 64 // SIZE
USD_PER_CALL_GUESS = 0.01  # 응답에 usage 가 없을 때 쓰는 추정값


def repo_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read_doc(root: str):
    """(공통 프롬프트, 항목 목록[{id, name, file, subject}])"""
    text = open(os.path.join(root, LIST_DOC), encoding="utf-8").read()
    block = re.search(r"공통 프롬프트.*?```\n(.*?)```", text, re.S)
    common = " ".join(block.group(1).split()) if block else ""
    section = text.split("## 2. 아이템 아이콘", 1)[-1]
    # 다음 큰 절(## 숫자.) 전까지만
    section = re.split(r"\n## \d+\.", section, maxsplit=1)[0]
    items = []
    for line in section.splitlines():
        m = re.match(r"\|\s*`([a-z0-9_]+)`\s*\|\s*([^|]*)\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|", line)
        if m:
            items.append({"id": m.group(1), "name": m.group(2).strip(), "file": m.group(3), "subject": m.group(4).strip()})
    return common, items


def pending(root: str, items, redo: bool):
    result = []
    for it in items:
        if os.path.exists(os.path.join(root, it["file"])):
            continue  # 이미 게임에 그림이 있다
        if not redo and os.path.exists(os.path.join(root, OUT_ROOT, it["id"], it["id"] + "_32.png")):
            continue  # 이미 받아 둔 것
        result.append(it)
    return result


def api(method: str, path: str, token: str, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(BASE_URL + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "application/json")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (429, 529) and attempt < 3:
                time.sleep(4 * (attempt + 1))  # 속도 제한: 기다렸다 다시
                continue
            detail = e.read().decode("utf-8", "replace")[:300]
            raise RuntimeError(f"HTTP {e.code}: {detail}")
    raise RuntimeError("재시도 실패")


def decode_image(response: dict) -> Image.Image:
    image = response.get("image") or {}
    b64 = image.get("base64", "")
    if "," in b64:
        b64 = b64.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGBA")


def save_item(root: str, it, image: Image.Image) -> str:
    folder = os.path.join(root, OUT_ROOT, it["id"])
    os.makedirs(folder, exist_ok=True)
    if image.size != (SIZE, SIZE):
        image = image.resize((SIZE, SIZE), Image.NEAREST)
    # 반투명 정리(게임 규격: 반투명 없음)
    px = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    image.save(os.path.join(folder, it["id"] + "_32.png"))
    image.resize((64, 64), Image.NEAREST).save(os.path.join(folder, it["id"] + "_64.png"))
    return folder


def contact_sheet(root: str, ids, path: str) -> None:
    """확인용 한 장: 64x64 확대본을 3배로 키워 격자에 늘어놓고 id 를 적는다."""
    cell, label = 64 * 3, 18
    cols = 4
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + label)), (58, 52, 48, 255))
    draw = ImageDraw.Draw(sheet)
    for i, item_id in enumerate(ids):
        src = os.path.join(root, OUT_ROOT, item_id, item_id + "_64.png")
        if not os.path.exists(src):
            continue
        icon = Image.open(src).convert("RGBA").resize((cell, cell), Image.NEAREST)
        x, y = (i % cols) * cell, (i // cols) * (cell + label)
        sheet.alpha_composite(icon, (x, y + label))
        draw.text((x + 4, y + 3), item_id, fill=(255, 235, 190, 255))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)


def build_request(common: str, it) -> dict:
    return {
        "description": f"{common} Subject: {it['subject']}",
        "image_size": {"width": SIZE, "height": SIZE},
        "no_background": True,
        "text_guidance_scale": 8,
        "seed": sum(ord(c) * (i + 7) for i, c in enumerate(it["id"])) % 1_000_000,   # id 마다 고정(같은 요청은 같은 결과)
    }


def run_generation(root: str, common: str, targets, args) -> None:
    token = os.environ.get(TOKEN_ENV, "").strip()
    if not token:
        sys.exit(f"환경 변수 {TOKEN_ENV} 가 없습니다. 토큰은 환경 설정에만 넣고 채팅·파일에 쓰지 마세요.")
    balance = api("GET", "/balance", token)
    print("잔액:", json.dumps(balance.get("credits", balance), ensure_ascii=False))
    spent = 0.0
    done = []
    for it in targets:
        if spent >= args.budget_usd:
            print(f"예산 한도({args.budget_usd} USD)에 도달해 멈춥니다.")
            break
        print(f"[{it['id']}] {it['subject']} ...", end=" ", flush=True)
        try:
            response = api("POST", "/create-image-pixflux", token, build_request(common, it))
        except RuntimeError as e:
            print("실패:", e)
            if "402" in str(e):
                print("크레딧이 부족합니다. 충전 후 다시 실행하세요.")
                break
            continue
        usage = (response.get("usage") or {}).get("usd")
        spent += float(usage) if usage is not None else USD_PER_CALL_GUESS
        save_item(root, it, decode_image(response))
        done.append(it["id"])
        print("저장")
    if done:
        sheet = os.path.join(root, OUT_ROOT, "_시트", time.strftime("%Y%m%d_%H%M%S") + ".png")
        contact_sheet(root, done, sheet)
        print(f"확인용 시트: {sheet}")
        print("마음에 드는 것만 반영: python tools/art/pixellab_batch.py --ingest " + ",".join(done[:3]) + ",...")
    print(f"사용한 금액(추정 포함): {spent:.3f} USD")


def ingest(root: str, items, ids) -> None:
    by_id = {it["id"]: it for it in items}
    written = []
    for item_id in ids:
        it = by_id.get(item_id)
        if it is None:
            print(f"[{item_id}] 목록에 없는 id")
            continue
        src = os.path.join(root, OUT_ROOT, item_id, item_id + "_64.png")
        if not os.path.exists(src):
            print(f"[{item_id}] 받은 그림이 없습니다: {src}")
            continue
        dst = os.path.join(root, it["file"])
        if os.path.exists(dst):
            print(f"[{item_id}] 이미 있는 파일이라 덮어쓰지 않습니다: {it['file']}")
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.open(src).save(dst)
        written.append(it["file"])
        print(f"[{item_id}] -> {it['file']}")
    if written:
        print("검증:")
        subprocess.call([sys.executable, os.path.join(root, "tools", "validate_assets.py"), root])
        print("Godot 로 열어 가져오기(.import)를 만든 뒤 커밋하세요. 커밋 접두사: [art]")


def main() -> None:
    ap = argparse.ArgumentParser(description="Pixel Lab 으로 아이템 아이콘 자동 생성")
    ap.add_argument("--list", action="store_true", help="아직 그림이 없는 목록만 보여 준다")
    ap.add_argument("--run", action="store_true", help="실제로 요청한다(없으면 모의 실행)")
    ap.add_argument("--limit", type=int, default=6, help="한 번에 만들 최대 개수")
    ap.add_argument("--ids", default="", help="쉼표로 이은 id만 만든다")
    ap.add_argument("--redo", action="store_true", help="받아 둔 것도 다시 만든다")
    ap.add_argument("--budget-usd", type=float, default=1.0, help="이 금액을 넘으면 멈춘다")
    ap.add_argument("--ingest", default="", help="쉼표로 이은 id 를 게임 폴더에 넣는다")
    args = ap.parse_args()
    root = repo_root()
    common, items = read_doc(root)
    if not common or not items:
        sys.exit("목록 문서를 읽지 못했습니다: " + LIST_DOC)
    if args.ingest:
        ingest(root, items, [s for s in args.ingest.split(",") if s])
        return
    targets = pending(root, items, args.redo)
    if args.ids:
        wanted = {s for s in args.ids.split(",") if s}
        targets = [it for it in targets if it["id"] in wanted]
    print(f"그림이 없는 항목: {len(targets)}개 (표 전체 {len(items)}개)")
    if args.list:
        for it in targets:
            print(f"  {it['id']:<18} {it['name']:<10} {it['subject']}")
        return
    targets = targets[: args.limit]
    if not args.run:
        print("모의 실행: 아래 요청을 보낼 예정입니다(--run 으로 실제 실행).")
        for it in targets:
            print(f"  POST /create-image-pixflux  {it['id']}")
            print("    " + json.dumps(build_request(common, it), ensure_ascii=False)[:230] + " ...")
        return
    run_generation(root, common, targets, args)


if __name__ == "__main__":
    main()
