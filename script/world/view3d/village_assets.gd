class_name VillageAssets
extends RefCounted
## 마을 건물·소품의 3D 모양(메시)과 임시 면 질감을 만드는 곳. StoreView3D 의 마을 거울(VillageMirror)과
## "그림 요청용 미리 출력"(dev/spike3d/art_request_export.gd)이 **같은 코드**를 쓴다 → 요청한 그림이 실제 3D 와 어긋나지 않는다.
## 모든 질감은 코드로 칠한 임시 그림이고, 면마다 이름(name)·크기를 갖는다(= 그림을 요청할 목록).
## 길이 단위는 칸(세계 단위), 높이도 세계 단위(1 ≈ 1블록). 면 질감 한 장이 한 칸일 때 크기는 ts×ts 픽셀(ts = 질감 크기, 기본 18).
##
## 매개변수 p: {"ts": 질감 크기, "block_px": 1블록 세로 px, "unit_px_z": 세계 단위 1 의 화면 세로 px}

const FACADE_SHADER: Shader = preload("res://script/world/view3d/shader/facade.gdshader")
const CUTOUT_SHADER: Shader = preload("res://script/world/view3d/shader/cutout.gdshader")

static var _texture_cache: Dictionary = {}


# ---------------------------------------------------------------- 공통

static func block_h(blocks: float, p: Dictionary) -> float:
	return blocks * float(p["block_px"]) / float(p["unit_px_z"])


# overrides: true 면 art/world3d/<자산id>/<면이름>.png 가 있을 때 임시 질감 대신 쓴다(그림 요청 내보내기는 false 로 임시 틀을 만든다).
static func default_params(texture_size: int = 18, block_px: float = 22.0, tile_low: float = 36.0, overrides: bool = true) -> Dictionary:
	return {"ts": texture_size, "block_px": block_px, "unit_px_z": (tile_low / sqrt(2.0)) * cos(deg_to_rad(30.0)), "overrides": overrides}


const REAL_ART_DIR: String = "res://art/world3d/"
static var _missing_report: Dictionary = {}  # 자산id → 아직 그림이 없는 면 이름 목록(한 번만 모음)


# 실제 그림이 있으면 사양의 질감을 바꾼다: art/world3d/<자산id>/<면이름>.png (+ <면이름>_n.png 법선 맵).
# 실제 그림에는 임시 색조(tint)를 곱하지 않는다. 크기가 임시 틀과 다르면 경고만 하고 그대로 쓴다(UV 가 면 전체에 늘어남).
static func apply_overrides(specs: Array, asset_id: String, p: Dictionary) -> int:
	if asset_id == "" or not bool(p.get("overrides", true)):
		return 0

	var used: int = 0

	for s in specs:
		var face: String = str(s["name"])
		var path: String = "%s%s/%s.png" % [REAL_ART_DIR, asset_id, face]

		if not ResourceLoader.exists(path):
			continue

		var tex: Texture2D = load(path)

		if tex == null:
			continue

		var old: Texture2D = s["tex"]

		if tex.get_width() != old.get_width() or tex.get_height() != old.get_height():
			push_warning("[VillageAssets] %s/%s 크기 %dx%d (요청서 %dx%d) — 그대로 사용(늘어남)" % [asset_id, face, tex.get_width(), tex.get_height(), old.get_width(), old.get_height()])

		s["tex"] = tex
		s["tint"] = Color.WHITE
		s["real"] = true
		used += 1
		var npath: String = "%s%s/%s_n.png" % [REAL_ART_DIR, asset_id, face]

		if ResourceLoader.exists(npath):
			s["normal"] = load(npath)

	return used


# 질감 한 칸 반복형은 이름+크기로 캐시한다(같은 모양 건물이 많아서).
static func _tex(kind: String, ts: int, extra: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	var key: String = "%s|%d|%s" % [kind, ts, str(extra)]

	if _texture_cache.has(key):
		return _texture_cache[key]

	var t: ImageTexture

	match kind:
		"plank", "brick", "grass":
			t = PlaceholderTextures.albedo(kind, ts)
		"crate":
			t = PlaceholderTextures.crate(ts)
		"barrel":
			t = PlaceholderTextures.barrel(ts)
		"stone":
			t = PlaceholderTextures.stone(ts)
		"notice":
			t = PlaceholderTextures.notice_board(ts)
		"foliage":
			t = PlaceholderTextures.foliage(ts, Color(0.2, 0.46, 0.2), extra)
		"flat":
			t = PlaceholderTextures.flat_color(ts, extra)
		_:
			t = PlaceholderTextures.albedo("plank", ts)

	_texture_cache[key] = t
	return t


static func make_material(spec: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	# 투명 컷아웃(빵 카드 등)은 별도 셰이더. 이 재질이 든 물체는 그림자를 끄고 쓴다(셰이더 파일 설명 참고).
	m.shader = CUTOUT_SHADER if bool(spec.get("cutout", false)) else FACADE_SHADER
	m.set_shader_parameter("albedo_tex", spec["tex"])
	m.set_shader_parameter("tint", spec.get("tint", Color.WHITE))
	m.set_shader_parameter("uv_scale", spec.get("uv_scale", Vector2.ONE))

	if spec.has("emit"):
		m.set_shader_parameter("emit_strength", float(spec["emit"]))

	if spec.has("sway"):
		m.set_shader_parameter("sway_amp", float(spec["sway"]))
		m.set_shader_parameter("sway_base", float(spec.get("sway_base", 0.6)))

	if spec.get("normal", null) != null and not bool(spec.get("cutout", false)):
		m.set_shader_parameter("normal_tex", spec["normal"])
		m.set_shader_parameter("use_normal", true)

	return m


# 부품(면)마다 재질을 따로 만들고, 면 순서(= 먼 것부터)에 따라 sub(0~1)를 매겨 부품끼리의 앞뒤를 깊이로 정한다.
static func make_materials(specs: Array) -> Array:
	var out: Array = []
	var n: int = specs.size()

	for i in range(n):
		var m: ShaderMaterial = make_material(specs[i])
		m.set_shader_parameter("sub", float(i) / float(maxi(n - 1, 1)))
		out.append(m)

	return out


# ---------------------------------------------------------------- 부품 모으기(재질 하나 = 면 하나)

class PartBuilder:
	extends RefCounted
	## 부품마다 면(surface) 하나. 한 물체 안은 깊이가 같아서(순번 깊이) 겹침은 **그리는 순서**로만 정해지므로,
	## 부품을 카메라에서 먼 것부터(x+z 가 작은 것부터, 같으면 낮은 것부터) 순서대로 면으로 만든다.
	var parts: Array = []
	var min_pt: Vector3 = Vector3(INF, INF, INF)
	var max_pt: Vector3 = Vector3(-INF, -INF, -INF)

	# bias: 정렬 순서에 더하는 값. 다른 부품 위에 놓이는 얇은 것(빵 카드)은 크게 줘서 항상 나중(앞)에 그리게 한다.
	func new_part(spec: Dictionary, a: Vector3, b: Vector3, bias: float = 0.0) -> SurfaceTool:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var c: Vector3 = (a + b) * 0.5
		parts.append({"depth": c.x + c.z + c.y * 0.02 + bias, "spec": spec, "st": st})
		min_pt = Vector3(minf(min_pt.x, minf(a.x, b.x)), minf(min_pt.y, minf(a.y, b.y)), minf(min_pt.z, minf(a.z, b.z)))
		max_pt = Vector3(maxf(max_pt.x, maxf(a.x, b.x)), maxf(max_pt.y, maxf(a.y, b.y)), maxf(max_pt.z, maxf(a.z, b.z)))
		return st

	func new_part_bounds(a: Vector3, b: Vector3) -> void:
		min_pt = Vector3(minf(min_pt.x, minf(a.x, b.x)), minf(min_pt.y, minf(a.y, b.y)), minf(min_pt.z, minf(a.z, b.z)))
		max_pt = Vector3(maxf(max_pt.x, maxf(a.x, b.x)), maxf(max_pt.y, maxf(a.y, b.y)), maxf(max_pt.z, maxf(a.z, b.z)))

	# 모은 부품을 먼 것부터 mesh 에 덧붙이고, 붙인 순서대로 재질 사양 목록을 돌려준다.
	func commit_into(mesh: ArrayMesh) -> Array:
		var out: Array = []
		var ordered: Array = parts.duplicate()
		ordered.sort_custom(func(x, y): return x["depth"] < y["depth"])

		for part in ordered:
			var st: SurfaceTool = part["st"]

			if part["spec"].get("normal", null) != null:
				st.generate_tangents()

			var before: int = mesh.get_surface_count()
			st.commit(mesh)

			# 면이 하나도 없는 부품은 mesh 에 면이 생기지 않으므로 재질 목록에도 넣지 않는다(개수가 어긋나면 오류).
			if mesh.get_surface_count() > before:
				out.append(part["spec"])

		return out


# 축에 맞춘 상자(밑면 제외). UV 는 세계 길이(칸) 단위, 질감 한 장 = 한 칸.
static func box(b: PartBuilder, key: String, spec: Dictionary, lo: Vector3, hi: Vector3, bias: float = 0.0) -> void:
	var st: SurfaceTool = b.new_part(spec, lo, hi, bias)
	var dx: float = hi.x - lo.x
	var dy: float = hi.y - lo.y
	var dz: float = hi.z - lo.z
	var q := BuildingMesh._quad
	q.call(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, Vector2(0, 0), Vector2(dx, 0), Vector2(dx, dz), Vector2(0, dz))
	q.call(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(0, 0, 1), Vector2(0, dy), Vector2(dx, dy), Vector2(dx, 0), Vector2(0, 0))
	q.call(st, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(1, 0, 0), Vector2(0, dy), Vector2(dz, dy), Vector2(dz, 0), Vector2(0, 0))
	q.call(st, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(0, 0, -1), Vector2(0, dy), Vector2(dx, dy), Vector2(dx, 0), Vector2(0, 0))
	q.call(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(-1, 0, 0), Vector2(0, dy), Vector2(dz, dy), Vector2(dz, 0), Vector2(0, 0))


# 이미 만든 부품(SurfaceTool)에 상자 하나를 더한다(같은 재질의 작은 상자를 한 면으로 모을 때). 윗면·네 옆면, 밑면 없음.
static func box_st(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var dx: float = hi.x - lo.x
	var dy: float = hi.y - lo.y
	var dz: float = hi.z - lo.z
	var q := BuildingMesh._quad
	q.call(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, Vector2(0, 0), Vector2(dx, 0), Vector2(dx, dz), Vector2(0, dz))
	q.call(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(0, 0, 1), Vector2(0, dy), Vector2(dx, dy), Vector2(dx, 0), Vector2(0, 0))
	q.call(st, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(1, 0, 0), Vector2(0, dy), Vector2(dz, dy), Vector2(dz, 0), Vector2(0, 0))
	q.call(st, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(0, 0, -1), Vector2(0, dy), Vector2(dx, dy), Vector2(dx, 0), Vector2(0, 0))
	q.call(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(-1, 0, 0), Vector2(0, dy), Vector2(dz, dy), Vector2(dz, 0), Vector2(0, 0))


# +z 면(평면 z0)에 붙는 문: 돌 문틀(좌우 기둥 + 상인방 + 문턱, 한 면으로 모음) + 널빤지 문판(질감 한 장).
# cx 가운데 x, base_y 바닥 높이, w 문 폭, h 문 높이. 문판은 벽에서 0.015 앞, 문틀은 0.1 튀어나온다.
static func add_door_z(b: PartBuilder, p: Dictionary, cx: float, base_y: float, z0: float, w: float, h: float, window: bool = false, stone_tint: Color = Color(1.12, 1.08, 1.02)) -> void:
	var ts: int = p["ts"]
	var panel_spec: Dictionary = spec(PlaceholderTextures.door_plank(maxi(int(roundf(w * float(ts) * 0.9)), 8), maxi(int(roundf(h * float(ts) * 1.15)), 16), Color(0.6, 0.37, 0.2), window), Color.WHITE, "door_plank", "널빤지 문 판: 세로 판자 + 쇠띠 둘 + 고리 손잡이(작은 질감 한 장)")
	var pa := Vector3(cx - w * 0.5, base_y, z0 + 0.015)
	var pb := Vector3(cx + w * 0.5, base_y, z0 + 0.015)
	var up := Vector3(0.0, h, 0.0)
	var pst: SurfaceTool = b.new_part(panel_spec, pa, pb + up, 40.0)
	BuildingMesh._quad(pst, pa, pb, pb + up, pa + up, Vector3(0.0, 0.0, 1.0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	var stone: Dictionary = stone_spec(p, stone_tint, "door_frame_stone")
	var st: SurfaceTool = b.new_part(stone, Vector3(cx - w * 0.5 - 0.1, base_y, z0), Vector3(cx + w * 0.5 + 0.1, base_y + h + 0.12, z0 + 0.12), 41.0)
	box_st(st, Vector3(cx - w * 0.5 - 0.1, base_y, z0), Vector3(cx - w * 0.5, base_y + h + 0.02, z0 + 0.1))
	box_st(st, Vector3(cx + w * 0.5, base_y, z0), Vector3(cx + w * 0.5 + 0.1, base_y + h + 0.02, z0 + 0.1))
	box_st(st, Vector3(cx - w * 0.5 - 0.12, base_y + h, z0), Vector3(cx + w * 0.5 + 0.12, base_y + h + 0.12, z0 + 0.12))
	box_st(st, Vector3(cx - w * 0.5 - 0.12, base_y, z0), Vector3(cx + w * 0.5 + 0.12, base_y + 0.05, z0 + 0.14))


# 팔각 기둥(통·줄기·잎 덩어리). 옆면 UV 는 둘레 길이 기준.
static func oct(b: PartBuilder, key: String, spec: Dictionary, cx: float, cz: float, r: float, y0: float, y1: float, r_top: float = -1.0) -> void:
	var st: SurfaceTool = b.new_part(spec, Vector3(cx - r, y0, cz - r), Vector3(cx + r, y1, cz + r))
	oct_st(st, cx, cz, r, y0, y1, r_top)


# 이미 만든 부품(SurfaceTool)에 팔각 기둥 하나를 더한다.
static func oct_st(st: SurfaceTool, cx: float, cz: float, r: float, y0: float, y1: float, r_top: float = -1.0) -> void:
	var rt: float = r if r_top < 0.0 else r_top
	var seg: float = TAU * r / 8.0
	var dy: float = y1 - y0
	var pts_b: Array = []
	var pts_t: Array = []

	for i in range(8):
		var a: float = (float(i) + 0.5) * TAU / 8.0
		pts_b.append(Vector3(cx + cos(a) * r, y0, cz + sin(a) * r))
		pts_t.append(Vector3(cx + cos(a) * rt, y1, cz + sin(a) * rt))

	for i in range(8):
		var j: int = (i + 1) % 8
		var am: float = (float(i) + 1.0) * TAU / 8.0
		var n := Vector3(cos(am), (r - rt) / maxf(dy, 0.001), sin(am)).normalized()
		BuildingMesh._quad(st, pts_b[i], pts_b[j], pts_t[j], pts_t[i], n, Vector2(seg * float(i), dy), Vector2(seg * float(i + 1), dy), Vector2(seg * float(i + 1), 0), Vector2(seg * float(i), 0))

	for i in range(8):
		var j2: int = (i + 1) % 8
		BuildingMesh._tri(st, Vector3(cx, y1, cz), pts_t[i], pts_t[j2], Vector3.UP, Vector2(0, 0), Vector2(pts_t[i].x - cx, pts_t[i].z - cz), Vector2(pts_t[j2].x - cx, pts_t[j2].z - cz))


# 둥근 덩어리(덤불·나무 잎): 아래가 평평한 반타원체. 겹겹의 고리(rings)와 둘레(segs) 면으로 윤곽이 둥글게 보인다.
# 면마다 법선을 구면 기준으로 정해 톤이 둥글게 번진다. UV 는 둘레 길이 기준(반복 질감).
static func dome(b: PartBuilder, key: String, spec: Dictionary, cx: float, cz: float, r: float, y0: float, y1: float, rings: int = 3, segs: int = 10) -> void:
	var st: SurfaceTool = b.new_part(spec, Vector3(cx - r, y0, cz - r), Vector3(cx + r, y1, cz + r))
	dome_st(st, cx, cz, r, y0, y1, rings, segs)


# 이미 만든 부품(SurfaceTool)에 둥근 덩어리 하나를 더한다.
static func dome_st(st: SurfaceTool, cx: float, cz: float, r: float, y0: float, y1: float, rings: int = 3, segs: int = 10) -> void:
	var h: float = y1 - y0
	var seg_len: float = TAU * r / float(segs)
	var ring_pts: Array = []

	for k in range(rings + 1):
		var phi: float = (float(k) / float(rings)) * PI * 0.5
		var rr: float = r * cos(phi)
		var yy: float = y0 + h * sin(phi)
		var pts: Array = []

		for i in range(segs):
			var a: float = (float(i) + 0.5) * TAU / float(segs)
			pts.append(Vector3(cx + cos(a) * rr, yy, cz + sin(a) * rr))

		ring_pts.append(pts)

	for k in range(rings):
		var phi_m: float = ((float(k) + 0.5) / float(rings)) * PI * 0.5

		for i in range(segs):
			var j: int = (i + 1) % segs
			var am: float = (float(i) + 1.0) * TAU / float(segs)
			var n := Vector3(cos(am) * cos(phi_m) / r, sin(phi_m) / h, sin(am) * cos(phi_m) / r).normalized()
			var vk0: float = float(k) * h / float(rings)
			var vk1: float = float(k + 1) * h / float(rings)
			BuildingMesh._quad(st, ring_pts[k][i], ring_pts[k][j], ring_pts[k + 1][j], ring_pts[k + 1][i], n, Vector2(seg_len * float(i), -vk0), Vector2(seg_len * float(i + 1), -vk0), Vector2(seg_len * float(i + 1), -vk1), Vector2(seg_len * float(i), -vk1))

	var top: Array = ring_pts[rings]

	for i in range(segs):
		var j2: int = (i + 1) % segs
		BuildingMesh._tri(st, Vector3(cx, y1, cz), top[i], top[j2], Vector3.UP, Vector2(0, 0), Vector2(top[i].x - cx, top[i].z - cz), Vector2(top[j2].x - cx, top[j2].z - cz))


# 삼각 기둥 지붕(얇은 면, 두께 없음): 기둥·차양·작은 지붕용. ridge_x 면 용마루가 x 방향.
static func roof_prism(b: PartBuilder, key: String, spec: Dictionary, x0: float, x1: float, z0: float, z1: float, y0: float, peak_h: float, ridge_x: bool) -> void:
	var st: SurfaceTool = b.new_part(spec, Vector3(x0, y0, z0), Vector3(x1, y0 + peak_h, z1))
	var zc: float = (z0 + z1) * 0.5
	var xc: float = (x0 + x1) * 0.5
	var yp: float = y0 + peak_h

	if ridge_x:
		var sl: float = sqrt(pow((z1 - z0) * 0.5, 2.0) + peak_h * peak_h)
		var nz: float = peak_h / sl
		var ny: float = ((z1 - z0) * 0.5) / sl
		BuildingMesh._quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, yp, zc), Vector3(x0, yp, zc), Vector3(0, ny, nz), Vector2(0, sl), Vector2(x1 - x0, sl), Vector2(x1 - x0, 0), Vector2(0, 0))
		BuildingMesh._quad(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, yp, zc), Vector3(x1, yp, zc), Vector3(0, ny, -nz), Vector2(0, sl), Vector2(x1 - x0, sl), Vector2(x1 - x0, 0), Vector2(0, 0))
		BuildingMesh._tri(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, yp, zc), Vector3(1, 0, 0), Vector2(0, 1), Vector2(z1 - z0, 1), Vector2((z1 - z0) * 0.5, 1.0 - peak_h))
		BuildingMesh._tri(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, yp, zc), Vector3(-1, 0, 0), Vector2(0, 1), Vector2(z1 - z0, 1), Vector2((z1 - z0) * 0.5, 1.0 - peak_h))
	else:
		var sl2: float = sqrt(pow((x1 - x0) * 0.5, 2.0) + peak_h * peak_h)
		var nx: float = peak_h / sl2
		var ny2: float = ((x1 - x0) * 0.5) / sl2
		BuildingMesh._quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(xc, yp, z0), Vector3(xc, yp, z1), Vector3(nx, ny2, 0), Vector2(0, sl2), Vector2(z1 - z0, sl2), Vector2(z1 - z0, 0), Vector2(0, 0))
		BuildingMesh._quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(xc, yp, z1), Vector3(xc, yp, z0), Vector3(-nx, ny2, 0), Vector2(0, sl2), Vector2(z1 - z0, sl2), Vector2(z1 - z0, 0), Vector2(0, 0))
		BuildingMesh._tri(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(xc, yp, z1), Vector3(0, 0, 1), Vector2(0, 1), Vector2(x1 - x0, 1), Vector2((x1 - x0) * 0.5, 1.0 - peak_h))
		BuildingMesh._tri(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(xc, yp, z0), Vector3(0, 0, -1), Vector2(0, 1), Vector2(x1 - x0, 1), Vector2((x1 - x0) * 0.5, 1.0 - peak_h))


