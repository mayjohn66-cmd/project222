extends Node
## 3D 가구 어긋남 점검: 모든 가구를 4방향으로 만들어, 3D 모델이 실제로 차지하는 크기(AABB)가 게임 로직의 칸 영역(발자국)과 얼마나 다른지 숫자로 뽑는다.
## 사용: godot --headless --path . res://dev/scenes/audit_furniture_3d.tscn -- <저장 폴더>   → <저장 폴더>/furniture_3d_audit.md, furniture_3d_audit.csv
## 단위는 칸(1.0 = 한 칸). 튀어나옴(+) = 모델이 칸 밖으로 나옴(옆 칸을 파고듦), 부족(-) = 칸을 다 채우지 못함.
## 한계: 모델 정점 범위만 본다(눈에 보이는 모양·질감·그림자·깊이 정렬은 보지 않는다). 벽에 거는 물건(문·포스터)은 따로 만들어져 이번 점검에서 빼고 목록에만 적는다.
const OVERHANG_WARN := 0.05     # 이보다 칸 밖으로 나오면 "튀어나옴"
const SHORT_WARN := 0.15        # 길이·폭이 칸보다 이만큼 부족하면 "부족"
const TURN_WARN := 0.04         # 회전을 해도 같아야 할 앞/뒤·좌/우 쏠림이 이만큼 다르면 "회전 불일치"
const HEIGHT_WARN := 0.12       # 모델 높이가 CSV 높이(블록)와 이만큼 다르면 "높이 불일치"(블록 환산)
const FLOAT_WARN := 0.02        # 바닥에서 이만큼 떠 있으면 "공중"

var rows: Array[Dictionary] = []
var skipped: Array[String] = []

func _ready() -> void: call_deferred("run")

func run() -> void:
	var out_dir := "/tmp/furniture_audit"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.initialize_new_game()
	var rules = load("res://script/build/model/build_area_rules.gd").new()
	var pp := {"ts": 18, "block_px": 22.0, "unit_px_z": (36.0 / sqrt(2.0)) * cos(deg_to_rad(30.0))}
	var ids: Array[String] = BuildObjectData.get_all_build_ids()
	ids.sort()
	for id in ids:
		var data: Dictionary = BuildObjectData.get_build_object(id)
		var row3: Dictionary = Furniture3DData.get_row(id)
		var kind := str(row3["kind"])
		if kind == "door" or kind == "wall_plate":
			skipped.append("%s(%s)" % [id, kind]); continue
		if kind != "shelf" and kind != "model":
			skipped.append("%s(%s: 상자형은 칸 그대로라 점검 불필요)" % [id, kind]); continue
		var base: Vector2i = data.get("grid_size", Vector2i.ONE)
		var rot_stat: Array[Dictionary] = []
		for rot in range(4):
			var size: Vector2i = rules.get_rotated_size(base, rot)
			var lo := Vector2(-0.5, -0.5)
			var hi := Vector2(size.x - 0.5, size.y - 0.5)
			var depth: float = row3["depth_ratio"]
			if depth < 1.0:
				match rot:
					0: hi.y = lo.y + depth
					1: hi.x = lo.x + depth
					2: lo.y = hi.y - depth
					3: lo.x = hi.x - depth
			var built: Dictionary
			if kind == "model":
				built = FurnitureAssets.build(id, lo, hi, rot, pp.duplicate(), {})
			else:
				var slots: Array = []
				built = ShelfAssets.build(lo, hi, rot, 1, slots, 2, pp.duplicate())
			var aabb: AABB = (built["mesh"] as Mesh).get_aabb()
			var mn := Vector3(aabb.position)
			var mx := Vector3(aabb.position + aabb.size)
			var over := {"left": lo.x - mn.x, "right": mx.x - hi.x, "back": lo.y - mn.z, "front": mx.z - hi.y}
			# 앞쪽 방향 기준(u 길이, v 뒤→앞)으로 바꾼 쏠림: 회전해도 같아야 한다
			var cx := (mn.x + mx.x) * 0.5 - (lo.x + hi.x) * 0.5
			var cz := (mn.z + mx.z) * 0.5 - (lo.y + hi.y) * 0.5
			var local: Vector2 = _to_local(rot, cx, cz)
			var fill := (aabb.size.x * aabb.size.z) / maxf((hi.x - lo.x) * (hi.y - lo.y), 0.0001)
			var along_x: bool = rot == 0 or rot == 2
			var model_len: float = aabb.size.x if along_x else aabb.size.z
			var model_dep: float = aabb.size.z if along_x else aabb.size.x
			var fp_len: float = (hi.x - lo.x) if along_x else (hi.y - lo.y)
			var fp_dep: float = (hi.y - lo.y) if along_x else (hi.x - lo.x)
			var height_blocks: float = mx.y * float(pp["unit_px_z"]) / float(pp["block_px"])
			var csv_blocks: float = float(built["total_blocks"])
			var r := {
				"id": id, "kind": kind, "rot": rot, "grid": "%dx%d" % [size.x, size.y],
				"overhang_max": maxf(maxf(over["left"], over["right"]), maxf(over["back"], over["front"])),
				"over": over, "len_diff": model_len - fp_len, "dep_diff": model_dep - fp_dep,
				"off_u": local.x, "off_v": local.y, "fill": fill,
				"min_y": mn.y, "height_blocks": height_blocks, "csv_blocks": csv_blocks,
			}
			rows.append(r)
			rot_stat.append(r)
		# 회전 일치: 4방향의 (u,v) 쏠림이 서로 같아야 한다
		var spread_u := 0.0
		var spread_v := 0.0
		for a in rot_stat:
			for b in rot_stat:
				spread_u = maxf(spread_u, absf(float(a["off_u"]) - float(b["off_u"])))
				spread_v = maxf(spread_v, absf(float(a["off_v"]) - float(b["off_v"])))
		for a in rot_stat: a["turn_spread"] = maxf(spread_u, spread_v)
	_report(out_dir)
	get_tree().quit()

