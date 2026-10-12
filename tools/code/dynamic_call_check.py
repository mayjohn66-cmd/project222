#!/usr/bin/env python3
"""문자열로 부르는 함수(has_method/call/call_deferred/callv/Callable(…, "이름"))가 실제로 정의돼 있는지 검사한다.
정의가 어디에도 없으면 그 분기는 조용히 죽어 있는 것이다(이름을 바꾸다 깨진 흔적). 읽기 전용.
사용: python tools/code/dynamic_call_check.py .   (정의 없음이 있으면 종료 코드 1)"""
import re, sys, glob, collections
root = sys.argv[1] if len(sys.argv) > 1 else "."
files = {f: open(f, encoding="utf-8", errors="ignore").read() for f in glob.glob(root + "/**/*.gd", recursive=True)}
defined = set()
for t in files.values():
    defined |= set(re.findall(r"^\s*(?:static\s+)?func\s+(\w+)", t, re.M))
    defined |= set(re.findall(r"^\s*signal\s+(\w+)", t, re.M))
    defined |= set(re.findall(r"^\s*(?:@export\s+)?(?:var|const)\s+(\w+)", t, re.M))
BUILTIN = set("""queue_free free show hide add_child remove_child set_process set_physics_process get_children get_parent
play stop pause emit_signal rebuild refresh _ready _process _draw queue_redraw grab_focus release_focus update_minimum_size
get_tree is_inside_tree get_node get_global_position set_visible get_rect get_size set_text get_text set_disabled
size position global_position visible name text disabled modulate scale rotation get_viewport reparent duplicate""".split())
PAT = re.compile(r'(has_method|\.call|call_deferred|callv|Callable\([^,]+,|has_user_signal|has_signal)\(\s*"([A-Za-z_0-9]+)"')
missing = collections.defaultdict(list)
total = 0
for f, t in files.items():
    for i, line in enumerate(t.split("\n"), 1):
        if line.lstrip().startswith("#"): continue
        for kind, name in PAT.findall(line):
            total += 1
            if name not in defined and name not in BUILTIN:
                missing[name].append("%s:%d" % (f.replace(root.rstrip("/") + "/", ""), i))
print("검사한 문자열 호출 %d건, 정의 없는 이름 %d종" % (total, len(missing)))
for n, where in sorted(missing.items()):
    print("  %-34s %s" % (n, ", ".join(where[:3])))
sys.exit(1 if missing else 0)