# 비스듬한 면 하나(차양 등): 위쪽 모서리 a→b, 아래쪽 모서리 d→c 가 같은 방향
static func slope(b: PartBuilder, key: String, spec: Dictionary, a: Vector3, bb: Vector3, c: Vector3, d: Vector3, n: Vector3, u_len: float, v_len: float) -> void:
	var st: SurfaceTool = b.new_part(spec, a, c)
	b.new_part_bounds(bb, d)
	BuildingMesh._quad(st, a, bb, c, d, n, Vector2(0, 0), Vector2(u_len, 0), Vector2(u_len, v_len), Vector2(0, v_len))


# ---------------------------------------------------------------- 재질 사양 만들기

static func spec(tex: ImageTexture, tint: Color, name: String, note: String = "", normal: ImageTexture = null) -> Dictionary:
	return {"tex": tex, "tint": tint, "name": name, "note": note, "normal": normal}


static func wood(p: Dictionary, tint: Color = Color(0.7, 0.5, 0.32), name: String = "wood") -> Dictionary:
	return spec(_tex("plank", p["ts"]), tint, name, "나무 판(가로 판자 결)")


static func stone_spec(p: Dictionary, tint: Color = Color(1, 1, 1), name: String = "stone") -> Dictionary:
	return spec(_tex("stone", p["ts"]), tint, name, "회색 돌 블록 줄눈")


# ---------------------------------------------------------------- 건물 (박공 지붕)

# rule: height_blocks(벽), roof_blocks, tint(회반죽), roof_tint, chimney, awning, awning_tint, apron, step, planters, sign, extras
# 반환: {"mesh", "specs"(재질 사양 순서), "apron": {"mesh","spec"} 또는 null, "total_blocks", "lo", "hi"(부품이 튀어나온 범위까지 넓힌 정렬 범위)}
static func build_gable(lo: Vector2, hi: Vector2, rule: Dictionary, p: Dictionary) -> Dictionary:
	var ts: int = p["ts"]
	var wall_blocks: float = float(rule["height_blocks"])
	var roof_blocks: float = float(rule.get("roof_blocks", 1.2))
	var wall_h: float = block_h(wall_blocks, p)
	var roof_h: float = block_h(roof_blocks, p)
	var plaster: Color = rule["tint"]
	var roof_tint: Color = rule.get("roof_tint", Color(0.85, 0.44, 0.23))
	var awning_tint: Color = rule.get("awning_tint", Color(0.88, 0.45, 0.22))
	var roof_kind: String = str(rule.get("roof_kind", ""))
	var shape_tokens: PackedStringArray = PackedStringArray(str(rule.get("shape", "")).split(";", false))
	var floors: int = int(rule.get("floors", 1))
	var options: Dictionary = {"chimney": bool(rule.get("chimney", true)), "awning": bool(rule.get("awning", false)), "apron": float(rule.get("apron", 0.4)), "chimney_big": str(rule.get("style", "")) == "forge", "hip": roof_kind == "hip", "roof_style": roof_kind}
	# 돌 기단은 벽보다 먼저(뒤에) 그린다: 윗면이 벽 아래를 덮지 않도록 건물 면들보다 앞서 mesh 에 넣는다.
	var mesh := ArrayMesh.new()
	var pre := PartBuilder.new()

	if bool(rule.get("plinth", false)):
		box(pre, "plinth", stone_spec(p, Color(1.1, 1.05, 1.0), "plinth_stone"), Vector3(lo.x - 0.08, 0.0, lo.y - 0.08), Vector3(hi.x + 0.08, 0.2, hi.y + 0.08))

	var pre_specs: Array = pre.commit_into(mesh)
	var built: Dictionary = BuildingMesh.build(lo, hi, wall_h, roof_h, options, mesh)
	var width: float = hi.x - lo.x
	var depth: float = hi.y - lo.y
	var h_texels: int = int(roundf(wall_blocks * float(p["block_px"])))
	var timber: Color = Color(0.56, 0.38, 0.24) if PlaceholderTextures.clean else Color(0.34, 0.22, 0.14)
	var cells_z: int = maxi(int(roundf(width)), 1)
	var cells_x: int = maxi(int(roundf(depth)), 1)
	var is_shop: bool = str(rule.get("style", "")) == "shop"
	var tex_z: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(width * ts)), h_texels, true, cells_z, plaster, timber, floors)

	var is_forge: bool = str(rule.get("style", "")) == "forge"
	var is_workshop: bool = str(rule.get("style", "")) == "workshop"

	if is_forge:
		tex_z = PlaceholderTextures.forge_front_wall(int(roundf(width * ts)), h_texels, cells_z, plaster)
	elif is_workshop:
		tex_z = PlaceholderTextures.workshop_front_wall(int(roundf(width * ts)), h_texels, cells_z, plaster)
	elif str(rule.get("style", "")) == "barn":
		tex_z = PlaceholderTextures.barn_front_wall(int(roundf(width * ts)), h_texels, cells_z, plaster)
	elif str(rule.get("style", "")) == "stable":
		tex_z = PlaceholderTextures.stable_front_wall(int(roundf(width * ts)), h_texels, cells_z, plaster)

	if is_shop:
		tex_z = PlaceholderTextures.shop_front_wall(int(roundf(width * ts)), h_texels, cells_z, plaster, timber, rule.get("goods_tint", Color(0.88, 0.56, 0.22)))
	var tex_x: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(depth * ts)), h_texels, false, cells_x, plaster, timber, floors)
	var specs: Array = [
		spec(tex_z, Color.WHITE, "wall_front", "카메라 왼쪽 아래를 보는 앞벽 %d×%d px: 문 1(가운데), 창 %d, 나무 뼈대, 아래 돌 기단" % [tex_z.get_width(), tex_z.get_height(), cells_z - 1]),
		spec(tex_x, Color.WHITE, "wall_side", "카메라 오른쪽 아래를 보는 옆벽 %d×%d px: 창 %d, 나무 뼈대, 아래 돌 기단" % [tex_x.get_width(), tex_x.get_height(), cells_x]),
		spec(_tex("flat", ts, roof_tint), Color.WHITE, "roof_tiles", "지붕 기와 %d×%d 한 칸 반복(이음매 없이). 법선 맵 별도" % [ts, ts], PlaceholderTextures.roof_normal(ts)),
		spec(PlaceholderTextures.flat_color(ts, plaster), Color.WHITE, "gable_wall", "박공(지붕 끝 삼각형) 벽 회반죽 단색 %d×%d (삼각형에 줄무늬가 비스듬히 늘어나지 않게 무늬 없음)" % [ts, ts]),
		spec(PlaceholderTextures.flat_color(ts, PlaceholderTextures.soften(roof_tint).darkened(0.1)), Color.WHITE, "roof_trim", "지붕 두께·처마 단면·용마루 덮개 %d×%d 어두운 목재/기와" % [ts, ts]),
		spec(_tex("stone", ts), Color(1.0, 0.82, 0.74), "chimney_stone", "굴뚝 돌 %d×%d 반복" % [ts, ts]),
		spec(PlaceholderTextures.roof_tiles(ts, awning_tint.darkened(0.12)), Color.WHITE, "awning", "차양 기와 %d×%d 반복(지붕 기와와 같은 구조, 색은 가게마다)" % [ts, ts], PlaceholderTextures.roof_normal(ts)),
	]
	# 지붕 기와는 flat_color 대신 기와 질감을 쓰도록 교체(법선 맵과 짝)
	specs[2]["tex"] = PlaceholderTextures.roof_tiles(ts, roof_tint)

	if is_forge:
		specs[0]["emit"] = 1.0  # 화덕 불꽃이 어두운 칸 안에서도 빛나게

	if is_shop:
		specs[0]["emit"] = 0.8  # 진열창 안쪽(따뜻한 밝은 색) 픽셀이 차양 그늘에서도 빛나게

	# ㄱ자(교차 박공): 앞쪽 왼쪽 끝에 용마루가 앞뒤로 달리는 작은 날개를 붙인다. 같은 mesh 에 면 일곱 개를 더 붙이므로 재질도 한 벌 더 만든다.
	var wing_w: float = 0.0
	var wing_specs: Array = []
	var wing_present: Array = []

	if str(rule.get("roof_kind", "")) == "cross" and depth >= 1.6:
		wing_w = clampf(width * 0.38, 1.3, 2.0)
		var wing_d: float = clampf(depth * 0.62, 1.2, 2.0)
		var wopts: Dictionary = {"chimney": false, "awning": false, "apron": 0.0, "hip": false}
		var wbuilt: Dictionary = BuildingMesh.build(Vector2(lo.x, hi.y), Vector2(lo.x + wing_w, hi.y + wing_d), wall_h, roof_h * 0.95, wopts, mesh)
		wing_present = wbuilt["present"]
		var wtex_f: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(wing_w * float(ts))), h_texels, false, 1, plaster, timber)
		var wtex_s: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(wing_d * float(ts))), h_texels, false, maxi(int(roundf(wing_d)), 1), plaster, timber)

		for sp in specs:
			wing_specs.append((sp as Dictionary).duplicate())

		wing_specs[0]["tex"] = wtex_f
		wing_specs[1]["tex"] = wtex_s
		wing_specs[0].erase("emit")

	# --- 부속: 현관 계단, 창 아래 화분, 간판, 건물 앞 소품(extras)
	var b := PartBuilder.new()
	var cells: int = cells_z
	var door_cell: int = cells / 2
	var door_cx: float = lo.x + (float(door_cell) + 0.5) * width / float(cells)
	var story_frac: float = 0.58 if floors >= 2 and h_texels >= 24 else 1.0
	var h_low: int = int(float(h_texels) * story_frac)
	var wall_h_low: float = wall_h * story_frac
	var lay_z: Dictionary = PlaceholderTextures.window_layout(int(roundf(width * ts)), h_low, cells_z)
	var lay_x: Dictionary = PlaceholderTextures.window_layout(int(roundf(depth * ts)), h_low, cells_x)
	var win_top: float = wall_h_low * (1.0 - float(lay_z["wy"]) / float(h_low))
	var win_bottom: float = wall_h_low * (1.0 - float(lay_z["wy"] + lay_z["wh"]) / float(h_low))
	var win_w: float = float(lay_z["ww"]) / float(ts)
	var win_w_x: float = float(lay_x["ww"]) / float(ts)
	var cell_w_z: float = width / float(cells_z)
	var cell_w_x: float = depth / float(cells_x)

	# 창문: 벽 질감에는 창을 그리지 않고, 창 자리마다 틀·유리·창살·창턱 부품을 따로 붙인다(PlaceholderTextures.window_objects).
	var plain_style: bool = str(rule.get("style", "")) == ""
	var skip_front: Array = []
	var skip_side: Array = []
	var cell_w_door: float = width / float(cells_z)

	if HouseShapes.has(shape_tokens, "bay"):
		var bk: int = door_cell + 1 if door_cell + 1 < cells_z else door_cell - 1
		var bcx: float = lo.x + (float(bk) + 0.5) * cell_w_door
		skip_front.append([bcx - 0.75, bcx + 0.75])

	if HouseShapes.has(shape_tokens, "tower"):
		skip_front.append([lo.x - 0.7, lo.x + 1.1])

	if HouseShapes.has(shape_tokens, "annex"):
		var az1: float = hi.y - 0.7
		skip_side.append([maxf(lo.y + 0.5, az1 - 2.2) - 0.3, az1 + 0.3])

	var slots: Dictionary = {"z": [], "x": []}

	if PlaceholderTextures.window_objects:
		slots = HouseShapes.window_slots(lo, hi, wall_h, story_frac, floors, plain_style, skip_front, skip_side, wing_w)
		var attic: Dictionary = {}

		if plain_style and not ["hip", "mansard"].has(roof_kind):
			var ridge_x0: bool = width >= depth
			var ay0: float = wall_h + roof_h * 0.2
			var ay1: float = ay0 + 0.34

			if ridge_x0:
				attic = {"face": "x", "c": (lo.y + hi.y) * 0.5, "y0": ay0, "y1": ay1, "w": 0.3}
			else:
				attic = {"face": "z", "c": (lo.x + hi.x) * 0.5, "y0": ay0, "y1": ay1, "w": 0.3}

		HouseShapes.add_windows(b, p, lo, hi, wall_h, slots, attic)

		if not ["hip", "mansard", "gambrel", "half_hip"].has(roof_kind):
			HouseShapes.gable_truss(b, specs[4], lo, hi, wall_h, roof_h, width >= depth)

	# 덧문: 창 양옆에 창과 같은 높이로. 살(루버) 질감을 쓴다.
	if bool(rule.get("shutters", false)):
		var shut: Dictionary = spec(PlaceholderTextures.shutter(ts, rule.get("shutter_tint", Color(0.36, 0.52, 0.48))), Color.WHITE, "shutter_wood", "덧문 %d×%d 가로 살(청록 계열, 가게마다 색)" % [ts, ts])

		for sl in slots["z"]:
			if bool(sl["upper"]):
				continue

			var half: float = float(sl["w"]) * 0.5 + 0.07
			box(b, "shutter", shut, Vector3(float(sl["c"]) - half - 0.12, sl["y0"], hi.y), Vector3(float(sl["c"]) - half, sl["y1"], hi.y + 0.05))
			box(b, "shutter", shut, Vector3(float(sl["c"]) + half, sl["y0"], hi.y), Vector3(float(sl["c"]) + half + 0.12, sl["y1"], hi.y + 0.05))

		for sx_slot in slots["x"]:
			if bool(sx_slot["upper"]):
				continue

			var halfx: float = float(sx_slot["w"]) * 0.5 + 0.07
			box(b, "shutter", shut, Vector3(hi.x, sx_slot["y0"], float(sx_slot["c"]) - halfx - 0.12), Vector3(hi.x + 0.05, sx_slot["y1"], float(sx_slot["c"]) - halfx))
			box(b, "shutter", shut, Vector3(hi.x, sx_slot["y0"], float(sx_slot["c"]) + halfx), Vector3(hi.x + 0.05, sx_slot["y1"], float(sx_slot["c"]) + halfx + 0.12))

	if bool(rule.get("step", true)) and not HouseShapes.has(shape_tokens, "porch"):
		var door_w: float = float(lay_z["dw"]) / float(ts)
		box(b, "step", stone_spec(p, Color(1.15, 1.1, 1.0), "step"), Vector3(door_cx - door_w * 0.5 - 0.12, 0.0, hi.y), Vector3(door_cx + door_w * 0.5 + 0.12, 0.14, hi.y + 0.3))

	if bool(rule.get("planters", true)):
		for pl in slots["z"]:
			if bool(pl["upper"]):
				continue

			var half_p: float = float(pl["w"]) * 0.5 + 0.08
			var pcx: float = pl["c"]
			var py0: float = float(pl["y0"])
			box(b, "planter", wood(p, Color(0.62, 0.42, 0.28), "planter_box"), Vector3(pcx - half_p, py0 - 0.2, hi.y), Vector3(pcx + half_p, py0 - 0.06, hi.y + 0.14))
			box(b, "flowers", spec(_tex("foliage", ts, Color(0.95, 0.4, 0.55)), Color.WHITE, "planter_flowers", "창 아래 화분 꽃·풀 %d×%d 반복" % [ts, ts]), Vector3(pcx - half_p + 0.02, py0 - 0.06, hi.y + 0.01), Vector3(pcx + half_p - 0.02, py0 + 0.04, hi.y + 0.13))

	if bool(rule.get("sign", false)):
		var sx: float = lo.x + 0.18
		box(b, "sign_bracket", wood(p, Color(0.3, 0.2, 0.12), "sign_bracket"), Vector3(sx, wall_h * 0.8, hi.y), Vector3(sx + 0.03, wall_h * 0.8 + 0.03, hi.y + 0.34))
		box(b, "sign_board", spec(PlaceholderTextures.sign_board(ts), Color.WHITE, "sign_board", "걸린 간판 %d×%d (가게 표시 그림은 가게마다)" % [ts, ts]), Vector3(sx - 0.02, wall_h * 0.8 - 0.24, hi.y + 0.28), Vector3(sx + 0.05, wall_h * 0.8, hi.y + 0.34))

	_add_eave_nubs(b, lo, hi, wall_h, roof_tint, p)
	var display: PartBuilder = null

	display = PartBuilder.new()  # 덩굴 같은 투명 컷아웃·진열 소품은 그림자 없는 별도 묶음으로

	if is_shop:
		_add_fascia(b, p, lo, hi, wall_h, h_texels, str(rule.get("sign_text", "BAKERY")), str(rule.get("sign_icon", "bread")))
		_add_cloth_awning(b, p, lo, hi, wall_h, cells_z, cells_z / 2, awning_tint)

	if bool(rule.get("chimney", true)):
		_add_flue(b, lo, hi, wall_h, roof_h, options, width >= depth, p)

	var smoke_anims: Array = []

	if bool(rule.get("chimney", true)):
		smoke_anims = _smoke_anims(lo, hi, wall_h + roof_h, p, is_forge)

	_add_extras(b, str(rule.get("extras", "")), lo, hi, p, wall_h, display)

	if not shape_tokens.is_empty():
		var ridge_x: bool = width >= depth
		var hs_roof: float = (depth if ridge_x else width) * 0.5 + 0.14
		var len_u: float = (width if ridge_x else depth) + 0.28
		var levels: Array = BuildingMesh.roof_levels(roof_kind if (BuildingMesh.LAYERED_KINDS.has(roof_kind) or roof_kind == "hip") else "", wall_h, roof_h, hs_roof, len_u)
		HouseShapes.apply(shape_tokens, {
			"b": b, "p": p, "lo": lo, "hi": hi, "wall_h": wall_h_low, "wall_h_total": wall_h, "roof_h": roof_h, "ridge_x": ridge_x,
			"hs": hs_roof, "vc": ((lo.y + hi.y) * 0.5 if ridge_x else (lo.x + hi.x) * 0.5), "levels": levels, "plaster": plaster, "timber": timber,
			"story_frac": story_frac, "roof_spec": (specs[2] as Dictionary).duplicate(), "trim_spec": (specs[4] as Dictionary).duplicate(), "wall_spec": (specs[3] as Dictionary).duplicate(),
			"door_cx": door_cx, "door_w": (width * 0.3 if is_forge else float(lay_z["dw"]) / float(ts)), "cells": cells_z, "door_cell": door_cell,
		})

	var extra_specs: Array = b.commit_into(mesh)
	var display_info: Variant = null

	if display != null and display.min_pt.x != INF:
		var dmesh := ArrayMesh.new()
		var dspecs: Array = display.commit_into(dmesh)
		apply_overrides(dspecs, str(rule.get("asset", "")), p)
		display_info = {"mesh": dmesh, "specs": dspecs, "lo": Vector2(display.min_pt.x, display.min_pt.z), "hi": Vector2(display.max_pt.x, display.max_pt.z), "total_blocks": display.max_pt.y * float(p["unit_px_z"]) / float(p["block_px"])}

	var ext_lo: Vector2 = lo
	var ext_hi: Vector2 = hi

	if b.min_pt.x != INF:
		ext_lo = Vector2(minf(lo.x, b.min_pt.x), minf(lo.y, b.min_pt.z))
		ext_hi = Vector2(maxf(hi.x, b.max_pt.x), maxf(hi.y, b.max_pt.z))

	var apron_info: Variant = null
	var apron_mesh: ArrayMesh = built["apron_mesh"]

	if apron_mesh.get_surface_count() > 0:
		apron_info = {"mesh": apron_mesh, "spec": spec(_tex("stone", ts), Color(1.5, 1.4, 1.25), "apron_stone", "건물 둘레 돌 마당 %d×%d 반복(위에서 본 면)" % [ts, ts])}

	if pre.min_pt.x != INF:
		ext_lo = Vector2(minf(ext_lo.x, pre.min_pt.x), minf(ext_lo.y, pre.min_pt.z))
		ext_hi = Vector2(maxf(ext_hi.x, pre.max_pt.x), maxf(ext_hi.y, pre.max_pt.z))

	# 건물 면 중 비어서 mesh 에 안 들어간 것(예: 굴뚝 없음)은 재질 목록에서도 뺀다. 안 그러면 뒤 부품의 재질이 한 칸씩 밀린다.
	var present: Array = built.get("present", [])
	var kept: Array = []

	for i in range(specs.size()):
		if i >= present.size() or present[i]:
			kept.append(specs[i])

	var wing_kept: Array = []

	for i in range(wing_specs.size()):
		if i >= wing_present.size() or wing_present[i]:
			wing_kept.append(wing_specs[i])

	var all_specs: Array = pre_specs + kept + wing_kept + extra_specs
	apply_overrides(all_specs, str(rule.get("asset", "")), p)

	if apron_info != null:
		apply_overrides([apron_info["spec"]], str(rule.get("asset", "")), p)

	return {"mesh": mesh, "specs": all_specs, "display": display_info, "apron": apron_info, "anim": smoke_anims, "total_blocks": wall_blocks + roof_blocks, "lo": ext_lo, "hi": ext_hi}