# 칸 좌표 (dx, dz) 를 앞쪽 방향 기준 (u: 길이, v: 뒤→앞)으로 바꾼다. ShelfAssets._to_world 의 역변환.
func _to_local(rot: int, dx: float, dz: float) -> Vector2:
	match rot:
		0: return Vector2(dx, dz)
		2: return Vector2(-dx, -dz)
		1: return Vector2(dz, dx)
		_: return Vector2(-dz, -dx)

func _flags(r: Dictionary) -> PackedStringArray:
	var f := PackedStringArray()
	if float(r["overhang_max"]) > OVERHANG_WARN: f.append("튀어나옴")
	if float(r["len_diff"]) < -SHORT_WARN or float(r["dep_diff"]) < -SHORT_WARN: f.append("부족")
	if float(r.get("turn_spread", 0.0)) > TURN_WARN: f.append("회전 불일치")
	if absf(float(r["height_blocks"]) - float(r["csv_blocks"])) > HEIGHT_WARN: f.append("높이 불일치")
	if float(r["min_y"]) > FLOAT_WARN: f.append("공중")
	return f

func _report(dir: String) -> void:
	var csv := FileAccess.open(dir + "/furniture_3d_audit.csv", FileAccess.WRITE)
	csv.store_line("id,kind,rot,grid,over_left,over_right,over_back,over_front,len_diff,dep_diff,off_u,off_v,fill,min_y,height_blocks,csv_blocks,turn_spread,flags")
	var flagged: Dictionary = {}
	var total_ids: Dictionary = {}
	for r in rows:
		var fl := _flags(r)
		total_ids[r["id"]] = true
		var o: Dictionary = r["over"]
		csv.store_line("%s,%s,%d,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.3f,%.3f,%.3f,%.3f,%s" % [r["id"], r["kind"], r["rot"], r["grid"], o["left"], o["right"], o["back"], o["front"], r["len_diff"], r["dep_diff"], r["off_u"], r["off_v"], r["fill"], r["min_y"], r["height_blocks"], r["csv_blocks"], r.get("turn_spread", 0.0), "|".join(fl)])
		if not fl.is_empty():
			if not flagged.has(r["id"]): flagged[r["id"]] = {"flags": {}, "worst": 0.0, "rots": []}
			for x in fl: flagged[r["id"]]["flags"][x] = true
			flagged[r["id"]]["worst"] = maxf(flagged[r["id"]]["worst"], float(r["overhang_max"]))
			flagged[r["id"]]["rots"].append(r["rot"])
	csv.close()
	var md := FileAccess.open(dir + "/furniture_3d_audit.md", FileAccess.WRITE)
	md.store_line("# 3D 가구 어긋남 점검 결과\n")
	md.store_line("점검한 가구 %d종 × 4방향. 이상이 있는 가구 %d종.\n" % [total_ids.size(), flagged.size()])
	md.store_line("기준: 튀어나옴 > %.2f칸, 부족 < -%.2f칸, 회전 쏠림 차 > %.2f칸, 높이 차 > %.2f블록, 공중 > %.2f.\n" % [OVERHANG_WARN, SHORT_WARN, TURN_WARN, HEIGHT_WARN, FLOAT_WARN])
	md.store_line("| 가구 | 종류 | 문제 | 가장 크게 튀어나온 값(칸) | 해당 방향 |")
	md.store_line("|---|---|---|---|---|")
	var keys: Array = flagged.keys()
	keys.sort_custom(func(a, b): return float(flagged[a]["worst"]) > float(flagged[b]["worst"]))
	for k in keys:
		var kind := ""
		for r in rows:
			if r["id"] == k: kind = str(r["kind"]); break
		md.store_line("| `%s` | %s | %s | %.2f | %s |" % [k, kind, ", ".join(flagged[k]["flags"].keys()), flagged[k]["worst"], ",".join(flagged[k]["rots"].map(func(x): return str(x)))])
	md.store_line("\n## 점검 대상이 아닌 것\n" + ", ".join(skipped) + "\n")
	md.store_line("## 방향별 자세한 수치\n전체 표는 `furniture_3d_audit.csv`.")
	md.close()
	print("AUDIT ids=%d flagged=%d rows=%d out=%s" % [total_ids.size(), flagged.size(), rows.size(), dir])
	for k in keys: print("  FLAG %s: %s worst=%.2f" % [k, ",".join(flagged[k]["flags"].keys()), flagged[k]["worst"]])
