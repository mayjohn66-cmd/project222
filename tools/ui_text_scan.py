#!/usr/bin/env python3
"""UI 문구 분리 현황. 사용: python tools/ui_text_scan.py .
1) 코드가 쓰는 UiText 키가 data/ui/ui_text.csv 에 모두 있는지(없으면 종료 코드 1)
2) CSV에만 있고 코드에서 안 쓰는 키
3) 코드에 한글 문자열을 직접 쓴 줄 수(파일별 상위) = 아직 옮기지 않은 양"""
import re, sys, glob, csv, collections
root = sys.argv[1] if len(sys.argv) > 1 else "."
rows = list(csv.reader(open(root + "/data/ui/ui_text.csv", encoding="utf-8")))[1:]
keys = {r[0] for r in rows if r}
used = collections.defaultdict(list)
hard = collections.Counter()
for f in glob.glob(root + "/script/**/*.gd", recursive=True):
    for i, line in enumerate(open(f, encoding="utf-8", errors="ignore"), 1):
        for k in re.findall(r'UiText\.(?:t|f|has_key)\(\s*"([^"]+)"', line): used[k].append("%s:%d" % (f, i))
        code = line.split("#")[0]
        if re.search(r'"[^"]*[가-힣][^"]*"', code) and "DebugLog" not in code and "push_warning" not in code:
            hard[f.replace(root + "/", "")] += 1
missing = sorted(set(used) - keys)
print("UiText 키 %d개 정의 · 코드에서 %d개 사용" % (len(keys), len(used)))
for k in missing: print("  없는 키:", k, used[k][:2])
for k in sorted(keys - set(used)): print("  안 쓰는 키:", k)
print("코드에 직접 쓴 한글 문구 줄 수: %d (파일 %d개). 많은 순:" % (sum(hard.values()), len(hard)))
for f, n in hard.most_common(8): print("  %4d  %s" % (n, f))
sys.exit(1 if missing else 0)