# extras: "이름:dx:dz;..." — 건물 앞(+z)쪽 중심 기준 옆(dx)·앞(dz) 칸 위치에 작은 소품(통·상자·화분)
# 보이는 쪽 처마 끝에 기와 끝 조각을 한 줄 붙여 가장자리가 물결(톱니) 모양으로 보이게 한다.
static func _add_eave_nubs(b: PartBuilder, lo: Vector2, hi: Vector2, wall_h: float, roof_tint: Color, p: Dictionary) -> void:
	var ts: int = p["ts"]
	var overhang: float = 0.14
	var ridge_x: bool = (hi.x - lo.x) >= (hi.y - lo.y)
	var cap: Dictionary = spec(PlaceholderTextures.flat_color(ts, PlaceholderTextures.soften(roof_tint).darkened(0.12)), Color.WHITE, "eave_tile", "처마 끝 기와 조각 단색 %d×%d (지붕보다 한 톤 어둡게)" % [ts, ts])
	var u0: float = (lo.x if ridge_x else lo.y) - overhang
	var u1: float = (hi.x if ridge_x else hi.y) + overhang
	var v_edge: float = (hi.y if ridge_x else hi.x) + overhang
	var count: int = maxi(int(roundf((u1 - u0) / 0.34)), 2)
	var step: float = (u1 - u0) / float(count)

	for k in range(count):
		var a: float = u0 + step * float(k) + 0.02
		var c: float = u0 + step * float(k + 1) - 0.02

		if ridge_x:
			box(b, "eave", cap, Vector3(a, wall_h - 0.07, v_edge - 0.02), Vector3(c, wall_h + 0.03, v_edge + 0.09))
		else:
			box(b, "eave", cap, Vector3(v_edge - 0.02, wall_h - 0.07, a), Vector3(v_edge + 0.09, wall_h + 0.03, c))


# 굴뚝 머릿돌 위의 어두운 연통 구멍(검은 사각 속)과 안쪽 그을음 띠. 평범한 사각 기둥으로 보이지 않게 한다.
static func _add_flue(b: PartBuilder, lo: Vector2, hi: Vector2, wall_h: float, roof_h: float, options: Dictionary, ridge_x: bool, p: Dictionary) -> void:
	var info: Dictionary = BuildingMesh.chimney_info(lo, hi, wall_h, roof_h, options, ridge_x)
	var ts: int = p["ts"]
	var cx: float = info["cu"] if ridge_x else info["cv"]
	var cz: float = info["cv"] if ridge_x else info["cu"]
	var y: float = info["cap_y"]
	var ch: float = info["ch"]
	var soot: Dictionary = spec(PlaceholderTextures.flat_color(ts, Color(0.1, 0.07, 0.06)), Color.WHITE, "flue", "굴뚝 연통 구멍 단색 %d×%d 거의 검정" % [ts, ts])
	var h: float = ch * 0.62
	box(b, "flue", soot, Vector3(cx - h, y - 0.01, cz - h), Vector3(cx + h, y + 0.02, cz + h), 20.0)


# 굴뚝 연기: 위로 갈수록 커지고 옆으로 번지는 흰 덩어리 셋(정지 상태). 2D 그림의 연기를 대신한다.
# 굴뚝 연기 부품 목록: 연기 덩어리 셋이 굴뚝 위에서 위로 떠오르며 커졌다 작아지길 반복한다(drift). 위상을 어긋나게 해서 끊기지 않고 이어져 보인다.
static func _smoke_anims(lo: Vector2, hi: Vector2, peak: float, p: Dictionary, big: bool = false) -> Array:
	var ts: int = p["ts"]
	var ridge_x: bool = (hi.x - lo.x) >= (hi.y - lo.y)
	var cu: float = (hi.x if ridge_x else hi.y) - BuildingMesh.CHIMNEY_INSET
	var cv: float = ((lo.y + hi.y) * 0.5 if ridge_x else (lo.x + hi.x) * 0.5) + 0.2
	var cx: float = cu if ridge_x else cv
	var cz: float = cv if ridge_x else cu
	var puff: Dictionary = spec(PlaceholderTextures.flat_color(ts, Color(0.92, 0.9, 0.9)), Color.WHITE, "smoke", "굴뚝 연기 단색 %d×%d 연한 회백색" % [ts, ts])
	var y: float = peak + (0.95 if big else 0.52)
	var out: Array = []

	for k in range(3):
		var pb := PartBuilder.new()
		dome(pb, "smoke", puff, 0.0, 0.0, 0.1, 0.0, 0.14, 2, 8)
		var pmesh := ArrayMesh.new()
		var pspecs: Array = pb.commit_into(pmesh)
		out.append({"mesh": pmesh, "specs": pspecs, "pos": Vector3(cx, y, cz), "mode": "drift", "speed": 0.28, "phase": float(k) / 3.0, "rise": 1.0, "drift": Vector3(0.18, 0.0, -0.1), "half": 1.0})

	return out


static func _add_smoke(b: PartBuilder, lo: Vector2, hi: Vector2, peak: float, p: Dictionary, big: bool = false) -> void:
	var ts: int = p["ts"]
	var ridge_x: bool = (hi.x - lo.x) >= (hi.y - lo.y)
	var cu: float = (hi.x if ridge_x else hi.y) - BuildingMesh.CHIMNEY_INSET
	var cv: float = ((lo.y + hi.y) * 0.5 if ridge_x else (lo.x + hi.x) * 0.5) + 0.2
	var cx: float = cu if ridge_x else cv
	var cz: float = cv if ridge_x else cu
	var puff: Dictionary = spec(PlaceholderTextures.flat_color(ts, Color(0.92, 0.9, 0.9)), Color.WHITE, "smoke", "굴뚝 연기 단색 %d×%d 연한 회백색" % [ts, ts])
	var y: float = peak + (0.95 if big else 0.52)

	pass


