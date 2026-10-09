#!/usr/bin/env python3
"""안 쓰는 후보 찾기(읽기 전용, 파일을 바꾸지 않는다). 사용: python tools/unused_scan.py .
결과는 '후보'다. 동적 호출(call/has_method/문자열 경로)은 잡지 못하므로 삭제 전 사람이 확인한다."""
import re, sys, os
from pathlib import Path
root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
SKIP = {".git", ".godot", "addons"}
def walk(exts):
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            if f.endswith(exts): yield Path(dp) / f
gd = list(walk((".gd",)))
text_files = list(walk((".gd", ".tscn", ".tres", ".godot", ".cfg", ".csv", ".json", ".md")))
blob = {p: p.read_text(encoding="utf-8", errors="ignore") for p in text_files}
allblob = "\n".join(blob.values())
rel = lambda p: str(p.relative_to(root)).replace("\\", "/")
prod = lambda p: not rel(p).startswith("dev/")

# 1) 어디서도 참조되지 않는 스크립트
print("== 참조 없는 스크립트(res 경로·class_name 모두 안 쓰임) ==")
for p in sorted(gd):
    r = rel(p)
    if r.startswith("dev/"): continue
    t = blob[p]
    m = re.search(r"^class_name\s+(\w+)", t, re.M)
    by_path = sum(1 for q, s in blob.items() if q != p and ("res://" + r) in s)
    by_class = 0
    if m:
        pat = re.compile(r"\b" + m.group(1) + r"\b")
        by_class = sum(1 for q, s in blob.items() if q != p and pat.search(s))
    if by_path == 0 and by_class == 0:
        print("  ", r)

# 2) 정의만 있고 이름이 한 번도 안 나오는 함수(프로덕션 코드)
print("== 이름이 다른 곳에 한 번도 안 나오는 함수 ==")
cnt = {}
for fn in re.findall(r"^\s*(?:static\s+)?func\s+(\w+)", "\n".join(blob[p] for p in gd), re.M):
    cnt[fn] = 1
words = {}
for w in re.findall(r"\b\w+\b", allblob): words[w] = words.get(w, 0) + 1
rows = []
for p in gd:
    if not prod(p): continue
    for m in re.finditer(r"^\s*(?:static\s+)?func\s+(\w+)", blob[p], re.M):
        n = m.group(1)
        if n.startswith("_"): continue  # 엔진 콜백·시그널 핸들러
        if words.get(n, 0) <= 1: rows.append((rel(p), n))
for r, n in sorted(rows): print("  %s :: %s" % (r, n))

# 3) 참조 없는 씬
print("== 참조 없는 씬(.tscn) ==")
for p in walk((".tscn",)):
    r = rel(p)
    if r.startswith("dev/"): continue
    if not any(("res://" + r) in s for q, s in blob.items() if q != p): print("  ", r)

# 4) 코드·씬에서 안 쓰는 CSV
print("== 이름이 어디서도 안 나오는 data CSV ==")
for p in walk((".csv",)):
    r = rel(p)
    if not r.startswith("data/"): continue
    if not any((p.name in s) for q, s in blob.items() if q != p and q.suffix != ".csv"): print("  ", r)
