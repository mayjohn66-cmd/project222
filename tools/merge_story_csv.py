#!/usr/bin/env python3
"""새 이야기 글(탭으로 구분된 표)을 data/shop/requests/requests_text.csv 에 합친다.
사용: python tools/merge_story_csv.py 새글.tsv            # 점검만(기본). 파일을 바꾸지 않는다.
      python tools/merge_story_csv.py 새글.tsv --apply    # 실제로 반영
입력 열: id, kind, title, summary, lines, completion (탭 구분, 뒤쪽 열은 비어도 된다. 머리글 줄은 있어도 없어도 된다)

규칙
- 키는 kind:id. 입력에 없는 기존 행은 그대로 둔다(덮어쓰지 않는다).
- 입력의 빈 칸은 '바꾸지 않음'이다. 기존 값을 지우지 않는다.
- lines/completion 은 '|' 로 줄을 나눈다. 줄 수가 같으면 기존 줄 앞의 표시(*서술, {표정})를 새 줄로 옮긴다.
  줄 수가 다르면 표시를 옮기지 않고 '표시 수동 확인' 목록에 올린다.
- 바뀐 행만 그 줄만 고쳐 쓴다(다른 줄은 글자 그대로). 새 행은 파일 끝에 붙인다.
- 줄 수가 바뀐 행은 연출·테스트가 줄 수에 기대는지 확인해야 하므로 따로 알려 준다."""
import csv, io, re, sys
CSV = "data/shop/requests/requests_text.csv"
COLS = ["id", "kind", "title", "summary", "lines", "completion"]
MARK = re.compile(r"^((?:\*|\{[^}]+\})+)")

def split_lines(value):
    return [p for p in value.split("|")] if value else []

def lead_marks(line):
    m = MARK.match(line.strip())
    return m.group(1) if m else ""

def carry_marks(old_value, new_value):
    """(합쳐진 값, 상태) 상태: same=표시 없음/그대로, carried=옮김, manual=줄 수 달라 수동"""
    old, new = split_lines(old_value), split_lines(new_value)
    if len(old) != len(new):
        lost = any(lead_marks(o) for o in old)
        return new_value, ("manual" if lost else "count")
    out, moved = [], False
    for o, n in zip(old, new):
        om = lead_marks(o)
        if om and not lead_marks(n):
            out.append(om + n); moved = True
        else:
            out.append(n)
    return "|".join(out), ("carried" if moved else "same")

def read_input(path):
    rows = []
    for raw in open(path, encoding="utf-8").read().splitlines():
        if not raw.strip(): continue
        cells = raw.split("\t")
        if cells[0] == "id" and len(cells) > 1 and cells[1] == "kind": continue
        cells += [""] * (len(COLS) - len(cells))
        rows.append(dict(zip(COLS, cells[:len(COLS)])))
    return rows

def ser(row):
    out = io.StringIO()
    csv.writer(out, lineterminator="").writerow([row[c] for c in COLS])
    return out.getvalue()

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv
    if not args:
        print(__doc__); sys.exit(2)
    incoming = read_input(args[0])
    text = open(CSV, encoding="utf-8", newline="").read()
    lines = text.split("\n")
    header = next(csv.reader([lines[0]]))
    assert header == COLS, "CSV 열 이름이 다릅니다: %s" % header
    index = {}
    for i, ln in enumerate(lines[1:], 1):
        if not ln.strip(): continue
        try: cells = next(csv.reader([ln]))
        except Exception: continue
        if len(cells) == len(COLS): index[(cells[1], cells[0])] = (i, dict(zip(COLS, cells)))
    new_rows, changed, manual, counts, kept_empty, bad = [], [], [], [], [], []
    patched = {}
    for r in incoming:
        key = (r["kind"], r["id"])
        if not r["id"] or not r["kind"]: bad.append(r); continue
        if key not in index:
            new_rows.append(r); continue
        i, old = index[key]
        merged, diffs = dict(old), []
        for c in ("title", "summary", "lines", "completion"):
            nv = r[c]
            if not nv:
                if old[c]: kept_empty.append("%s:%s.%s" % (key[0], key[1], c))
                continue
            if c in ("lines", "completion"):
                nv, state = carry_marks(old[c], nv)
                if state == "manual": manual.append("%s:%s.%s" % (key[0], key[1], c))
                if state in ("manual", "count"):
                    counts.append("%s:%s.%s %d→%d줄" % (key[0], key[1], c, len(split_lines(old[c])), len(split_lines(r[c]))))
            if nv != old[c]:
                merged[c] = nv; diffs.append(c)
        if diffs:
            changed.append("%s:%s [%s]" % (key[0], key[1], ",".join(diffs)))
            patched[i] = ser(merged)
    print("입력 %d행 → 바뀌는 기존 행 %d · 새 행 %d · 변화 없음 %d" % (len(incoming), len(changed), len(new_rows), len(incoming) - len(changed) - len(new_rows) - len(bad)))
    if bad: print("키(id/kind)가 빠진 행 %d개는 건너뜁니다." % len(bad))
    print("\n[바뀌는 기존 행]"); [print("  ", c) for c in changed]
    print("\n[새 행]"); [print("  ", "%s:%s" % (r["kind"], r["id"]), "—", r["title"]) for r in new_rows]
    print("\n[줄 수가 달라진 칸] 연출·테스트가 줄 수에 기대는지 확인 필요"); [print("  ", c) for c in counts]
    print("\n[표시(*, {표정}) 수동 확인] 줄 수가 달라 옮기지 못함"); [print("  ", c) for c in manual]
    print("\n[입력이 비어 있어 기존 값을 유지한 칸] %d개" % len(kept_empty))
    if not apply:
        print("\n(점검만 했습니다. 반영하려면 --apply)"); return
    for i, s in patched.items(): lines[i] = s
    tail = [ser(r) for r in new_rows]
    while lines and lines[-1] == "": lines.pop()
    lines += tail
    open(CSV, "w", encoding="utf-8", newline="").write("\n".join(lines) + "\n")
    print("\n반영했습니다: 수정 %d행 · 추가 %d행" % (len(patched), len(tail)))

main()