# 카메라 쪽(+x,+z 대각선)을 보는 평면 카드 한 장(투명 컷아웃). 상자에 꽂힌 종이처럼 세워 둔다. 바닥 중심 (cx, y0, cz), 폭 w, 높이 h.
static func _card(b: PartBuilder, spec: Dictionary, cx: float, y0: float, cz: float, w: float, h: float) -> void:
	var r := Vector3(0.7071, 0.0, -0.7071) * (w * 0.5)
	var c0 := Vector3(cx, y0, cz)
	var pa: Vector3 = c0 - r
	var pb: Vector3 = c0 + r
	var up := Vector3(0, h, 0)
	# 카드는 놓인 면(진열대 윗판 등)보다 항상 나중에 그린다(bias). 안 그러면 왼쪽 카드가 윗판 뒤로 정렬돼 아랫부분이 잘린다.
	var st: SurfaceTool = b.new_part(spec, pa, pb + up, 50.0)
	BuildingMesh._quad(st, pa, pb, pb + up, pa + up, Vector3(0.7071, 0.0, 0.7071), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


# +z 면을 보는 카드(x-y 평면, 법선 +z): 건물 앞벽과 같은 방향을 바라보는 평면(풍차 날개 등). cz 위치, 중심 x=cx, 아래 y0, 폭 w 높이 h.
static func _card_z(b: PartBuilder, spec: Dictionary, cx: float, y0: float, cz: float, w: float, h: float) -> void:
	var pa := Vector3(cx - w * 0.5, y0, cz)
	var pb := Vector3(cx + w * 0.5, y0, cz)
	var up := Vector3(0, h, 0)
	var st: SurfaceTool = b.new_part(spec, pa, pb + up, 50.0)
	BuildingMesh._quad(st, pa, pb, pb + up, pa + up, Vector3(0.0, 0.0, 1.0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


static func _card_spec(kind: String, p: Dictionary) -> Dictionary:
	var sp: Dictionary = spec(PlaceholderTextures.bread_card(kind), Color.WHITE, "card_" + kind, "빵 카드 %s (투명 배경 컷아웃, 어두운 윤곽선)" % kind)
	sp["cutout"] = true
	return sp


# 빵 상자: 윗면이 열린 나무 상자(바닥 + 사방 판). 안에 빵 카드를 세워 꽂는다(여러 장이 겹쳐 "빵이 가득 든" 모양).
static func _add_bread_bin(b: PartBuilder, p: Dictionary, x: float, z: float, kind: String) -> void:
	var plank: Dictionary = wood(p, Color(1.0, 0.84, 0.6), "bin_wood")
	var inner: Dictionary = spec(_tex("flat", p["ts"], Color(0.42, 0.26, 0.14)), Color.WHITE, "bin_inner", "빵 상자 안쪽 어두운 갈색 단색 %d×%d" % [p["ts"], p["ts"]])
	var hx: float = 0.4
	var hz: float = 0.2
	var rim: float = 0.3
	box(b, "bin_bottom", inner, Vector3(x - hx, 0.0, z - hz), Vector3(x + hx, 0.05, z + hz))
	box(b, "bin_back", plank, Vector3(x - hx, 0.0, z - hz), Vector3(x + hx, rim, z - hz + 0.04))
	box(b, "bin_left", plank, Vector3(x - hx, 0.0, z - hz), Vector3(x - hx + 0.04, rim, z + hz))

	var card: Dictionary = _card_spec(kind, p)

	# 간략화: 크게, 세 장만(겹치지 않게 간격을 둠). 상자 밖으로 충분히 솟아서 한눈에 읽히게.
	if kind == "baguette":
		var xs: Array = [-0.24, 0.0, 0.24]
		var hs: Array = [0.95, 1.1, 0.98]

		for i2 in range(xs.size()):
			_card(b, card, x + float(xs[i2]), 0.08, z - 0.02, 0.4, float(hs[i2]))
	else:
		_card(b, card, x - 0.26, 0.12, z + 0.0, 0.56, 0.5)
		_card(b, card, x + 0.26, 0.12, z + 0.0, 0.56, 0.5)
		_card(b, card, x, 0.2, z - 0.1, 0.56, 0.5)

	box(b, "bin_right", plank, Vector3(x + hx - 0.04, 0.0, z - hz), Vector3(x + hx, rim, z + hz))
	box(b, "bin_front", plank, Vector3(x - hx, 0.0, z + hz - 0.04), Vector3(x + hx, rim, z + hz))


# 가게 앞면 천 차양(줄무늬): 진열창 칸 위에만(문 칸은 비움). 앞 가장자리에 톱니 단.
static func _add_cloth_awning(b: PartBuilder, p: Dictionary, lo: Vector2, hi: Vector2, wall_h: float, cells: int, door_cell: int, tint: Color) -> void:
	var ts: int = p["ts"]
	var cloth: Dictionary = spec(PlaceholderTextures.awning_stripes(ts, Color(0.98, 0.95, 0.86), tint), Color.WHITE, "cloth_awning", "천 차양 줄무늬 %d×%d 반복(크림 + 가게 색)" % [ts, ts])
	var width: float = hi.x - lo.x
	var cell_w: float = width / float(cells)
	# 차양 윗변은 진열창 윗변(shop_front_wall 의 win_top = 높이의 28%)에 붙이고, 가로는 창 폭(칸 왼쪽 3px ~ 오른쪽 2px 안쪽)보다 조금 넓게 한다.
	var y_top: float = wall_h * 0.72 + 0.03
	var y_bot: float = y_top - 0.3
	var out: float = 0.5
	var win_l: float = 3.0 / float(ts)
	var win_r: float = 2.0 / float(ts)

	for k in range(cells):
		if k == door_cell:
			continue

		var x0: float = lo.x + float(k) * cell_w + win_l - 0.06
		var x1: float = lo.x + float(k + 1) * cell_w - win_r + 0.06
		slope(b, "awning", cloth, Vector3(x0, y_top, hi.y), Vector3(x1, y_top, hi.y), Vector3(x1, y_bot, hi.y + out), Vector3(x0, y_bot, hi.y + out), Vector3(0, out, (y_top - y_bot)).normalized(), x1 - x0, 1.0)
		var tooth: int = maxi(int(roundf((x1 - x0) / 0.2)), 2)
		var tw: float = (x1 - x0) / float(tooth)

		for t in range(tooth):
			if t % 2 == 0:
				box(b, "valance", cloth, Vector3(x0 + tw * float(t), y_bot - 0.09, hi.y + out - 0.03), Vector3(x0 + tw * float(t + 1), y_bot, hi.y + out + 0.01))


# 가게 이름 간판(앞벽 맨 위): 가로로 긴 판, 정면(+z)에 한 장 그림.
static func _add_fascia(b: PartBuilder, p: Dictionary, lo: Vector2, hi: Vector2, wall_h: float, h_texels: int, text: String = "BAKERY", icon: String = "bread") -> void:
	var ts: int = p["ts"]
	var sign_px: int = 14
	var sign_h: float = float(sign_px) * wall_h / float(h_texels)
	var x0: float = lo.x + 0.08
	var x1: float = hi.x - 0.08
	# 지붕 처마선 위로 솟게: 아래 끝은 처마 조금 아래, 위는 처마 위로 올라온다(처마 0.14 + 조각 0.09 보다 앞에 둔다).
	var y0: float = wall_h - 0.2
	var y1: float = y0 + sign_h
	var z: float = hi.y + 0.28
	var tex: ImageTexture = PlaceholderTextures.bakery_fascia(int(roundf((x1 - x0) * float(ts))), sign_px, text, icon)
	var board: Dictionary = spec(tex, Color.WHITE, "bakery_fascia", "가게 간판 %d×%d (%s 글자 + 양끝 그림), 한 장 전체" % [tex.get_width(), sign_px, text])
	var back: Dictionary = spec(_tex("flat", ts, Color(0.36, 0.22, 0.12)), Color.WHITE, "sign_frame", "간판 뒤판·테두리 어두운 나무 단색 %d×%d" % [ts, ts])
	box(b, "fascia_back", back, Vector3(x0 - 0.02, y0 - 0.02, hi.y + 0.1), Vector3(x1 + 0.02, y1 + 0.02, z - 0.01), 40.0)
	var st: SurfaceTool = b.new_part(board, Vector3(x0, y0, z), Vector3(x1, y1, z + 0.01), 41.0)
	BuildingMesh._quad(st, Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1 - 0.01, z), Vector3(x0, y1 - 0.01, z), Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


# 긴 진열대: 앞이 열린 긴 나무 카운터 위에 둥근 빵을 한 개씩 간격을 두고 올려놓는다(바게트·상자 진열은 빼고 간략화).
static func _add_long_counter(b: PartBuilder, p: Dictionary, x: float, z: float, length: float) -> void:
	var body: Dictionary = wood(p, Color(1.0, 0.84, 0.6), "counter_wood")
	var top: Dictionary = spec(_tex("flat", p["ts"], Color(0.98, 0.9, 0.74)), Color.WHITE, "counter_top", "진열대 윗판 단색 %d×%d 밝은 베이지" % [p["ts"], p["ts"]])
	var hl: float = length * 0.5
	var hd: float = 0.2
	box(b, "counter", body, Vector3(x - hl, 0.0, z - hd), Vector3(x + hl, 0.46, z + hd))
	box(b, "counter_top", top, Vector3(x - hl - 0.02, 0.46, z - hd - 0.03), Vector3(x + hl + 0.02, 0.5, z + hd + 0.03))
	var count: int = maxi(int(floorf(length / 0.45)), 2)
	var gap: float = length / float(count)
	var card: Dictionary = _card_spec("loaf", p)

	for i in range(count):
		var cx: float = x - hl + gap * (float(i) + 0.5)
		_card(b, card, cx, 0.5, z + (0.02 if i % 2 == 0 else -0.02), 0.4, 0.36)


# 진열대: 나무 카운터. 윗면에 위에서 본 빵 그림(바게트·둥근 빵)을 평면으로 붙인다(입체 빵은 작아서 어색해 보였다).
static func _add_counter(b: PartBuilder, p: Dictionary, x: float, z: float) -> void:
	var wood_a: Dictionary = wood(p, Color(1.0, 0.82, 0.58), "counter_wood")
	var top: Dictionary = spec(PlaceholderTextures.bread_counter_top(p["ts"]), Color.WHITE, "counter_top_bread", "진열대 윗면 %d×%d: 쟁반 + 바게트 둘 + 둥근 빵 셋(위에서 본 평면 그림, 앞쪽 17×8 칸 사용)" % [p["ts"], p["ts"]])
	box(b, "counter", wood_a, Vector3(x - 0.46, 0.0, z - 0.2), Vector3(x + 0.46, 0.5, z + 0.2))
	box(b, "counter_top", top, Vector3(x - 0.48, 0.5, z - 0.22), Vector3(x + 0.48, 0.55, z + 0.22))


# 덩굴: 벽에 붙는 투명 컷아웃 카드(잎 + 분홍 꽃)를 위아래로 여러 장. front=true 면 앞벽(+z, x 가운데 값), 아니면 옆벽(+x, z 가운데 값).
static func _wall_card(b: PartBuilder, spec: Dictionary, a: float, y0: float, c: float, w: float, h: float, front: bool) -> void:
	var up := Vector3(0, h, 0)
	var pa: Vector3
	var pb: Vector3
	var n: Vector3

	if front:
		pa = Vector3(a - w * 0.5, y0, c)
		pb = Vector3(a + w * 0.5, y0, c)
		n = Vector3(0, 0, 1)
	else:
		pa = Vector3(a, y0, c + w * 0.5)
		pb = Vector3(a, y0, c - w * 0.5)
		n = Vector3(1, 0, 0)

	var st: SurfaceTool = b.new_part(spec, pa, pb + up, 45.0)
	BuildingMesh._quad(st, pa, pb, pb + up, pa + up, n, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


static func _add_vines(b: PartBuilder, p: Dictionary, a: float, c: float, wall_h: float, width: float, front: bool) -> void:
	var sp: Dictionary = spec(PlaceholderTextures.vine_card(), Color.WHITE, "vine", "덩굴 카드 (투명 배경 컷아웃, 잎 + 분홍 꽃)")
	sp["cutout"] = true
	var n: int = maxi(int(roundf(wall_h / 0.55)), 2)
	var cw: float = width

	for i in range(n):
		var jitter: float = (0.12 if i % 2 == 0 else -0.1) * width
		var y0: float = wall_h - 0.55 * float(i + 1)
		_wall_card(b, sp, a + jitter * (1.0 if front else 0.0), maxf(y0, 0.05), c + (0.0 if front else jitter), cw * (1.0 - 0.08 * float(i)), 0.62, front)


# 모루: 나무 그루터기 위에 쇠 모루(받침·허리·윗판·뿔).
static func _add_anvil(b: PartBuilder, p: Dictionary, x: float, z: float) -> void:
	var ts: int = p["ts"]
	var bark: Dictionary = wood(p, Color(0.5, 0.34, 0.2), "stump_wood")
	var iron: Dictionary = spec(_tex("flat", ts, Color(0.36, 0.38, 0.48)), Color.WHITE, "anvil_iron", "모루 쇠 단색 %d×%d 푸른 회색" % [ts, ts])
	var top: Dictionary = spec(_tex("flat", ts, Color(0.55, 0.57, 0.68)), Color.WHITE, "anvil_top", "모루 윗판 단색 %d×%d 밝은 회색" % [ts, ts])
	oct(b, "stump", bark, x, z, 0.2, 0.0, 0.28, 0.18)
	box(b, "anvil_base", iron, Vector3(x - 0.16, 0.28, z - 0.1), Vector3(x + 0.16, 0.34, z + 0.1))
	box(b, "anvil_waist", iron, Vector3(x - 0.08, 0.34, z - 0.07), Vector3(x + 0.08, 0.42, z + 0.07))
	box(b, "anvil_top", top, Vector3(x - 0.2, 0.42, z - 0.1), Vector3(x + 0.2, 0.5, z + 0.1))
	box(b, "anvil_horn", top, Vector3(x + 0.2, 0.44, z - 0.05), Vector3(x + 0.34, 0.5, z + 0.05))


# 장작 더미: 세워 둔 통나무 여러 개(뾰족한 무리).
static func _add_logs(b: PartBuilder, p: Dictionary, x: float, z: float) -> void:
	var bark: Dictionary = wood(p, Color(0.56, 0.38, 0.22), "log_wood")
	var offs: Array = [Vector2(-0.14, -0.06), Vector2(0.0, 0.1), Vector2(0.14, -0.06), Vector2(-0.07, 0.05), Vector2(0.08, 0.0)]
	var hs: Array = [0.5, 0.58, 0.46, 0.64, 0.52]

	for i in range(offs.size()):
		oct(b, "log", bark, x + offs[i].x, z + offs[i].y, 0.1, 0.0, float(hs[i]), 0.095)


# 걸이 간판: 벽에서 앞으로 뻗은 팔 끝에 빵 그림 판이 매달린다. 판은 카메라가 보는 +x 쪽 면에 그림이 나온다.
static func _add_hang_sign(b: PartBuilder, p: Dictionary, x: float, wall_z: float, tip_dz: float, wall_h: float, icon: String = "bread") -> void:
	var iron: Dictionary = spec(_tex("flat", p["ts"], Color(0.2, 0.2, 0.24)), Color.WHITE, "iron", "검은 쇠(기둥·테두리) 단색 %d×%d" % [p["ts"], p["ts"]])
	var frame_wood: Dictionary = spec(_tex("flat", p["ts"], Color(0.36, 0.22, 0.12)), Color.WHITE, "sign_frame", "간판 뒤판·테두리 어두운 나무 단색 %d×%d" % [p["ts"], p["ts"]])
	var board_tex: ImageTexture = PlaceholderTextures.bread_sign() if icon == "bread" else PlaceholderTextures.icon_sign(icon)
	var board: Dictionary = spec(board_tex, Color.WHITE, "%s_sign" % icon, "걸이 간판 그림 16×12 (%s), +x 쪽 면 한 장" % icon)
	var y_arm: float = wall_h * 0.8
	var tip_z: float = wall_z + tip_dz
	box(b, "arm", iron, Vector3(x - 0.02, y_arm, wall_z), Vector3(x + 0.02, y_arm + 0.04, tip_z + 0.02))
	var z0: float = tip_z - 0.8
	var z1: float = tip_z - 0.04
	var y1: float = y_arm - 0.07
	var y0: float = y1 - 0.6
	box(b, "chain", iron, Vector3(x - 0.01, y1, z0 + 0.06), Vector3(x + 0.01, y_arm, z0 + 0.08))
	box(b, "chain", iron, Vector3(x - 0.01, y1, z1 - 0.08), Vector3(x + 0.01, y_arm, z1 - 0.06))
	box(b, "sign_back", frame_wood, Vector3(x - 0.04, y0, z0), Vector3(x + 0.0, y1, z1))
	# 그림 면(+x): 판 앞에 얇은 면 하나(한 장 전체를 판 크기에 맞춰 늘림)
	var st: SurfaceTool = b.new_part(board, Vector3(x, y0, z0), Vector3(x + 0.01, y1, z1))
	BuildingMesh._quad(st, Vector3(x + 0.01, y0, z1), Vector3(x + 0.01, y0, z0), Vector3(x + 0.01, y1, z0), Vector3(x + 0.01, y1, z1), Vector3(1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


static func _add_extras(b: PartBuilder, text: String, lo: Vector2, hi: Vector2, p: Dictionary, wall_h: float = 2.0, display: PartBuilder = null) -> void:
	if text.strip_edges().is_empty():
		return

	var cx: float = (lo.x + hi.x) * 0.5

	for item in text.split(";"):
		var f: PackedStringArray = item.strip_edges().split(":")

		if f.size() < 3:
			continue

		var x: float = cx + float(f[1])
		var z: float = hi.y + float(f[2])
		# 상자·카운터·간판처럼 앞에 놓는 진열 소품은 따로 그림자 없는 묶음(display)에 넣는다(투명 컷아웃이 섞여 있어서).
		var tb: PartBuilder = b

		if display != null and f[0] in ["counter", "hang_sign", "basket", "bin_baguette", "bin_loaf", "long_counter", "vine", "vine_side"]:
			tb = display

		match f[0]:
			"barrel":
				oct(b, "barrel", spec(_tex("barrel", p["ts"]), Color.WHITE, "barrel", "통(배럴) 옆면 %d×%d: 세로 판자 + 쇠테 2줄" % [p["ts"], p["ts"]]), x, z, 0.2, 0.0, 0.5, 0.17)
			"crate":
				box(b, "crate", spec(_tex("crate", p["ts"]), Color.WHITE, "crate", "나무 상자 %d×%d: 판자 + 모서리 틀 + 가로 보강" % [p["ts"], p["ts"]]), Vector3(x - 0.2, 0.0, z - 0.2), Vector3(x + 0.2, 0.4, z + 0.2))
			"sack":
				box(b, "sack", spec(_tex("flat", p["ts"], Color(0.8, 0.72, 0.52)), Color.WHITE, "sack", "자루 %d×%d 베이지" % [p["ts"], p["ts"]]), Vector3(x - 0.16, 0.0, z - 0.14), Vector3(x + 0.16, 0.34, z + 0.14))
			"hay":
				box(b, "hay", spec(_tex("flat", p["ts"], Color(0.85, 0.72, 0.3)), Color.WHITE, "hay", "건초 %d×%d 노랑" % [p["ts"], p["ts"]]), Vector3(x - 0.3, 0.0, z - 0.22), Vector3(x + 0.3, 0.38, z + 0.22))
			"counter":
				_add_counter(tb, p, x, z)
			"hang_sign":
				_add_hang_sign(tb, p, x, hi.y, z - hi.y, wall_h, str(f[3]) if f.size() > 3 else "bread")
			"basket":
				oct(tb, "basket", spec(PlaceholderTextures.crate(p["ts"], Color(0.62, 0.42, 0.22)), Color.WHITE, "basket", "바구니 옆면 %d×%d 갈색 엮음" % [p["ts"], p["ts"]]), x, z, 0.19, 0.0, 0.26, 0.17)
				_card(tb, _card_spec("loaf", p), x - 0.05, 0.16, z, 0.28, 0.25)
				_card(tb, _card_spec("loaf", p), x + 0.07, 0.2, z - 0.03, 0.26, 0.23)
			"vine":
				_add_vines(tb, p, x, hi.y + 0.03, wall_h, float(f[3]) if f.size() > 3 else 0.8, true)
			"vine_side":
				_add_vines(tb, p, hi.x + 0.03, lo.y + (hi.y - lo.y) * 0.5 + float(f[1]), wall_h, float(f[3]) if f.size() > 3 else 0.8, false)
			"anvil":
				_add_anvil(b, p, x, z)
			"logs":
				_add_logs(b, p, x, z)
			"hang_icon":
				_add_hang_sign(b, p, x, hi.y, z - hi.y, wall_h, str(f[3]) if f.size() > 3 else "anvil")
			"long_counter":
				_add_long_counter(tb, p, x, z, float(f[3]) if f.size() > 3 else 1.6)
			"bin_baguette":
				_add_bread_bin(tb, p, x, z, "baguette")
			"bin_loaf":
				_add_bread_bin(tb, p, x, z, "loaf")
			"bush":
				dome(b, "bush", spec(_tex("foliage", p["ts"], Color(0.95, 0.4, 0.55)), Color.WHITE, "bush", "덤불 %d×%d 반복(꽃 점)" % [p["ts"], p["ts"]]), x, z, 0.27, 0.0, 0.34)


# ---------------------------------------------------------------- 가판대 종류(데이터)

# canopy: stripe(줄무늬 천) / solid(단색 천 + 톱니 단) / tent(사방 천막) / shingle(나무 지붕 한쪽 경사) / umbrella(큰 파라솔)
# goods: 카운터 위에 놓는 상품 카드 목록("종류" 또는 "종류:#색"), hang: 차양 앞에 매다는 카드, props: 양옆 소품(crate/barrel/basket/sack)
const STALL_TYPES: Dictionary = {
	"bread": {"canopy": "stripe", "c1": "d9503c", "c2": "fbf3e0", "counter": "d8a870", "skirt": "e8c89a", "goods": ["loaf", "loaf", "baguette"], "hang": [], "props": ["basket", "sack"]},
	"fruit": {"canopy": "stripe", "c1": "4a9a4a", "c2": "fbf3e0", "counter": "b88c5c", "skirt": "6aaa5a", "goods": ["apple", "orange", "lemon", "grape"], "hang": [], "props": ["crate", "barrel"]},
	"fish": {"canopy": "stripe", "c1": "4a86c0", "c2": "f2f6fa", "counter": "8aa8c0", "skirt": "5a96d0", "goods": ["fish", "fish"], "hang": ["fish"], "props": ["barrel", "crate"]},
	"meat": {"canopy": "stripe", "c1": "c8403a", "c2": "fbf3e0", "counter": "b07a54", "skirt": "d85a50", "goods": ["ham", "ham"], "hang": ["ham"], "props": ["crate", "barrel"]},
	"cloth": {"canopy": "solid", "c1": "a050c0", "c2": "", "counter": "c89a6a", "skirt": "d05080", "goods": ["cloth:#d05080", "cloth:#4a86c0", "cloth:#e8b030", "cloth:#4a9a4a"], "hang": ["cloth:#a050c0"], "props": ["sack", "basket"]},
	"herb": {"canopy": "shingle", "c1": "7a5a34", "c2": "", "counter": "9a7a4c", "skirt": "5a8a3a", "goods": ["herb", "herb", "flower:#e8e050"], "hang": ["herb"], "props": ["basket", "barrel"]},
	"potion": {"canopy": "solid", "c1": "5a3a8a", "c2": "", "counter": "6a4a7a", "skirt": "7a5aa0", "goods": ["bottle:#d04040", "bottle:#4a86e0", "bottle:#4ac060", "bottle:#c050d0"], "hang": ["bottle:#e0b030"], "props": ["barrel", "crate"]},
	"flower": {"canopy": "umbrella", "c1": "e06080", "c2": "fbf3e0", "counter": "d8b078", "skirt": "f0a0b0", "goods": ["flower:#e06080", "flower:#f0e050", "flower:#b070e0", "flower:#ffffff"], "hang": [], "props": ["basket", "basket"]},
	"pottery": {"canopy": "tent", "c1": "d8b060", "c2": "", "counter": "a07a50", "skirt": "c89860", "goods": ["jar", "jar", "jar"], "hang": [], "props": ["barrel", "barrel"]},
	"books": {"canopy": "solid", "c1": "2a6a58", "c2": "", "counter": "6a4a30", "skirt": "3a8a70", "goods": ["book:#a03030", "book:#3050a0", "book:#d0a030", "book:#308050"], "hang": [], "props": ["crate", "sack"]},
	"spice": {"canopy": "tent", "c1": "d08030", "c2": "fbf3e0", "counter": "b0804c", "skirt": "e0a050", "goods": ["jar", "herb", "apple"], "hang": ["herb"], "props": ["sack", "sack"]},
	"cheese": {"canopy": "shingle", "c1": "a05030", "c2": "", "counter": "c8a060", "skirt": "e8c860", "goods": ["lemon", "lemon", "loaf"], "hang": ["ham"], "props": ["barrel", "crate"]},
}


static func _goods_spec(token: String, ts: int) -> Dictionary:
	var parts: PackedStringArray = token.split(":")
	var color := Color(0.85, 0.25, 0.25)

	if parts.size() > 1:
		color = Color.html(parts[1])

	var sp: Dictionary = spec(PlaceholderTextures.goods_card(parts[0], color), Color.WHITE, "goods_" + parts[0], "가판대 상품 카드 %s (투명 배경 컷아웃, 어두운 윤곽선)" % parts[0])
	sp["cutout"] = true
	return sp


# ---------------------------------------------------------------- 나무·소품 도우미

# 잡티 단색 질감 사양(잎·돌·건초 등)
static func _noise_spec(ts: int, base: Color, dot: Color, name: String, seed_value: int = 1, tint_c: Color = Color.WHITE, density: float = 0.14) -> Dictionary:
	return spec(PlaceholderTextures.noise_tex(ts, base, dot, seed_value, density), tint_c, name, "%s 잡티 단색 %d×%d" % [name, ts, ts])


# 단색 사양
static func _flat_spec(ts: int, color: Color, name: String) -> Dictionary:
	return spec(_tex("flat", ts, color), Color.WHITE, name, "%s 단색 %d×%d" % [name, ts, ts])


# 잎 덩어리 여러 개를 한 면에 모은다. 한 면 안에서는 넣은 순서대로 그려지므로 먼(x+z 작은)·낮은 것부터 정렬해서 넣는다.
# lobes: [{dx, dz, r, y0, y1}]
static func _crown(b: PartBuilder, sp: Dictionary, cx: float, cz: float, lobes: Array, rings: int = 3, segs: int = 12) -> void:
	var sorted: Array = lobes.duplicate()
	sorted.sort_custom(func(a, c): return float(a["dx"]) + float(a["dz"]) + (float(a["y0"]) + float(a["y1"])) * 0.01 < float(c["dx"]) + float(c["dz"]) + (float(c["y0"]) + float(c["y1"])) * 0.01)
	var lo_v := Vector3(INF, INF, INF)
	var hi_v := Vector3(-INF, -INF, -INF)

	for l in sorted:
		lo_v = Vector3(minf(lo_v.x, cx + float(l["dx"]) - float(l["r"])), minf(lo_v.y, float(l["y0"])), minf(lo_v.z, cz + float(l["dz"]) - float(l["r"])))
		hi_v = Vector3(maxf(hi_v.x, cx + float(l["dx"]) + float(l["r"])), maxf(hi_v.y, float(l["y1"])), maxf(hi_v.z, cz + float(l["dz"]) + float(l["r"])))

	var st: SurfaceTool = b.new_part(sp, lo_v, hi_v)

	for l in sorted:
		dome_st(st, cx + float(l["dx"]), cz + float(l["dz"]), float(l["r"]), float(l["y0"]), float(l["y1"]), rings, segs)


# ---------------------------------------------------------------- 가판대 상품(3D 오브젝트)

# 색별로 부품 하나(SurfaceTool)를 모아 쓴다(같은 색은 면 하나). cache: 색 문자열 → SurfaceTool. 만든 순서대로 나중에 그려진다(bias).
static func _goods_st(b: PartBuilder, cache: Dictionary, color: Color, ts: int, a: Vector3, c: Vector3) -> SurfaceTool:
	var key: String = color.to_html(false)

	if cache.has(key):
		return cache[key]

	var sp: Dictionary = spec(PlaceholderTextures.flat_color(ts, color), Color.WHITE, "goods_" + key, "가판대 상품 단색 %d×%d" % [ts, ts])
	var st: SurfaceTool = b.new_part(sp, a, c, 45.0 + float(cache.size()) * 0.05)
	cache[key] = st
	return st


# 상품 하나를 (x, y, z) 바닥 중심에 세운다. token: "이름" 또는 "이름:#색". 높이는 대략 0.1~0.2.
static func _goods_obj(b: PartBuilder, cache: Dictionary, token: String, x: float, y: float, z: float, ts: int, a: Vector3, c: Vector3) -> void:
	var parts: PackedStringArray = token.split(":")
	var name: String = parts[0]
	var col: Color = Color.html(parts[1]) if parts.size() > 1 else Color(0.85, 0.25, 0.25)
	col = PlaceholderTextures.soften(col) if PlaceholderTextures.clean else col
	var gs := func(cl: Color) -> SurfaceTool: return _goods_st(b, cache, cl, ts, a, c)

	match name:
		"apple", "orange", "lemon":
			var fc: Color = {"apple": Color(0.82, 0.22, 0.2), "orange": Color(0.95, 0.56, 0.16), "lemon": Color(0.96, 0.86, 0.24)}[name]
			var st_f: SurfaceTool = gs.call(fc)
			dome_st(st_f, x - 0.075, z, 0.075, y, y + 0.12, 2, 8)
			dome_st(st_f, x + 0.075, z, 0.075, y, y + 0.12, 2, 8)
			dome_st(st_f, x, z - 0.01, 0.075, y + 0.08, y + 0.2, 2, 8)
		"grape":
			var st_g: SurfaceTool = gs.call(Color(0.5, 0.25, 0.62))

			for gp in [Vector2(-0.07, 0.0), Vector2(0.07, 0.0), Vector2(0.0, 0.0)]:
				dome_st(st_g, x + gp.x, z + gp.y, 0.06, y + (0.07 if gp.x == 0.0 else 0.0), y + (0.17 if gp.x == 0.0 else 0.1), 2, 8)
		"loaf":
			var st_l: SurfaceTool = gs.call(Color(0.8, 0.52, 0.24))
			dome_st(st_l, x, z, 0.11, y, y + 0.12, 2, 8)
			var st_l2: SurfaceTool = gs.call(Color(0.92, 0.7, 0.4))
			dome_st(st_l2, x, z, 0.06, y + 0.09, y + 0.14, 2, 8)
		"baguette":
			var st_b: SurfaceTool = gs.call(Color(0.86, 0.62, 0.3))
			box_st(st_b, Vector3(x - 0.17, y, z - 0.07), Vector3(x + 0.17, y + 0.06, z - 0.02))
			box_st(st_b, Vector3(x - 0.17, y, z + 0.02), Vector3(x + 0.17, y + 0.06, z + 0.07))
			box_st(st_b, Vector3(x - 0.15, y + 0.06, z - 0.025), Vector3(x + 0.15, y + 0.11, z + 0.025))
		"fish":
			var st_fi: SurfaceTool = gs.call(Color(0.62, 0.74, 0.84))
			var st_ft: SurfaceTool = gs.call(Color(0.42, 0.56, 0.74))

			for fz in [-0.07, 0.07]:
				box_st(st_fi, Vector3(x - 0.12, y, z + fz - 0.035), Vector3(x + 0.07, y + 0.055, z + fz + 0.035))
				box_st(st_ft, Vector3(x + 0.07, y, z + fz - 0.05), Vector3(x + 0.14, y + 0.05, z + fz + 0.05))
		"ham":
			var st_h: SurfaceTool = gs.call(Color(0.8, 0.4, 0.36))
			oct_st(st_h, x, z, 0.085, y, y + 0.13, 0.06)
			var st_hb: SurfaceTool = gs.call(Color(0.94, 0.9, 0.82))
			box_st(st_hb, Vector3(x - 0.02, y + 0.13, z - 0.02), Vector3(x + 0.02, y + 0.19, z + 0.02))
		"cloth":
			var st_c: SurfaceTool = gs.call(col)
			box_st(st_c, Vector3(x - 0.11, y, z - 0.08), Vector3(x + 0.11, y + 0.04, z + 0.08))
			var st_c2: SurfaceTool = gs.call(col.lightened(0.18))
			box_st(st_c2, Vector3(x - 0.1, y + 0.04, z - 0.07), Vector3(x + 0.1, y + 0.08, z + 0.07))
			var st_c3: SurfaceTool = gs.call(col.darkened(0.12))
			box_st(st_c3, Vector3(x - 0.11, y + 0.08, z - 0.08), Vector3(x + 0.11, y + 0.12, z + 0.08))
		"herb":
			var st_hr: SurfaceTool = gs.call(Color(0.34, 0.6, 0.3))
			oct_st(st_hr, x, z, 0.04, y, y + 0.16, 0.085)
			var st_ht: SurfaceTool = gs.call(Color(0.62, 0.44, 0.26))
			oct_st(st_ht, x, z, 0.048, y + 0.02, y + 0.05, 0.048)
		"flower":
			var st_fs: SurfaceTool = gs.call(Color(0.36, 0.6, 0.3))
			var st_fh: SurfaceTool = gs.call(col)

			for fo in [Vector2(-0.07, 0.0), Vector2(0.0, 0.03), Vector2(0.07, 0.0)]:
				oct_st(st_fs, x + fo.x, z + fo.y, 0.012, y, y + 0.12 + fo.y, 0.012)
				dome_st(st_fh, x + fo.x, z + fo.y, 0.05, y + 0.1 + fo.y, y + 0.17 + fo.y, 2, 8)
		"bottle":
			var st_bo: SurfaceTool = gs.call(col)
			oct_st(st_bo, x, z, 0.05, y, y + 0.12, 0.05)
			oct_st(st_bo, x, z, 0.022, y + 0.12, y + 0.18, 0.022)
			var st_bc: SurfaceTool = gs.call(Color(0.7, 0.52, 0.3))
			box_st(st_bc, Vector3(x - 0.018, y + 0.18, z - 0.018), Vector3(x + 0.018, y + 0.21, z + 0.018))
		"jar":
			var st_j: SurfaceTool = gs.call(Color(0.74, 0.46, 0.28))
			oct_st(st_j, x, z, 0.075, y, y + 0.12, 0.068)
			var st_jl: SurfaceTool = gs.call(Color(0.5, 0.3, 0.2))
			oct_st(st_jl, x, z, 0.06, y + 0.12, y + 0.15, 0.06)
		"book":
			var st_k1: SurfaceTool = gs.call(col)
			box_st(st_k1, Vector3(x - 0.1, y, z - 0.07), Vector3(x - 0.055, y + 0.2, z + 0.07))
			var st_k2: SurfaceTool = gs.call(col.lightened(0.25))
			box_st(st_k2, Vector3(x - 0.05, y, z - 0.07), Vector3(x - 0.005, y + 0.17, z + 0.07))
			var st_k3: SurfaceTool = gs.call(col.darkened(0.2))
			box_st(st_k3, Vector3(x + 0.0, y, z - 0.07), Vector3(x + 0.045, y + 0.19, z + 0.07))
		_:
			var st_d: SurfaceTool = gs.call(col)
			dome_st(st_d, x, z, 0.08, y, y + 0.14, 2, 8)


# 불길 한 갈래: 아래가 둥글고 위가 뾰족한 물방울 모양(팔각 토막 4개를 쌓음). 바닥이 원점, 높이 h, 폭 w.
static func _flame_tongue(spec_f: Dictionary, h: float, w: float) -> Dictionary:
	var fb := PartBuilder.new()
	var st: SurfaceTool = fb.new_part(spec_f, Vector3(-w, 0.0, -w), Vector3(w, h, w))
	oct_st(st, 0.0, 0.0, w * 0.75, 0.0, h * 0.22, w * 1.0)
	oct_st(st, 0.0, 0.0, w * 1.0, h * 0.22, h * 0.5, w * 0.7)
	oct_st(st, 0.0, 0.0, w * 0.7, h * 0.5, h * 0.8, w * 0.32)
	oct_st(st, 0.0, 0.0, w * 0.32, h * 0.8, h, w * 0.04)
	var m := ArrayMesh.new()
	var specs: Array = fb.commit_into(m)
	return {"mesh": m, "specs": specs}


# 천막/지붕 네 면(사방으로 경사진 피라미드): 중심 (cx, cz), 반폭 (hx, hz), 아래 y0(처마), 꼭대기 y1.
static func pyramid(b: PartBuilder, key: String, spec: Dictionary, cx: float, cz: float, hx: float, hz: float, y0: float, y1: float) -> void:
	var st: SurfaceTool = b.new_part(spec, Vector3(cx - hx, y0, cz - hz), Vector3(cx + hx, y1, cz + hz))
	var apex := Vector3(cx, y1, cz)
	var c0 := Vector3(cx - hx, y0, cz - hz)
	var c1 := Vector3(cx + hx, y0, cz - hz)
	var c2 := Vector3(cx + hx, y0, cz + hz)
	var c3 := Vector3(cx - hx, y0, cz + hz)
	var rise: float = y1 - y0
	var nx: Vector3 = Vector3(rise, hx, 0.0).normalized()
	var nz: Vector3 = Vector3(0.0, hz, rise).normalized()
	var sl_x: float = sqrt(hx * hx + rise * rise)
	var sl_z: float = sqrt(hz * hz + rise * rise)
	# +z(앞) / +x / -z / -x 네 면. UV: 처마 따라 u, 경사 따라 v
	BuildingMesh._tri(st, c3, c2, apex, Vector3(0.0, nz.y, nz.z), Vector2(0, sl_z), Vector2(hx * 2.0, sl_z), Vector2(hx, 0))
	BuildingMesh._tri(st, c2, c1, apex, nx, Vector2(0, sl_x), Vector2(hz * 2.0, sl_x), Vector2(hz, 0))
	BuildingMesh._tri(st, c1, c0, apex, Vector3(0.0, nz.y, -nz.z), Vector2(0, sl_z), Vector2(hx * 2.0, sl_z), Vector2(hx, 0))
	BuildingMesh._tri(st, c0, c3, apex, Vector3(-nx.x, nx.y, 0.0).normalized(), Vector2(0, sl_x), Vector2(hz * 2.0, sl_x), Vector2(hz, 0))


# 가판대 한 칸(종류는 STALL_TYPES). lo/hi 는 발자국. 반환: 전체 높이(칸).
static func _build_stall(b: PartBuilder, lo: Vector2, hi: Vector2, kind: String, p: Dictionary) -> float:
	var ts: int = p["ts"]
	var d: Dictionary = STALL_TYPES[kind]
	var c1: Color = PlaceholderTextures.soften(Color.html(str(d["c1"])))
	var c2: Color = Color.html(str(d["c2"])) if str(d["c2"]) != "" else c1.lightened(0.35)
	var counter_c: Color = Color.html(str(d["counter"]))
	var skirt_c: Color = PlaceholderTextures.soften(Color.html(str(d["skirt"])))
	var bark: Dictionary = wood(p, Color(0.42, 0.3, 0.2), "bark")
	var canopy_kind: String = str(d["canopy"])
	var stripes: Dictionary = spec(PlaceholderTextures.awning_stripes(ts, c2, c1), Color.WHITE, "stall_cloth_stripe", "가판대 줄무늬 천 %d×%d (가판대마다 색 다름)" % [ts, ts])
	var solid: Dictionary = spec(_tex("flat", ts, c1), Color.WHITE, "stall_cloth_solid", "가판대 단색 천 %d×%d" % [ts, ts])
	var shingle: Dictionary = spec(PlaceholderTextures.roof_tiles(ts, c1), Color.WHITE, "stall_shingle", "가판대 나무 지붕 기와 %d×%d" % [ts, ts])
	var x0: float = lo.x + 0.08
	var x1: float = hi.x - 0.08
	var z0: float = lo.y + 0.08
	var z1: float = hi.y - 0.08
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var top: float = 2.0

	# 카운터와 앞 천(스커트)
	var counter_d: float = clampf((z1 - z0) * 0.5, 0.45, 0.7)
	box(b, "counter", wood(p, counter_c, "stall_counter"), Vector3(x0, 0.0, z1 - counter_d), Vector3(x1, 0.65, z1))
	box(b, "skirt", stripes if canopy_kind == "stripe" else spec(_tex("flat", ts, skirt_c), Color.WHITE, "stall_skirt", "가판대 카운터 앞 천 단색 %d×%d" % [ts, ts]), Vector3(x0 - 0.02, 0.05, z1), Vector3(x1 + 0.02, 0.62, z1 + 0.03))

	# 기둥
	if canopy_kind == "umbrella":
		oct(b, "pole", bark, cx, cz - 0.05, 0.05, 0.0, 1.7, 0.05)
	else:
		for corner in [Vector2(x0, z0), Vector2(x1 - 0.07, z0), Vector2(x0, z1 - 0.07), Vector2(x1 - 0.07, z1 - 0.07)]:
			box(b, "post", bark, Vector3(corner.x, 0.0, corner.y), Vector3(corner.x + 0.07, 1.6, corner.y + 0.07))

	# 지붕
	match canopy_kind:
		"stripe", "solid":
			var cloth: Dictionary = stripes if canopy_kind == "stripe" else solid
			slope(b, "awning", cloth, Vector3(x0 - 0.05, 1.75, z0), Vector3(x1 + 0.05, 1.75, z0), Vector3(x1 + 0.05, 1.35, z1 + 0.18), Vector3(x0 - 0.05, 1.35, z1 + 0.18), Vector3(0, 0.6, 0.8), x1 - x0 + 0.1, 1.0)
			var n_teeth: int = maxi(int(roundf((x1 - x0) / 0.2)), 3)
			var tw: float = (x1 - x0 + 0.1) / float(n_teeth)

			for t in range(n_teeth):
				var tooth_spec: Dictionary = cloth if (t % 2 == 0) else spec(_tex("flat", ts, c1.darkened(0.2) if canopy_kind == "solid" else c2), Color.WHITE, "stall_valance", "가판대 처마 단 단색 %d×%d" % [ts, ts])
				box(b, "valance", tooth_spec, Vector3(x0 - 0.05 + tw * float(t), 1.26, z1 + 0.15), Vector3(x0 - 0.05 + tw * float(t + 1), 1.35, z1 + 0.19))

			top = 1.8
		"shingle":
			slope(b, "awning", shingle, Vector3(x0 - 0.05, 1.8, z0 - 0.04), Vector3(x1 + 0.05, 1.8, z0 - 0.04), Vector3(x1 + 0.05, 1.4, z1 + 0.18), Vector3(x0 - 0.05, 1.4, z1 + 0.18), Vector3(0, 0.6, 0.8), x1 - x0 + 0.1, 1.0)
			top = 1.85
		"tent":
			pyramid(b, "tent", stripes if str(d["c2"]) != "" else solid, cx, cz, (x1 - x0) * 0.5 + 0.12, (z1 - z0) * 0.5 + 0.12, 1.45, 2.1)
			top = 2.15
		"umbrella":
			dome(b, "umbrella", stripes, cx, cz - 0.05, 0.9, 1.55, 2.05, 3, 12)
			top = 2.1

	# 상품 오브젝트: 카운터 위 한 줄, 같은 종류끼리 묶어서(AABBCC) 균등 간격
	var goods: Array = d["goods"]
	var kinds: Array = []

	for g in goods:
		if not kinds.has(str(g)):
			kinds.append(str(g))

	var gcache: Dictionary = {}
	var ga := Vector3(x0, 0.6, z0)
	var gc := Vector3(x1, 1.4, z1)

	if kinds.size() > 0:
		var span_g: float = x1 - x0 - 0.7  # 카운터 양 끝에서 0.35 씩 안쪽
		var n_g: int = maxi(int(span_g / 0.42) + 1, 2)
		var step_g: float = span_g / float(n_g - 1)

		for gi in range(n_g):
			var tok: String = kinds[mini(gi * kinds.size() / n_g, kinds.size() - 1)]
			_goods_obj(b, gcache, tok, x0 + 0.35 + step_g * float(gi), 0.65, z1 - counter_d * 0.5, ts, ga, gc)

	# 매다는 상품(차양 앞 가장자리 아래): 가운데 몇 개만 균등 간격, 가는 줄로 처마에 매단다
	var hang: Array = d["hang"]

	if hang.size() > 0:
		var span_h: float = x1 - x0 - 1.0
		var n_h: int = maxi(int(span_h / 0.6) + 1, 2)
		var step_h: float = span_h / float(n_h - 1)
		var hstring: Dictionary = spec(PlaceholderTextures.flat_color(ts, Color(0.3, 0.22, 0.14)), Color.WHITE, "goods_string", "상품 매단 줄 단색 %d×%d" % [ts, ts])

		for hi_idx in range(n_h):
			var hx: float = x0 + 0.5 + step_h * float(hi_idx)
			_goods_obj(b, gcache, str(hang[0]), hx, 1.0, z1 + 0.12, ts, ga, gc)
			box(b, "string", hstring, Vector3(hx - 0.006, 1.2, z1 + 0.115), Vector3(hx + 0.006, 1.36, z1 + 0.125), 46.0)

	# 양옆 소품
	var props: Array = d["props"]

	for i in range(mini(props.size(), 2)):
		var px: float = x0 - 0.12 if i == 0 else x1 + 0.12
		var pz: float = z1 - 0.18
		var pk: String = str(props[i])

		match pk:
			"barrel":
				oct(b, "barrel", spec(_tex("barrel", ts), Color.WHITE, "barrel", "통(배럴) 옆면 %d×%d" % [ts, ts]), px, pz, 0.17, 0.0, 0.42, 0.15)
			"crate":
				box(b, "crate", spec(_tex("crate", ts), Color.WHITE, "crate", "나무 상자 %d×%d" % [ts, ts]), Vector3(px - 0.15, 0.0, pz - 0.15), Vector3(px + 0.15, 0.3, pz + 0.15))
			"sack":
				box(b, "sack", spec(_tex("flat", ts, Color(0.8, 0.72, 0.52)), Color.WHITE, "sack", "자루 %d×%d 베이지" % [ts, ts]), Vector3(px - 0.13, 0.0, pz - 0.12), Vector3(px + 0.13, 0.3, pz + 0.12))
			_:
				oct(b, "basket", spec(PlaceholderTextures.crate(ts, Color(0.62, 0.42, 0.22)), Color.WHITE, "basket", "바구니 옆면 %d×%d" % [ts, ts]), px, pz, 0.16, 0.0, 0.22, 0.14)

	return top


# ---------------------------------------------------------------- 소품

static func build_prop(style: String, lo: Vector2, hi: Vector2, rule: Dictionary, p: Dictionary) -> Dictionary:
	var ts: int = p["ts"]
	var b := PartBuilder.new()
	var c: Vector2 = (lo + hi) * 0.5
	var sx: float = hi.x - lo.x
	var sz: float = hi.y - lo.y
	var along_x: bool = sx >= sz
	var total: float = 1.0
	var anim_parts: Array = []  # 돌아가는 부품: {mesh, specs, pos, speed(rad/s)}
	var roof_tint: Color = rule.get("roof_tint", Color(0.8, 0.42, 0.25))
	var tint: Color = rule.get("tint", Color(1, 1, 1))
	var bark: Dictionary = wood(p, Color(0.42, 0.3, 0.2), "bark")
	var iron: Dictionary = spec(_tex("flat", ts, Color(0.2, 0.2, 0.24)), Color.WHITE, "iron", "검은 쇠(기둥·테두리) 단색 %d×%d" % [ts, ts])
	var roof_spec: Dictionary = spec(PlaceholderTextures.roof_tiles(ts, roof_tint), Color.WHITE, "small_roof_tiles", "작은 지붕 기와 %d×%d 반복" % [ts, ts], PlaceholderTextures.roof_normal(ts))

	match style:
		"tree":
			var leaf: Dictionary = spec(_tex("foliage", ts, Color(0.9, 0.3, 0.3)), tint, "tree_foliage", "나뭇잎 %d×%d 반복(짙은 초록 + 밝은 점 + 빨간 열매 점)" % [ts, ts])
			leaf["sway"] = 0.04
			var variant: String = str(rule.get("variant", "round"))
			var bark_dark: Dictionary = wood(p, Color(0.34, 0.24, 0.17), "bark_dark")
			var root_spec: Dictionary = wood(p, Color(0.4, 0.28, 0.19), "bark_root")

			if variant == "pine":
				var pine: Dictionary = _noise_spec(ts, Color(0.16, 0.38, 0.24), Color(0.3, 0.55, 0.36), "pine_foliage", 3)
				pine["sway"] = 0.04
				oct(b, "root", root_spec, c.x, c.y, 0.17, 0.0, 0.16, 0.12)
				oct(b, "bark", bark, c.x, c.y, 0.12, 0.1, 0.8, 0.09)
				oct(b, "cone", pine, c.x, c.y, 0.7, 0.45, 1.2, 0.28)
				oct(b, "cone", pine, c.x, c.y, 0.56, 0.95, 1.7, 0.22)
				oct(b, "cone", pine, c.x, c.y, 0.42, 1.45, 2.2, 0.16)
				oct(b, "cone", pine, c.x, c.y, 0.28, 1.95, 2.7, 0.03)
				total = 2.75
			elif variant == "birch":
				var white: Dictionary = _noise_spec(ts, Color(0.92, 0.92, 0.86), Color(0.3, 0.28, 0.26), "birch_bark", 5, Color.WHITE, 0.06)
				var light_leaf: Dictionary = _noise_spec(ts, Color(0.4, 0.62, 0.3), Color(0.58, 0.78, 0.4), "birch_foliage", 7)
				light_leaf["sway"] = 0.04
				oct(b, "bark", white, c.x, c.y, 0.09, 0.0, 1.5, 0.07)
				_crown(b, light_leaf, c.x, c.y, [{"dx": -0.2, "dz": -0.12, "r": 0.4, "y0": 1.2, "y1": 1.9}, {"dx": 0.0, "dz": 0.0, "r": 0.5, "y0": 1.35, "y1": 2.15}, {"dx": 0.18, "dz": 0.12, "r": 0.36, "y0": 1.25, "y1": 1.95}, {"dx": 0.04, "dz": 0.02, "r": 0.3, "y0": 1.9, "y1": 2.4}], 2, 10)
				total = 2.45
			elif variant == "big_oak":
				oct(b, "root", root_spec, c.x, c.y, 0.3, 0.0, 0.2, 0.2)
				oct(b, "bark", bark, c.x, c.y, 0.2, 0.15, 1.1, 0.15)
				_crown(b, leaf, c.x, c.y, [{"dx": -0.45, "dz": -0.3, "r": 0.5, "y0": 0.95, "y1": 1.6}, {"dx": 0.0, "dz": 0.0, "r": 0.95, "y0": 0.95, "y1": 1.9}, {"dx": 0.5, "dz": 0.3, "r": 0.5, "y0": 0.95, "y1": 1.6}, {"dx": 0.04, "dz": 0.03, "r": 0.68, "y0": 1.55, "y1": 2.45}, {"dx": 0.12, "dz": 0.08, "r": 0.4, "y0": 2.1, "y1": 2.65}], 3, 14)
				total = 2.7
			elif variant == "autumn":
				var fall: Dictionary = _noise_spec(ts, Color(0.86, 0.5, 0.18), Color(0.96, 0.78, 0.3), "autumn_foliage", 9)
				fall["sway"] = 0.04
				oct(b, "root", root_spec, c.x, c.y, 0.17, 0.0, 0.16, 0.12)
				oct(b, "bark", bark, c.x, c.y, 0.13, 0.1, 1.0, 0.1)
				_crown(b, fall, c.x, c.y, [{"dx": -0.3, "dz": -0.2, "r": 0.42, "y0": 0.9, "y1": 1.5}, {"dx": 0.0, "dz": 0.0, "r": 0.66, "y0": 0.85, "y1": 1.6}, {"dx": 0.3, "dz": 0.22, "r": 0.4, "y0": 0.9, "y1": 1.45}, {"dx": 0.06, "dz": 0.04, "r": 0.5, "y0": 1.4, "y1": 2.05}, {"dx": 0.1, "dz": 0.07, "r": 0.28, "y0": 1.9, "y1": 2.35}])
				total = 2.35
			elif variant == "cherry":
				var bloom: Dictionary = _noise_spec(ts, Color(0.93, 0.5, 0.66), Color(1.0, 0.8, 0.88), "cherry_blossom", 11, Color.WHITE, 0.18)
				bloom["sway"] = 0.04
				oct(b, "root", bark_dark, c.x, c.y, 0.15, 0.0, 0.14, 0.11)
				oct(b, "bark", bark_dark, c.x, c.y, 0.11, 0.1, 1.05, 0.08)
				box(b, "limb", bark_dark, Vector3(c.x - 0.38, 0.95, c.y - 0.03), Vector3(c.x + 0.0, 1.03, c.y + 0.03))
				box(b, "limb", bark_dark, Vector3(c.x, 1.0, c.y - 0.03), Vector3(c.x + 0.36, 1.08, c.y + 0.03))
				_crown(b, bloom, c.x, c.y, [{"dx": -0.45, "dz": -0.25, "r": 0.4, "y0": 1.0, "y1": 1.6}, {"dx": 0.0, "dz": 0.0, "r": 0.7, "y0": 1.0, "y1": 1.85}, {"dx": 0.44, "dz": 0.26, "r": 0.4, "y0": 1.02, "y1": 1.6}, {"dx": 0.05, "dz": 0.04, "r": 0.5, "y0": 1.6, "y1": 2.25}])
				total = 2.3
			elif variant == "willow":
				var wleaf: Dictionary = _noise_spec(ts, Color(0.38, 0.58, 0.3), Color(0.55, 0.74, 0.4), "willow_foliage", 13)
				wleaf["sway"] = 0.04
				oct(b, "root", bark_dark, c.x, c.y, 0.2, 0.0, 0.18, 0.15)
				oct(b, "bark", bark_dark, c.x, c.y, 0.15, 0.12, 1.2, 0.11)
				var wst: SurfaceTool = b.new_part(wleaf, Vector3(c.x - 0.95, 0.4, c.y - 0.95), Vector3(c.x + 0.95, 1.9, c.y + 0.95))
				dome_st(wst, c.x, c.y, 0.9, 1.2, 1.95, 3, 12)

				for wi in range(12):
					var wa: float = float(wi) * TAU / 12.0
					var wr: float = 0.78 + (0.1 if wi % 2 == 0 else 0.0)
					var wx: float = c.x + cos(wa) * wr
					var wz: float = c.y + sin(wa) * wr
					var wl: float = 0.55 + float((wi * 5) % 4) * 0.12
					box_st(wst, Vector3(wx - 0.025, 1.3 - wl, wz - 0.025), Vector3(wx + 0.025, 1.3, wz + 0.025))

				total = 2.0
			elif variant == "dead":
				oct(b, "root", bark_dark, c.x, c.y, 0.2, 0.0, 0.16, 0.14)
				oct(b, "bark", bark_dark, c.x, c.y, 0.13, 0.1, 1.9, 0.05)
				box(b, "limb", bark_dark, Vector3(c.x - 0.5, 1.15, c.y - 0.03), Vector3(c.x, 1.22, c.y + 0.03))
				box(b, "limb", bark_dark, Vector3(c.x - 0.5, 1.22, c.y - 0.03), Vector3(c.x - 0.43, 1.6, c.y + 0.03))
				box(b, "limb", bark_dark, Vector3(c.x, 1.35, c.y - 0.03), Vector3(c.x + 0.42, 1.42, c.y + 0.03))
				box(b, "limb", bark_dark, Vector3(c.x + 0.36, 1.42, c.y - 0.03), Vector3(c.x + 0.43, 1.78, c.y + 0.03))
				box(b, "limb", bark_dark, Vector3(c.x - 0.03, 1.55, c.y), Vector3(c.x + 0.03, 1.62, c.y + 0.32))
				total = 1.95
			elif variant == "poplar":
				var pl: Dictionary = _noise_spec(ts, Color(0.28, 0.52, 0.26), Color(0.46, 0.7, 0.36), "poplar_foliage", 15)
				pl["sway"] = 0.04
				oct(b, "bark", bark, c.x, c.y, 0.1, 0.0, 0.8, 0.08)
				_crown(b, pl, c.x, c.y, [{"dx": 0.0, "dz": 0.0, "r": 0.42, "y0": 0.6, "y1": 1.4}, {"dx": 0.02, "dz": 0.01, "r": 0.4, "y0": 1.15, "y1": 2.0}, {"dx": 0.04, "dz": 0.02, "r": 0.3, "y0": 1.75, "y1": 2.6}, {"dx": 0.06, "dz": 0.03, "r": 0.16, "y0": 2.3, "y1": 2.95}], 3, 10)
				total = 3.0
			else:
				oct(b, "root", root_spec, c.x, c.y, 0.2, 0.0, 0.16, 0.14)
				oct(b, "bark", bark, c.x, c.y, 0.13, 0.1, 1.0, 0.1)
				_crown(b, leaf, c.x, c.y, [{"dx": -0.34, "dz": -0.2, "r": 0.4, "y0": 0.9, "y1": 1.5}, {"dx": 0.0, "dz": 0.0, "r": 0.66, "y0": 0.85, "y1": 1.6}, {"dx": 0.32, "dz": 0.22, "r": 0.38, "y0": 0.9, "y1": 1.45}, {"dx": 0.06, "dz": 0.04, "r": 0.5, "y0": 1.4, "y1": 2.05}, {"dx": 0.1, "dz": 0.07, "r": 0.3, "y0": 1.9, "y1": 2.35}])
				total = 2.35
		"hay":
			var hay: Dictionary = spec(_tex("plank", ts), Color(1.1, 0.95, 0.5), "hay_bale", "건초 단 %d×%d (노란 결)" % [ts, ts])
			box(b, "bale", hay, Vector3(c.x - 0.5, 0.0, c.y - 0.3), Vector3(c.x + 0.0, 0.4, c.y + 0.3))
			box(b, "bale", hay, Vector3(c.x + 0.05, 0.0, c.y - 0.28), Vector3(c.x + 0.5, 0.4, c.y + 0.3))
			box(b, "bale", hay, Vector3(c.x - 0.3, 0.4, c.y - 0.25), Vector3(c.x + 0.2, 0.8, c.y + 0.25))
			dome(b, "stack", spec(_tex("foliage", ts, Color(0.9, 0.8, 0.3)), Color(1.1, 1.0, 0.55), "hay_stack", "건초 더미 %d×%d" % [ts, ts]), c.x + 0.6, c.y + 0.35, 0.34, 0.0, 0.52, 2, 8)
			total = 0.85
		"barrels":
			var barrel: Dictionary = spec(_tex("barrel", ts), Color.WHITE, "barrel", "통 %d×%d" % [ts, ts])
			oct(b, "barrel", barrel, c.x - 0.3, c.y - 0.1, 0.24, 0.0, 0.5, 0.2)
			oct(b, "barrel", barrel, c.x + 0.22, c.y - 0.15, 0.24, 0.0, 0.5, 0.2)
			oct(b, "barrel", barrel, c.x - 0.05, c.y + 0.28, 0.24, 0.0, 0.5, 0.2)
			oct(b, "barrel", barrel, c.x - 0.05, c.y + 0.02, 0.22, 0.5, 0.95, 0.18)
			total = 1.0
		"well":
			oct(b, "stone", stone_spec(p, Color(1, 1, 1), "well_stone"), c.x, c.y, 0.58, 0.0, 0.55)
			oct(b, "water", spec(_tex("flat", ts, Color(0.18, 0.3, 0.5)), Color.WHITE, "well_water", "우물 물 단색 %d×%d 어두운 파랑" % [ts, ts]), c.x, c.y, 0.44, 0.5, 0.53)
			box(b, "post", bark, Vector3(c.x - 0.52, 0.0, c.y - 0.04), Vector3(c.x - 0.44, 1.5, c.y + 0.04))
			box(b, "post", bark, Vector3(c.x + 0.44, 0.0, c.y - 0.04), Vector3(c.x + 0.52, 1.5, c.y + 0.04))
			roof_prism(b, "roof", roof_spec, c.x - 0.66, c.x + 0.66, c.y - 0.55, c.y + 0.55, 1.5, 0.45, true)
			total = 1.95
		"stall":
			if STALL_TYPES.has(str(rule.get("variant", ""))):
				total = _build_stall(b, lo, hi, str(rule["variant"]), p)
			else:
				var cloth: Dictionary = spec(PlaceholderTextures.awning_stripes(ts, Color(0.96, 0.92, 0.8), roof_tint), Color.WHITE, "stall_awning", "가판대 차양 줄무늬 %d×%d 반복(가게마다 색 다름)" % [ts, ts])
				var goods_tint: Color = rule.get("goods_tint", Color(0.8, 0.55, 0.25))
				var goods: Dictionary = spec(_tex("flat", ts, goods_tint), Color.WHITE, "stall_goods", "가판대 상품 단색 %d×%d(빵·생선·옷감·약초 중 하나)" % [ts, ts])
				var x0: float = lo.x + 0.08
				var x1: float = hi.x - 0.08
				var z0: float = lo.y + 0.08
				var z1: float = hi.y - 0.08
				box(b, "counter", wood(p, Color(0.66, 0.46, 0.3), "stall_counter"), Vector3(x0, 0.0, z1 - 0.45), Vector3(x1, 0.65, z1))
				for corner in [Vector2(x0, z0), Vector2(x1 - 0.07, z0), Vector2(x0, z1 - 0.07), Vector2(x1 - 0.07, z1 - 0.07)]:
					box(b, "post", bark, Vector3(corner.x, 0.0, corner.y), Vector3(corner.x + 0.07, 1.6, corner.y + 0.07))

				slope(b, "awning", cloth, Vector3(x0 - 0.05, 1.75, z0), Vector3(x1 + 0.05, 1.75, z0), Vector3(x1 + 0.05, 1.35, z1 + 0.18), Vector3(x0 - 0.05, 1.35, z1 + 0.18), Vector3(0, 0.6, 0.8), x1 - x0 + 0.1, 1.0)
				var gx: float = x0 + 0.15

				while gx < x1 - 0.2:
					box(b, "goods", goods, Vector3(gx, 0.65, z1 - 0.38), Vector3(gx + 0.16, 0.77, z1 - 0.1))
					gx += 0.26

				total = 1.8
		"tower":
			var stone_t: Dictionary = stone_spec(p, Color(1.05, 1.0, 0.95), "tower_stone")
			var band: Dictionary = stone_spec(p, Color(0.8, 0.78, 0.74), "tower_band")
			var dark: Dictionary = spec(_tex("flat", ts, Color(0.16, 0.14, 0.18)), Color.WHITE, "tower_dark", "탑 창·문 안쪽 어두운 단색 %d×%d" % [ts, ts])
			var door_c: Dictionary = spec(_tex("flat", ts, Color(0.5, 0.32, 0.18)), Color.WHITE, "tower_door", "탑 문 갈색 단색 %d×%d" % [ts, ts])
			var hx: float = minf(sx, sz) * 0.5
			var wall_top: float = 3.7
			box(b, "tower_base", band, Vector3(c.x - hx - 0.06, 0.0, c.y - hx - 0.06), Vector3(c.x + hx + 0.06, 0.35, c.y + hx + 0.06))
			box(b, "tower_body", stone_t, Vector3(c.x - hx, 0.35, c.y - hx), Vector3(c.x + hx, wall_top, c.y + hx))
			box(b, "tower_band", band, Vector3(c.x - hx - 0.05, 2.5, c.y - hx - 0.05), Vector3(c.x + hx + 0.05, 2.65, c.y + hx + 0.05))
			box(b, "tower_band", band, Vector3(c.x - hx - 0.08, wall_top - 0.15, c.y - hx - 0.08), Vector3(c.x + hx + 0.08, wall_top, c.y + hx + 0.08))
			# 앞(+z)면: 문 + 창 슬릿 둘, 옆(+x)면: 창 슬릿 둘
			add_door_z(b, p, c.x, 0.35, c.y + hx, 0.46, 0.98)

			for yy in [1.8, 3.0]:
				box(b, "slit", dark, Vector3(c.x - 0.05, yy, c.y + hx), Vector3(c.x + 0.05, yy + 0.4, c.y + hx + 0.03))
				box(b, "slit", dark, Vector3(c.x + hx, yy, c.y - 0.05), Vector3(c.x + hx + 0.03, yy + 0.4, c.y + 0.05))

			var roof_tw: Dictionary = spec(PlaceholderTextures.roof_tiles(ts, rule.get("roof_tint", Color(0.36, 0.5, 0.66))), Color.WHITE, "tower_roof", "탑 지붕 기와 %d×%d" % [ts, ts], PlaceholderTextures.roof_normal(ts))
			pyramid(b, "tower_roof", roof_tw, c.x, c.y, hx + 0.25, hx + 0.25, wall_top, wall_top + 1.7)
			oct(b, "finial", bark, c.x, c.y, 0.03, wall_top + 1.7, wall_top + 2.2, 0.02)
			dome(b, "finial_ball", spec(_tex("flat", ts, Color(0.96, 0.8, 0.3)), Color.WHITE, "finial_gold", "탑 꼭대기 장식 금색 단색 %d×%d" % [ts, ts]), c.x, c.y, 0.07, wall_top + 2.18, wall_top + 2.3, 2, 8)
			total = 2.6
		"dome":
			var wall_d: Dictionary = stone_spec(p, Color(1.15, 1.1, 1.0), "dome_stone")
			var trim_d: Dictionary = stone_spec(p, Color(0.85, 0.83, 0.8), "dome_trim")
			var glass_d: Dictionary = spec(_tex("flat", ts, Color(0.5, 0.7, 0.9)), Color.WHITE, "dome_glass", "둥근 건물 창 하늘색 단색 %d×%d" % [ts, ts])
			var door_d: Dictionary = spec(_tex("flat", ts, Color(0.5, 0.32, 0.18)), Color.WHITE, "dome_door", "둥근 건물 문 갈색 단색 %d×%d" % [ts, ts])
			var r0: float = minf(sx, sz) * 0.5 - 0.1
			oct(b, "dome_steps", trim_d, c.x, c.y, r0 + 0.15, 0.0, 0.18)
			oct(b, "dome_drum", wall_d, c.x, c.y, r0, 0.18, 2.0)
			oct(b, "dome_band", trim_d, c.x, c.y, r0 + 0.05, 1.9, 2.05)
			add_door_z(b, p, c.x, 0.18, c.y + r0 * 0.9239, 0.46, 0.95, true)

			var ap_d: float = r0 * 0.9239  # 팔각형 변 중심까지 거리(면 평면 위치)
			# 면 하나에 창 하나씩, 면 가운데에: +x 면은 창 부품, 카메라를 보는 대각선 면은 카드(틀·유리·창살)
			var dwp: Dictionary = HouseShapes.win_parts(b, p, Vector3(c.x + ap_d - 0.05, 0.8, c.y - 0.4), Vector3(c.x + ap_d + 0.15, 1.7, c.y + 0.4))
			HouseShapes.win_on_x(dwp, c.y, 0.85, 1.55, 0.14, c.x + ap_d)
			var dd: float = 0.7071
			var frame_dc: Dictionary = spec(PlaceholderTextures.flat_color(ts, Color(0.95, 0.92, 0.84)), Color.WHITE, "dome_win_frame", "돔 창틀 크림 단색 %d×%d" % [ts, ts])
			var glass_dc: Dictionary = spec(PlaceholderTextures.flat_color(ts, Color(0.5, 0.74, 0.92)), Color.WHITE, "dome_win_glass", "돔 창 유리 단색 %d×%d" % [ts, ts])
			_card(b, frame_dc, c.x + dd * (ap_d + 0.02), 0.82, c.y + dd * (ap_d + 0.02), 0.36, 0.76)
			_card(b, glass_dc, c.x + dd * (ap_d + 0.035), 0.88, c.y + dd * (ap_d + 0.035), 0.28, 0.64)
			_card(b, frame_dc, c.x + dd * (ap_d + 0.05), 0.88, c.y + dd * (ap_d + 0.05), 0.03, 0.64)
			_card(b, frame_dc, c.x + dd * (ap_d + 0.05), 1.19, c.y + dd * (ap_d + 0.05), 0.28, 0.03)

			var dome_tex: Dictionary = spec(PlaceholderTextures.roof_tiles(ts, rule.get("roof_tint", Color(0.42, 0.4, 0.68))), Color.WHITE, "dome_roof", "둥근 지붕 기와 %d×%d" % [ts, ts])
			dome(b, "dome", dome_tex, c.x, c.y, r0 + 0.1, 2.0, 3.3, 4, 12)
			oct(b, "finial", bark, c.x, c.y, 0.03, 3.3, 3.8, 0.02)
			dome(b, "finial_ball", spec(_tex("flat", ts, Color(0.96, 0.8, 0.3)), Color.WHITE, "finial_gold", "꼭대기 장식 금색 단색 %d×%d" % [ts, ts]), c.x, c.y, 0.07, 3.78, 3.9, 2, 8)
			total = 2.8
		"windmill":
			var body_w: Dictionary = stone_spec(p, Color(1.2, 1.15, 1.05), "mill_stone")
			var roof_m: Dictionary = spec(PlaceholderTextures.roof_tiles(ts, rule.get("roof_tint", Color(0.7, 0.36, 0.28))), Color.WHITE, "mill_roof", "풍차 지붕 기와 %d×%d" % [ts, ts])
			var door_m: Dictionary = spec(_tex("flat", ts, Color(0.5, 0.32, 0.18)), Color.WHITE, "mill_door", "풍차 문 갈색 단색 %d×%d" % [ts, ts])
			var dark_m: Dictionary = spec(_tex("flat", ts, Color(0.16, 0.14, 0.18)), Color.WHITE, "mill_dark", "풍차 창 어두운 단색 %d×%d" % [ts, ts])
			var wood_m: Dictionary = wood(p, Color(0.5, 0.34, 0.2), "mill_axle")
			var r1: float = minf(sx, sz) * 0.5 - 0.1
			# 몸체: 아래가 넓고 위가 좁은 팔각탑(높이 3.0), 지붕: 원뿔(3.0~3.9)
			oct(b, "mill_body", body_w, c.x, c.y, r1, 0.0, 3.0, r1 * 0.62)
			oct(b, "mill_band", body_w, c.x, c.y, r1 * 0.66, 2.9, 3.05, r1 * 0.66)
			oct(b, "mill_roof", roof_m, c.x, c.y, r1 * 0.74, 3.05, 3.95, 0.05)
			# 문·창·날개는 다른 건물 앞면과 같은 +z 면(화면 좌측 하단을 보는 면)을 바라본다. 몸체가 위로 갈수록 좁아지므로 높이별 면 위치를 계산한다.
			var apothem_k: float = 0.9239  # 팔각형 변 중심까지 거리 / 꼭짓점 반지름
			# 몸체가 위로 갈수록 좁아져 문을 세로로 세울 수 없으므로, 문 쪽에만 수직 벽 덩어리(출입구)를 붙여 문이 똑바로 서게 한다(문 쪽 벽을 수직으로 깎은 모양).
			var ap0: float = r1 * apothem_k  # 바닥 쪽 벽 위치(가장 넓음)
			var zf: float = c.y + ap0 + 0.08  # 출입구 앞면
			var ap_top: float = r1 * (1.0 - 0.38 * (1.7 / 3.0)) * apothem_k  # 출입구 지붕이 닿는 높이의 벽 위치
			var entry_h: float = 1.4
			box(b, "mill_entry", body_w, Vector3(c.x - 0.52, 0.0, c.y + ap_top - 0.1), Vector3(c.x + 0.52, entry_h, zf))
			box(b, "mill_entry_base", stone_spec(p, Color(0.95, 0.92, 0.88), "mill_entry_base"), Vector3(c.x - 0.56, 0.0, c.y + ap_top - 0.1), Vector3(c.x + 0.56, 0.12, zf + 0.04))
			var eroof_top: float = entry_h + 0.3
			slope(b, "mill_entry_roof", roof_m, Vector3(c.x - 0.62, eroof_top, c.y + ap_top - 0.02), Vector3(c.x + 0.62, eroof_top, c.y + ap_top - 0.02), Vector3(c.x + 0.62, entry_h + 0.02, zf + 0.12), Vector3(c.x - 0.62, entry_h + 0.02, zf + 0.12), Vector3(0.0, zf + 0.12 - (c.y + ap_top), eroof_top - entry_h).normalized(), 1.24, 1.0)
			add_door_z(b, p, c.x, 0.12, zf, 0.46, 1.0)
			var ap_win: float = r1 * (1.0 - 0.38 * (2.3 / 3.0)) * apothem_k
			var mwp: Dictionary = HouseShapes.win_parts(b, p, Vector3(c.x - 0.3, 1.9, c.y + ap_win - 0.1), Vector3(c.x + 0.3, 2.6, c.y + ap_win + 0.2))
			HouseShapes.win_on_z(mwp, c.x, 2.05, 2.45, 0.13, c.y + ap_win - 0.03)
			# 날개 축(몸체 앞 위쪽에서 카메라 쪽으로 튀어나온 나무 토막)과 날개: 날개는 카메라를 보는 평면 컷아웃이라 그 축으로 돌려도 정면 그대로다.
			var ap_hub: float = r1 * (1.0 - 0.38 * (2.55 / 3.0)) * apothem_k
			var hub := Vector3(c.x, 2.55, c.y + ap_hub + 0.28)
			box(b, "mill_axle", wood_m, Vector3(hub.x - 0.12, 2.43, c.y + ap_hub - 0.05), Vector3(hub.x + 0.12, 2.67, hub.z))
			var blades: Dictionary = spec(PlaceholderTextures.windmill_blades(), Color.WHITE, "mill_blades", "풍차 날개 24×24 (투명 배경 컷아웃, 십자 뼈대와 격자 천)")
			blades["cutout"] = true
			var ab := PartBuilder.new()
			_card_z(ab, blades, 0.0, -1.1, 0.0, 2.2, 2.2)
			var amesh := ArrayMesh.new()
			var aspecs: Array = ab.commit_into(amesh)
			anim_parts.append({"mesh": amesh, "specs": aspecs, "pos": hub + Vector3(0.0, 0.0, 0.1), "mode": "rotate", "speed": 0.9, "axis": Vector3(0.0, 0.0, 1.0)})
			total = 3.95
		"low_wall":
			box(b, "stone", stone_spec(p, Color(1, 1, 1), "low_wall_stone"), Vector3(lo.x, 0.0, lo.y), Vector3(hi.x, 0.55, hi.y))
			box(b, "cap", stone_spec(p, Color(1.25, 1.2, 1.1), "low_wall_cap"), Vector3(lo.x - 0.03, 0.55, lo.y - 0.03), Vector3(hi.x + 0.03, 0.64, hi.y + 0.03))
			total = 0.65
		"cart":
			var l0: float = lo.x if along_x else lo.y
			var l1: float = hi.x if along_x else hi.y
			var w0: float = lo.y if along_x else lo.x
			var w1: float = hi.y if along_x else hi.x
			var wc: float = (w0 + w1) * 0.5
			var bed_lo: float = l0 + 0.45 * (l1 - l0)
			_cart_box(b, along_x, wood(p, Color(0.66, 0.46, 0.3), "cart_bed"), bed_lo, l1 - 0.05, wc - 0.28, wc + 0.28, 0.3, 0.45)
			_cart_box(b, along_x, wood(p, Color(0.5, 0.34, 0.22), "cart_side"), bed_lo, l1 - 0.05, wc - 0.28, wc - 0.24, 0.45, 0.65)
			_cart_box(b, along_x, wood(p, Color(0.5, 0.34, 0.22), "cart_side"), bed_lo, l1 - 0.05, wc + 0.24, wc + 0.28, 0.45, 0.65)
			_cart_box(b, along_x, iron, bed_lo + 0.1, bed_lo + 0.4, wc - 0.34, wc - 0.28, 0.0, 0.5)
			_cart_box(b, along_x, iron, bed_lo + 0.1, bed_lo + 0.4, wc + 0.28, wc + 0.34, 0.0, 0.5)
			_cart_box(b, along_x, wood(p, Color(0.4, 0.28, 0.18), "cart_handle"), l0, bed_lo, wc - 0.22, wc - 0.18, 0.28, 0.32)
			_cart_box(b, along_x, wood(p, Color(0.4, 0.28, 0.18), "cart_handle"), l0, bed_lo, wc + 0.18, wc + 0.22, 0.28, 0.32)
			_cart_box(b, along_x, spec(_tex("crate", ts), Color.WHITE, "crate", "나무 상자 %d×%d" % [ts, ts]), bed_lo + 0.15, bed_lo + 0.5, wc - 0.2, wc + 0.15, 0.45, 0.8)
			total = 1.0
		"crates":
			var crate_spec: Dictionary = spec(_tex("crate", ts), Color.WHITE, "crate", "나무 상자 %d×%d: 판자 + 모서리 틀 + 가로 보강" % [ts, ts])
			box(b, "crate", crate_spec, Vector3(c.x - 0.45, 0.0, c.y - 0.25), Vector3(c.x + 0.0, 0.45, c.y + 0.25))
			box(b, "crate", crate_spec, Vector3(c.x + 0.05, 0.0, c.y - 0.2), Vector3(c.x + 0.45, 0.38, c.y + 0.22))
			box(b, "crate", crate_spec, Vector3(c.x - 0.38, 0.45, c.y - 0.18), Vector3(c.x - 0.02, 0.8, c.y + 0.18))
			total = 0.8
		"noticeboard":
			box(b, "post", bark, Vector3(c.x - 0.34, 0.0, c.y - 0.04), Vector3(c.x - 0.27, 1.5, c.y + 0.04))
			box(b, "post", bark, Vector3(c.x + 0.27, 0.0, c.y - 0.04), Vector3(c.x + 0.34, 1.5, c.y + 0.04))
			box(b, "board", spec(_tex("notice", ts), Color.WHITE, "noticeboard_face", "게시판 면 %d×%d: 코르크 바탕 + 종이 쪽지" % [ts, ts]), Vector3(c.x - 0.3, 0.6, c.y - 0.05), Vector3(c.x + 0.3, 1.25, c.y + 0.05))
			roof_prism(b, "roof", roof_spec, c.x - 0.45, c.x + 0.45, c.y - 0.2, c.y + 0.2, 1.5, 0.26, true)
			total = 1.8
		"bench":
			var bw: Dictionary = wood(p, Color(0.6, 0.4, 0.25), "bench_wood")

			if along_x:
				box(b, "seat", bw, Vector3(c.x - 0.42, 0.28, c.y - 0.15), Vector3(c.x + 0.42, 0.34, c.y + 0.15))
				box(b, "back", bw, Vector3(c.x - 0.42, 0.34, c.y - 0.17), Vector3(c.x + 0.42, 0.62, c.y - 0.12))
				box(b, "leg", bw, Vector3(c.x - 0.38, 0.0, c.y - 0.12), Vector3(c.x - 0.32, 0.28, c.y + 0.12))
				box(b, "leg", bw, Vector3(c.x + 0.32, 0.0, c.y - 0.12), Vector3(c.x + 0.38, 0.28, c.y + 0.12))
			else:
				box(b, "seat", bw, Vector3(c.x - 0.15, 0.28, c.y - 0.42), Vector3(c.x + 0.15, 0.34, c.y + 0.42))
				box(b, "back", bw, Vector3(c.x - 0.17, 0.34, c.y - 0.42), Vector3(c.x - 0.12, 0.62, c.y + 0.42))
				box(b, "leg", bw, Vector3(c.x - 0.12, 0.0, c.y - 0.38), Vector3(c.x + 0.12, 0.28, c.y - 0.32))
				box(b, "leg", bw, Vector3(c.x - 0.12, 0.0, c.y + 0.32), Vector3(c.x + 0.12, 0.28, c.y + 0.38))

			total = 0.65
		"lantern":
			box(b, "pole", iron, Vector3(c.x - 0.04, 0.0, c.y - 0.04), Vector3(c.x + 0.04, 1.6, c.y + 0.04))
			var lamp_spec: Dictionary = spec(_tex("flat", ts, Color(1.0, 0.85, 0.45)), Color(1.4, 1.3, 1.0), "lantern_glass", "가로등 유리 단색 %d×%d 따뜻한 노랑(밤에 빛남)" % [ts, ts])
			lamp_spec["emit"] = 1.0
			var lamb := PartBuilder.new()
			box(lamb, "lamp", lamp_spec, Vector3(-0.1, 0.0, -0.1), Vector3(0.1, 0.26, 0.1))
			var lammesh := ArrayMesh.new()
			var lamspecs: Array = lamb.commit_into(lammesh)
			anim_parts.append({"mesh": lammesh, "specs": lamspecs, "pos": Vector3(c.x, 1.6, c.y), "mode": "pulse", "speed": 5.0, "amp": 0.3, "half": 0.5, "emit_base": 1.0})
			box(b, "cap", iron, Vector3(c.x - 0.13, 1.86, c.y - 0.13), Vector3(c.x + 0.13, 1.92, c.y + 0.13))
			total = 1.95
		"flower_bush":
			var bvar: String = str(rule.get("variant", ""))

			if bvar == "berry":
				var berry: Dictionary = _noise_spec(ts, Color(0.24, 0.46, 0.26), Color(0.82, 0.18, 0.22), "berry_bush", 17, Color.WHITE, 0.1)
				berry["sway"] = 0.05
				berry["sway_base"] = 0.05
				_crown(b, berry, c.x, c.y, [{"dx": -0.18, "dz": -0.1, "r": 0.3, "y0": 0.0, "y1": 0.42}, {"dx": 0.0, "dz": 0.0, "r": 0.34, "y0": 0.0, "y1": 0.5}, {"dx": 0.2, "dz": 0.12, "r": 0.28, "y0": 0.0, "y1": 0.4}], 2, 10)
				total = 0.55
			elif bvar == "hedge":
				var hedge: Dictionary = _noise_spec(ts, Color(0.22, 0.44, 0.24), Color(0.4, 0.62, 0.34), "hedge_foliage", 19)
				var h0: float = lo.x if along_x else lo.y
				var h1: float = hi.x if along_x else hi.y
				var hc: float = c.y if along_x else c.x
				_cart_box(b, along_x, hedge, h0, h1, hc - 0.2, hc + 0.2, 0.0, 0.62)
				_cart_box(b, along_x, hedge, h0 + 0.06, h1 - 0.06, hc - 0.16, hc + 0.16, 0.62, 0.74)
				total = 0.78
			else:
				dome(b, "bush", spec(_tex("foliage", ts, Color(0.95, 0.4, 0.55)), tint, "flower_bush", "꽃 덤불 %d×%d 반복(짙은 초록 + 분홍 꽃 점)" % [ts, ts]), c.x, c.y, 0.32, 0.0, 0.4)
				total = 0.45
		"rock":
			var rs: Dictionary = _noise_spec(ts, Color(0.42, 0.43, 0.48), Color(0.58, 0.59, 0.64), "rock_stone", 21, Color.WHITE, 0.12)
			_crown(b, rs, c.x, c.y, [{"dx": -0.2, "dz": -0.12, "r": 0.3, "y0": 0.0, "y1": 0.3}, {"dx": 0.0, "dz": 0.0, "r": 0.42, "y0": 0.0, "y1": 0.44}, {"dx": 0.34, "dz": 0.24, "r": 0.24, "y0": 0.0, "y1": 0.24}, {"dx": 0.1, "dz": 0.4, "r": 0.14, "y0": 0.0, "y1": 0.14}], 2, 8)
			total = 0.5
		"stump":
			var ring: Dictionary = _flat_spec(ts, Color(0.76, 0.58, 0.38), "stump_rings")
			oct(b, "root", bark, c.x, c.y, 0.32, 0.0, 0.1, 0.26)
			oct(b, "stump", bark, c.x, c.y, 0.25, 0.08, 0.36, 0.23)
			oct(b, "top", ring, c.x, c.y, 0.22, 0.36, 0.375, 0.21)
			oct(b, "ring", wood(p, Color(0.58, 0.4, 0.26), "stump_ring"), c.x, c.y, 0.12, 0.375, 0.38, 0.11)
			total = 0.4
		"log":
			var lg: float = lo.x if along_x else lo.y
			var lg1: float = hi.x if along_x else hi.y
			var lc: float = c.y if along_x else c.x
			var endc: Dictionary = _flat_spec(ts, Color(0.76, 0.58, 0.38), "log_end")
			_cart_box(b, along_x, bark, lg, lg1, lc - 0.24, lc - 0.02, 0.0, 0.22)
			_cart_box(b, along_x, bark, lg + 0.05, lg1 - 0.02, lc + 0.02, lc + 0.24, 0.0, 0.22)
			_cart_box(b, along_x, bark, lg + 0.02, lg1 - 0.05, lc - 0.11, lc + 0.11, 0.22, 0.44)
			_cart_box(b, along_x, endc, lg1 - 0.02, lg1 + 0.01, lc - 0.2, lc - 0.04, 0.02, 0.2)
			total = 0.46
		"mushroom":
			var stem: Dictionary = _flat_spec(ts, Color(0.94, 0.9, 0.8), "mushroom_stem")
			var cap_r: Dictionary = _noise_spec(ts, Color(0.82, 0.2, 0.2), Color(0.98, 0.96, 0.9), "mushroom_cap", 23, Color.WHITE, 0.12)
			var cap_b: Dictionary = _noise_spec(ts, Color(0.7, 0.5, 0.3), Color(0.86, 0.72, 0.5), "mushroom_cap_brown", 25, Color.WHITE, 0.1)

			for mi in [[-0.3, -0.15, 0.16, 0.29, 0], [0.18, 0.08, 0.22, 0.42, 1], [-0.03, 0.34, 0.13, 0.22, 0]]:
				oct(b, "stem", stem, c.x + float(mi[0]), c.y + float(mi[1]), 0.035 + float(mi[2]) * 0.2, 0.0, float(mi[3]), 0.035 + float(mi[2]) * 0.16)
				dome(b, "cap", cap_r if int(mi[4]) == 0 else cap_b, c.x + float(mi[0]), c.y + float(mi[1]), float(mi[2]) + 0.04, float(mi[3]) - 0.03, float(mi[3]) + float(mi[2]) * 0.9, 2, 8)

			total = 0.4
		"fountain":
			var fs: Dictionary = stone_spec(p, Color(1.1, 1.06, 1.0), "fountain_stone")
			var fs2: Dictionary = stone_spec(p, Color(0.88, 0.86, 0.82), "fountain_stone_dark")
			var water: Dictionary = spec(_tex("flat", ts, Color(0.35, 0.62, 0.86)), Color.WHITE, "fountain_water", "분수 물 단색 %d×%d" % [ts, ts])
			water["emit"] = 0.15
			var fr: float = minf(sx, sz) * 0.5 - 0.05
			oct(b, "base", fs2, c.x, c.y, fr, 0.0, 0.14, fr - 0.04)
			oct(b, "wall", fs, c.x, c.y, fr - 0.1, 0.12, 0.42, fr - 0.14)
			oct(b, "water", water, c.x, c.y, fr - 0.22, 0.4, 0.43, fr - 0.22)
			oct(b, "pillar", fs, c.x, c.y, 0.15, 0.4, 1.0, 0.11)
			oct(b, "bowl", fs, c.x, c.y, 0.42, 0.88, 1.06, 0.5)
			oct(b, "bowl_water", water, c.x, c.y, 0.38, 1.04, 1.07, 0.38)
			var spb := PartBuilder.new()
			dome(spb, "spout", water, 0.0, 0.0, 0.1, 0.0, 0.24, 2, 8)
			var spmesh := ArrayMesh.new()
			var spspecs: Array = spb.commit_into(spmesh)
			anim_parts.append({"mesh": spmesh, "specs": spspecs, "pos": Vector3(c.x, 1.06, c.y), "mode": "bob", "speed": 3.6, "amp": 0.035, "half": 0.8})

			for di in range(6):
				var da: float = float(di) * TAU / 6.0
				var drb := PartBuilder.new()
				dome(drb, "drop", water, 0.0, 0.0, 0.04, 0.0, 0.07, 2, 6)
				var drmesh := ArrayMesh.new()
				var drspecs: Array = drb.commit_into(drmesh)
				anim_parts.append({"mesh": drmesh, "specs": drspecs, "pos": Vector3(c.x, 1.3, c.y), "mode": "arc", "speed": 0.8, "phase": float(di) / 6.0, "amp": 0.25, "drift": Vector3(cos(da) * 0.4, 0.0, sin(da) * 0.4), "half": 0.8})

			total = 1.35
		"scarecrow":
			var straw: Dictionary = _noise_spec(ts, Color(0.88, 0.74, 0.34), Color(0.98, 0.9, 0.5), "straw", 27, Color.WHITE, 0.16)
			var cloth_s: Dictionary = _flat_spec(ts, Color(0.5, 0.32, 0.62), "scarecrow_shirt")
			var hat_s: Dictionary = _flat_spec(ts, Color(0.46, 0.3, 0.18), "scarecrow_hat")
			oct(b, "pole", bark, c.x, c.y, 0.04, 0.0, 1.4, 0.035)
			# 몸·팔·머리·모자는 막대 위 받침(높이 0.55)을 중심으로 좌우로 살랑 흔들린다(sway). 부품 좌표는 받침 기준.
			var sab := PartBuilder.new()
			box(sab, "arms", wood(p, Color(0.5, 0.36, 0.22), "scarecrow_arms"), Vector3(-0.5, 0.4, -0.03), Vector3(0.5, 0.46, 0.03))
			box(sab, "shirt", cloth_s, Vector3(-0.15, 0.0, -0.1), Vector3(0.15, 0.5, 0.1))
			box(sab, "hand", straw, Vector3(-0.58, 0.35, -0.05), Vector3(-0.46, 0.49, 0.05))
			box(sab, "hand", straw, Vector3(0.46, 0.35, -0.05), Vector3(0.58, 0.49, 0.05))
			dome(sab, "head", straw, 0.0, 0.0, 0.14, 0.57, 0.83, 2, 8)
			oct(sab, "brim", hat_s, 0.0, 0.0, 0.24, 0.81, 0.84, 0.24)
			oct(sab, "hat", hat_s, 0.0, 0.0, 0.14, 0.84, 1.07, 0.07)
			var samesh := ArrayMesh.new()
			var saspecs: Array = sab.commit_into(samesh)
			anim_parts.append({"mesh": samesh, "specs": saspecs, "pos": Vector3(c.x, 0.55, c.y), "mode": "sway", "speed": 1.5, "amp": 0.06, "axis": Vector3(0.0, 0.0, 1.0), "half": 1.0})
			total = 1.7
		"campfire":
			var stones: Dictionary = _noise_spec(ts, Color(0.42, 0.43, 0.48), Color(0.58, 0.59, 0.64), "fire_stone", 29)
			var ember: Dictionary = _flat_spec(ts, Color(0.92, 0.26, 0.05), "flame_outer")
			ember["emit"] = 0.55
			var ember2: Dictionary = _flat_spec(ts, Color(1.0, 0.72, 0.18), "flame_inner")
			ember2["emit"] = 0.8
			var ring_st: SurfaceTool = b.new_part(stones, Vector3(c.x - 0.6, 0.0, c.y - 0.6), Vector3(c.x + 0.6, 0.3, c.y + 0.6))

			for si in range(8):
				var sa: float = float(si) * TAU / 8.0 + 0.2
				dome_st(ring_st, c.x + cos(sa) * 0.44, c.y + sin(sa) * 0.44, 0.13, 0.0, 0.18 + float(si % 2) * 0.06, 2, 6)

			var logs_s: Dictionary = wood(p, Color(0.4, 0.28, 0.18), "fire_logs")
			box(b, "log", logs_s, Vector3(c.x - 0.34, 0.05, c.y - 0.05), Vector3(c.x + 0.34, 0.18, c.y + 0.08))
			box(b, "log", logs_s, Vector3(c.x - 0.06, 0.18, c.y - 0.32), Vector3(c.x + 0.06, 0.31, c.y + 0.32))
			# 불꽃은 여러 갈래(불길 혀)로 나눠 갈래마다 높이·기울기·박자를 달리 일렁이게 한다(flame). 바닥에는 깜빡이는 숯불 층.
			var tongues: Array = [
				{"dx": 0.0, "dz": 0.0, "h": 0.66, "w": 0.1, "ph": 0.0, "sp": 7.0, "outer": true},
				{"dx": -0.13, "dz": 0.05, "h": 0.46, "w": 0.085, "ph": 1.7, "sp": 9.0, "outer": true},
				{"dx": 0.12, "dz": -0.06, "h": 0.5, "w": 0.085, "ph": 3.1, "sp": 8.0, "outer": true},
				{"dx": 0.04, "dz": 0.14, "h": 0.4, "w": 0.075, "ph": 4.4, "sp": 10.0, "outer": true},
				{"dx": -0.05, "dz": -0.13, "h": 0.42, "w": 0.075, "ph": 5.6, "sp": 9.5, "outer": true},
				{"dx": 0.0, "dz": 0.0, "h": 0.42, "w": 0.055, "ph": 0.9, "sp": 11.0, "outer": false},
				{"dx": -0.1, "dz": 0.05, "h": 0.28, "w": 0.045, "ph": 2.5, "sp": 12.0, "outer": false},
				{"dx": 0.09, "dz": -0.05, "h": 0.3, "w": 0.045, "ph": 3.8, "sp": 11.5, "outer": false},
			]

			for tg in tongues:
				var tm: Dictionary = _flame_tongue(ember if bool(tg["outer"]) else ember2, float(tg["h"]), float(tg["w"]))
				anim_parts.append({"mesh": tm["mesh"], "specs": tm["specs"], "pos": Vector3(c.x + float(tg["dx"]), 0.2, c.y + float(tg["dz"])), "mode": "flame", "speed": float(tg["sp"]), "phase": float(tg["ph"]), "amp": 0.28, "half": 0.8, "emit_base": 0.55 if bool(tg["outer"]) else 0.8})

			var bedb := PartBuilder.new()
			var bed_spec: Dictionary = _flat_spec(ts, Color(0.95, 0.35, 0.1), "ember_bed")
			bed_spec["emit"] = 1.0
			oct(bedb, "bed", bed_spec, 0.0, 0.0, 0.2, 0.0, 0.04, 0.17)
			var bed_mesh := ArrayMesh.new()
			var bed_specs: Array = bedb.commit_into(bed_mesh)
			anim_parts.append({"mesh": bed_mesh, "specs": bed_specs, "pos": Vector3(c.x, 0.16, c.y), "mode": "pulse", "speed": 6.0, "amp": 0.35, "half": 0.6, "emit_base": 1.0})

			for sk in range(3):
				var sb := PartBuilder.new()
				box(sb, "spark", ember2, Vector3(-0.025, 0.0, -0.025), Vector3(0.025, 0.05, 0.025))
				var smesh := ArrayMesh.new()
				var sspecs: Array = sb.commit_into(smesh)
				anim_parts.append({"mesh": smesh, "specs": sspecs, "pos": Vector3(c.x + (float(sk) - 1.0) * 0.07, 0.62, c.y + (float(sk) - 1.0) * 0.04), "mode": "drift", "speed": 0.5, "phase": float(sk) / 3.0, "rise": 0.7, "drift": Vector3((float(sk) - 1.0) * 0.12, 0.0, 0.05), "half": 0.8, "emit_base": 1.0})

			total = 0.65
		"flowerbed":
			var soil: Dictionary = _flat_spec(ts, Color(0.36, 0.26, 0.18), "bed_soil")
			var edge: Dictionary = stone_spec(p, Color(1.05, 1.0, 0.95), "bed_edge")
			var f0: float = lo.x + 0.04
			var f1: float = hi.x - 0.04
			var g0: float = lo.y + 0.04
			var g1: float = hi.y - 0.04
			box(b, "soil", soil, Vector3(f0, 0.0, g0), Vector3(f1, 0.1, g1))
			box(b, "edge", edge, Vector3(f0 - 0.04, 0.0, g0 - 0.04), Vector3(f1 + 0.04, 0.14, g0 + 0.06))
			box(b, "edge", edge, Vector3(f0 - 0.04, 0.0, g1 - 0.06), Vector3(f1 + 0.04, 0.14, g1 + 0.04))
			box(b, "edge", edge, Vector3(f0 - 0.04, 0.0, g0 + 0.06), Vector3(f0 + 0.06, 0.14, g1 - 0.06))
			box(b, "edge", edge, Vector3(f1 - 0.06, 0.0, g0 + 0.06), Vector3(f1 + 0.04, 0.14, g1 - 0.06))
			var fcache: Dictionary = {}
			var fa := Vector3(f0, 0.1, g0)
			var fb := Vector3(f1, 0.4, g1)
			var cols: Array = ["#e06080", "#f0e050", "#b070e0", "#ffffff", "#f09040"]
			var fnx: int = maxi(int((f1 - f0) / 0.34), 1)
			var fnz: int = maxi(int((g1 - g0) / 0.34), 1)

			for ix in range(fnx):
				for iz in range(fnz):
					var fx: float = f0 + (float(ix) + 0.5) * (f1 - f0) / float(fnx)
					var fz: float = g0 + (float(iz) + 0.5) * (g1 - g0) / float(fnz)
					_goods_obj(b, fcache, "flower:" + str(cols[(ix * 2 + iz) % cols.size()]), fx, 0.1, fz, ts, fa, fb)

			total = 0.4
		"sign":
			box(b, "pole", bark, Vector3(c.x - 0.04, 0.0, c.y - 0.04), Vector3(c.x + 0.04, 1.4, c.y + 0.04))
			box(b, "board", spec(PlaceholderTextures.sign_board(ts), Color.WHITE, "road_sign_board", "표지판 %d×%d 나무 판 + 흰 화살표" % [ts, ts]), Vector3(c.x - 0.28, 1.05, c.y - 0.04), Vector3(c.x + 0.28, 1.4, c.y + 0.04))
			total = 1.45
		"fence":
			var fw: Dictionary = wood(p, Color(0.62, 0.42, 0.26), "fence_wood")
			var f0: float = lo.x if along_x else lo.y
			var f1: float = hi.x if along_x else hi.y
			var fc: float = c.y if along_x else c.x
			var posts: int = maxi(int(roundf((f1 - f0) / 0.7)), 2)

			for i in range(posts + 1):
				var pp: float = lerpf(f0, f1, float(i) / float(posts))
				_cart_box(b, along_x, fw, pp - 0.04, pp + 0.04, fc - 0.05, fc + 0.05, 0.0, 0.7)

			_cart_box(b, along_x, fw, f0, f1, fc - 0.03, fc + 0.03, 0.5, 0.58)
			_cart_box(b, along_x, fw, f0, f1, fc - 0.03, fc + 0.03, 0.28, 0.36)
			total = 0.75
		_:
			box(b, "box", wood(p, tint, "generic"), Vector3(lo.x, 0.0, lo.y), Vector3(hi.x, 1.0, hi.y))

	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	var plo: Vector2 = lo
	var phi: Vector2 = hi

	if b.min_pt.x != INF:
		plo = Vector2(minf(lo.x, b.min_pt.x), minf(lo.y, b.min_pt.z))
		phi = Vector2(maxf(hi.x, b.max_pt.x), maxf(hi.y, b.max_pt.z))

	apply_overrides(specs, str(rule.get("asset", "")), p)
	return {"mesh": mesh, "specs": specs, "apron": null, "anim": anim_parts, "total_blocks": total, "lo": plo, "hi": phi}


# l(길이 방향)·w(폭 방향) 좌표로 상자를 놓는다(along_x 면 l=x, w=z / 아니면 l=z, w=x).
static func _cart_box(b: PartBuilder, along_x: bool, sp: Dictionary, l0: float, l1: float, w0: float, w1: float, y0: float, y1: float) -> void:
	if along_x:
		box(b, str(sp["name"]), sp, Vector3(l0, y0, w0), Vector3(l1, y1, w1))
	else:
		box(b, str(sp["name"]), sp, Vector3(w0, y0, l0), Vector3(w1, y1, l1))
