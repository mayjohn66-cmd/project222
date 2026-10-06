#!/usr/bin/env python3
"""requests_text.csv(또는 초안 CSV)를 사람이 읽기 쉬운 마크다운으로 바꾼다.
사용: python tools/export_story_text.py [--file CSV] [--prefix act4_] [--out 파일.md]
기본: data/shop/requests/requests_text.csv 의 act4_ 행 → docs/스토리_4막_글_보기.md
"""
import argparse, csv, re, sys
from collections import OrderedDict

ap = argparse.ArgumentParser()
ap.add_argument("--file", default="data/shop/requests/requests_text.csv")
ap.add_argument("--prefix", default="act4_")
ap.add_argument("--out", default="docs/스토리_4막_글_보기.md")
a = ap.parse_args()

rows = [r for r in csv.DictReader(open(a.file, encoding="utf-8")) if r["id"].startswith(a.prefix)]
groups = OrderedDict()
for r in rows:
    m = re.match(re.escape(a.prefix) + r"([a-z]\d)_", r["id"])
    groups.setdefault(m.group(1) if m else "etc", []).append(r)

out = ["# 글 보기: %s (%d행)\n" % (a.prefix, len(rows)),
       "원본: `%s` · 이 파일은 `python tools/export_story_text.py`가 만든 읽기용 사본이다. 고칠 때는 원본 CSV를 고친다.\n" % a.file]
for key, items in groups.items():
    out.append("\n## %s\n" % key)
    for r in items:
        out.append("### `%s`" % r["id"])
        for label, col in (("제목", "title"), ("요약", "summary")):
            if r[col].strip(): out.append("- %s: %s" % (label, r[col]))
        if r["lines"].strip():
            out.append("- 대사:")
            for i, line in enumerate(r["lines"].split("|"), 1): out.append("  %d. %s" % (i, line.strip()))
        if r["completion"].strip():
            out.append("- 완료 문장:")
            for i, line in enumerate(r["completion"].split("|"), 1): out.append("  %d. %s" % (i, line.strip()))
        out.append("")
open(a.out, "w", encoding="utf-8").write("\n".join(out))
print("%s 행 %d개 → %s" % (a.prefix, len(rows), a.out))
