#!/usr/bin/env python3
"""docs/ 문서 점검: 깨진 링크와 목록에 빠진 문서를 찾는다.

사용: python tools/code/docs_check.py [저장소 경로]
- 깨진 링크: 모든 .md 안의 상대 링크가 가리키는 파일이 없으면 보고.
- 빠진 문서: docs/README.md 와 docs/콘텐츠/README.md 어디에서도 링크되지 않은 문서를 보고
  (보관/, drafts/, 받은그림/, 고쳐쓰기_요청/ 는 제외 — 각자 자기 README 로 관리).
끝에 문제 개수를 출력하고, 문제가 있으면 종료 코드 1.
"""
import os
import re
import sys
import urllib.parse

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS = os.path.join(ROOT, "docs")
INDEXES = ["README.md", os.path.join("콘텐츠", "README.md")]
SKIP_DIRS = ("보관", "drafts", "받은그림", "고쳐쓰기_요청", "시트", "틀")
LINK = re.compile(r"\]\(([^)#\s]+)")


def links_of(path):
    text = open(path, encoding="utf-8", errors="ignore").read()
    out = []
    for raw in LINK.findall(text):
        if raw.startswith(("http://", "https://", "mailto:")):
            continue
        out.append(os.path.normpath(os.path.join(os.path.dirname(path), urllib.parse.unquote(raw))))
    return out


def main():
    mds = []
    for d, dirs, files in os.walk(DOCS):
        for f in files:
            if f.endswith(".md"):
                mds.append(os.path.join(d, f))
    broken = []
    for m in mds:
        for target in links_of(m):
            if not os.path.exists(target):
                broken.append((os.path.relpath(m, ROOT), os.path.relpath(target, ROOT)))
    indexed = set()
    for idx in INDEXES:
        p = os.path.join(DOCS, idx)
        if os.path.exists(p):
            indexed.update(links_of(p))
    missing = []
    for m in mds:
        rel = os.path.relpath(m, DOCS)
        parts = rel.split(os.sep)
        if os.path.basename(m) == "README.md" or parts[0] in SKIP_DIRS or any(p in SKIP_DIRS for p in parts):
            continue
        if os.path.normpath(m) not in indexed:
            missing.append(os.path.relpath(m, ROOT))
    print("깨진 링크 %d개" % len(broken))
    for b in broken:
        print("  %s -> %s" % b)
    print("목록에 빠진 문서 %d개" % len(missing))
    for m in sorted(missing):
        print("  " + m)
    sys.exit(1 if broken or missing else 0)


if __name__ == "__main__":
    main()
