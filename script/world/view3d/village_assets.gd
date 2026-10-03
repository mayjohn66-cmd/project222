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

	func new_part(spec: Dictionary, a: Vector3, b: Vector3) -> SurfaceTool:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var c: Vector3 = (a + b) * 0.5
		parts.append({"depth": c.x + c.z + c.y * 0.02, "spec": spec, "st": st})
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
static func box(b: PartBuilder, key: String, spec: Dictionary, lo: Vector3, hi: Vector3) -> void:
	var st: SurfaceTool = b.new_part(spec, lo, hi)
	var dx: float = hi.x - lo.x
	var dy: float = hi.y - lo.y
	var dz: float = hi.z - lo.z
	var q := BuildingMesh._quad
	q.call(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, Vector2(0, 0), Vector2(dx, 0), Vector2(dx, dz), Vector2(0, dz))
	q.call(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(0, 0, 1), Vector2(0, dy), Vector2(dx, dy), Vector2(dx, 0), Vector2(0, 0))
	q.call(st, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(1, 0, 0), Vector2(0, dy), Vector2(dz, dy), Vector2(dz, 0), Vector2(0, 0))
	q.call(st, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(0, 0, -1), Vector2(0, dy), Vector2(dx, dy), Vector2(dx, 0), Vector2(0, 0))
	q.call(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(-1, 0, 0), Vector2(0, dy), Vector2(dz, dy), Vector2(dz, 0), Vector2(0, 0))


# 팔각 기둥(통·줄기·잎 덩어리). 옆면 UV 는 둘레 길이 기준.
static func oct(b: PartBuilder, key: String, spec: Dictionary, cx: float, cz: float, r: float, y0: float, y1: float, r_top: float = -1.0) -> void:
	var st: SurfaceTool = b.new_part(spec, Vector3(cx - r, y0, cz - r), Vector3(cx + r, y1, cz + r))
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
	var options: Dictionary = {"chimney": bool(rule.get("chimney", true)), "awning": bool(rule.get("awning", false)), "apron": float(rule.get("apron", 0.4))}
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
	var tex_z: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(width * ts)), h_texels, true, cells_z, plaster, timber)

	if is_shop:
		tex_z = PlaceholderTextures.shop_front_wall(int(roundf(width * ts)), h_texels, cells_z, plaster, timber)
	var tex_x: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(depth * ts)), h_texels, false, cells_x, plaster, timber)
	var specs: Array = [
		spec(tex_z, Color.WHITE, "wall_front", "카메라 왼쪽 아래를 보는 앞벽 %d×%d px: 문 1(가운데), 창 %d, 나무 뼈대, 아래 돌 기단" % [tex_z.get_width(), tex_z.get_height(), cells_z - 1]),
		spec(tex_x, Color.WHITE, "wall_side", "카메라 오른쪽 아래를 보는 옆벽 %d×%d px: 창 %d, 나무 뼈대, 아래 돌 기단" % [tex_x.get_width(), tex_x.get_height(), cells_x]),
		spec(_tex("flat", ts, roof_tint), Color.WHITE, "roof_tiles", "지붕 기와 %d×%d 한 칸 반복(이음매 없이). 법선 맵 별도" % [ts, ts], PlaceholderTextures.roof_normal(ts)),
		spec(PlaceholderTextures.wall_facade(ts, ts, false, 1, plaster, timber), Color.WHITE, "gable_wall", "박공(지붕 끝 삼각형) 벽 %d×%d 반복" % [ts, ts]),
		spec(PlaceholderTextures.flat_color(ts, roof_tint.darkened(0.45)), Color.WHITE, "roof_trim", "지붕 두께·처마 단면·용마루 덮개 %d×%d 어두운 목재/기와" % [ts, ts]),
		spec(_tex("stone", ts), Color(1.0, 0.82, 0.74), "chimney_stone", "굴뚝 돌 %d×%d 반복" % [ts, ts]),
		spec(PlaceholderTextures.roof_tiles(ts, awning_tint.darkened(0.12)), Color.WHITE, "awning", "차양 기와 %d×%d 반복(지붕 기와와 같은 구조, 색은 가게마다)" % [ts, ts], PlaceholderTextures.roof_normal(ts)),
	]
	# 지붕 기와는 flat_color 대신 기와 질감을 쓰도록 교체(법선 맵과 짝)
	specs[2]["tex"] = PlaceholderTextures.roof_tiles(ts, roof_tint)

	# --- 부속: 현관 계단, 창 아래 화분, 간판, 건물 앞 소품(extras)
	var b := PartBuilder.new()
	var cells: int = cells_z
	var door_cell: int = cells / 2
	var door_cx: float = lo.x + (float(door_cell) + 0.5) * width / float(cells)
	var lay_z: Dictionary = PlaceholderTextures.window_layout(int(roundf(width * ts)), h_texels, cells_z)
	var lay_x: Dictionary = PlaceholderTextures.window_layout(int(roundf(depth * ts)), h_texels, cells_x)
	var win_top: float = wall_h * (1.0 - float(lay_z["wy"]) / float(h_texels))
	var win_bottom: float = wall_h * (1.0 - float(lay_z["wy"] + lay_z["wh"]) / float(h_texels))
	var win_w: float = float(lay_z["ww"]) / float(ts)
	var win_w_x: float = float(lay_x["ww"]) / float(ts)
	var cell_w_z: float = width / float(cells_z)
	var cell_w_x: float = depth / float(cells_x)

	# 덧문: 창 양옆에 창과 같은 높이로, 칸에 들어가는 만큼만(너무 넓으면 뼈대와 겹치므로 줄임). 살(루버) 질감을 쓴다.
	if bool(rule.get("shutters", false)):
		var shut: Dictionary = spec(PlaceholderTextures.shutter(ts, Color(0.36, 0.52, 0.48)), Color.WHITE, "shutter_wood", "덧문 %d×%d 가로 살(청록 계열, 가게마다 색)" % [ts, ts])
		var sw_z: float = clampf((cell_w_z - win_w) * 0.5 * 0.75, 0.05, 0.2)
		var sw_x: float = clampf((cell_w_x - win_w_x) * 0.5 * 0.75, 0.05, 0.2)

		for k in range(cells_z):
			if k == cells_z / 2:
				continue

			var scx: float = lo.x + (float(k) + 0.5) * cell_w_z
			var half: float = win_w * 0.5 + 0.02
			box(b, "shutter", shut, Vector3(scx - half - sw_z, win_bottom, hi.y), Vector3(scx - half, win_top, hi.y + 0.05))
			box(b, "shutter", shut, Vector3(scx + half, win_bottom, hi.y), Vector3(scx + half + sw_z, win_top, hi.y + 0.05))

		for k in range(cells_x):
			var scz: float = hi.y - (float(k) + 0.5) * cell_w_x
			var halfx: float = win_w_x * 0.5 + 0.02
			box(b, "shutter", shut, Vector3(hi.x, win_bottom, scz - halfx - sw_x), Vector3(hi.x + 0.05, win_top, scz - halfx))
			box(b, "shutter", shut, Vector3(hi.x, win_bottom, scz + halfx), Vector3(hi.x + 0.05, win_top, scz + halfx + sw_x))

	if bool(rule.get("step", true)):
		var door_w: float = float(lay_z["dw"]) / float(ts)
		box(b, "step", stone_spec(p, Color(1.15, 1.1, 1.0), "step"), Vector3(door_cx - door_w * 0.5 - 0.12, 0.0, hi.y), Vector3(door_cx + door_w * 0.5 + 0.12, 0.14, hi.y + 0.3))

	if bool(rule.get("planters", true)):
		for k in range(cells):
			if k == door_cell:
				continue

			var cx: float = lo.x + (float(k) + 0.5) * width / float(cells)
			var half_p: float = win_w * 0.5 + 0.04
			box(b, "planter", wood(p, Color(0.62, 0.42, 0.28), "planter_box"), Vector3(cx - half_p, win_bottom - 0.13, hi.y), Vector3(cx + half_p, win_bottom, hi.y + 0.14))
			box(b, "flowers", spec(_tex("foliage", ts, Color(0.95, 0.4, 0.55)), Color.WHITE, "planter_flowers", "창 아래 화분 꽃·풀 %d×%d 반복" % [ts, ts]), Vector3(cx - half_p + 0.02, win_bottom, hi.y + 0.01), Vector3(cx + half_p - 0.02, win_bottom + 0.1, hi.y + 0.13))

	if bool(rule.get("sign", false)):
		var sx: float = lo.x + 0.18
		box(b, "sign_bracket", wood(p, Color(0.3, 0.2, 0.12), "sign_bracket"), Vector3(sx, wall_h * 0.8, hi.y), Vector3(sx + 0.03, wall_h * 0.8 + 0.03, hi.y + 0.34))
		box(b, "sign_board", spec(PlaceholderTextures.sign_board(ts), Color.WHITE, "sign_board", "걸린 간판 %d×%d (가게 표시 그림은 가게마다)" % [ts, ts]), Vector3(sx - 0.02, wall_h * 0.8 - 0.24, hi.y + 0.28), Vector3(sx + 0.05, wall_h * 0.8, hi.y + 0.34))

	_add_eave_nubs(b, lo, hi, wall_h, roof_tint, p)
	var display: PartBuilder = null

	if is_shop:
		_add_fascia(b, p, lo, hi, wall_h, h_texels)
		_add_cloth_awning(b, p, lo, hi, wall_h, cells_z, cells_z / 2, awning_tint)
		display = PartBuilder.new()

	if bool(rule.get("chimney", true)):
		_add_smoke(b, lo, hi, wall_h + roof_h, p)

	_add_extras(b, str(rule.get("extras", "")), lo, hi, p, wall_h, display)
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

	var all_specs: Array = pre_specs + kept + extra_specs
	apply_overrides(all_specs, str(rule.get("asset", "")), p)

	if apron_info != null:
		apply_overrides([apron_info["spec"]], str(rule.get("asset", "")), p)

	return {"mesh": mesh, "specs": all_specs, "display": display_info, "apron": apron_info, "total_blocks": wall_blocks + roof_blocks, "lo": ext_lo, "hi": ext_hi}


# extras: "이름:dx:dz;..." — 건물 앞(+z)쪽 중심 기준 옆(dx)·앞(dz) 칸 위치에 작은 소품(통·상자·화분)
# 보이는 쪽 처마 끝에 기와 끝 조각을 한 줄 붙여 가장자리가 물결(톱니) 모양으로 보이게 한다.
static func _add_eave_nubs(b: PartBuilder, lo: Vector2, hi: Vector2, wall_h: float, roof_tint: Color, p: Dictionary) -> void:
	var ts: int = p["ts"]
	var overhang: float = 0.14
	var ridge_x: bool = (hi.x - lo.x) >= (hi.y - lo.y)
	var cap: Dictionary = spec(PlaceholderTextures.flat_color(ts, roof_tint.darkened(0.12)), Color.WHITE, "eave_tile", "처마 끝 기와 조각 단색 %d×%d (지붕보다 한 톤 어둡게)" % [ts, ts])
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


# 굴뚝 연기: 위로 갈수록 커지고 옆으로 번지는 흰 덩어리 셋(정지 상태). 2D 그림의 연기를 대신한다.
static func _add_smoke(b: PartBuilder, lo: Vector2, hi: Vector2, peak: float, p: Dictionary) -> void:
	var ts: int = p["ts"]
	var ridge_x: bool = (hi.x - lo.x) >= (hi.y - lo.y)
	var cu: float = (hi.x if ridge_x else hi.y) - BuildingMesh.CHIMNEY_INSET
	var cv: float = ((lo.y + hi.y) * 0.5 if ridge_x else (lo.x + hi.x) * 0.5) + 0.2
	var cx: float = cu if ridge_x else cv
	var cz: float = cv if ridge_x else cu
	var puff: Dictionary = spec(PlaceholderTextures.flat_color(ts, Color(0.92, 0.9, 0.9)), Color.WHITE, "smoke", "굴뚝 연기 단색 %d×%d 연한 회백색" % [ts, ts])
	var y: float = peak + 0.34

	for k in range(3):
		var r: float = 0.07 + 0.03 * float(k)
		dome(b, "smoke", puff, cx + 0.05 * float(k), cz - 0.03 * float(k), r, y, y + r * 1.4, 2, 8)
		y += r * 1.5


# 카메라 쪽(+x,+z 대각선)을 보는 평면 카드 한 장(투명 컷아웃). 상자에 꽂힌 종이처럼 세워 둔다. 바닥 중심 (cx, y0, cz), 폭 w, 높이 h.
static func _card(b: PartBuilder, spec: Dictionary, cx: float, y0: float, cz: float, w: float, h: float) -> void:
	var r := Vector3(0.7071, 0.0, -0.7071) * (w * 0.5)
	var c0 := Vector3(cx, y0, cz)
	var pa: Vector3 = c0 - r
	var pb: Vector3 = c0 + r
	var up := Vector3(0, h, 0)
	var st: SurfaceTool = b.new_part(spec, pa, pb + up)
	BuildingMesh._quad(st, pa, pb, pb + up, pa + up, Vector3(0.7071, 0.0, 0.7071), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


static func _card_spec(kind: String, p: Dictionary) -> Dictionary:
	var sp: Dictionary = spec(PlaceholderTextures.bread_card(kind), Color.WHITE, "card_" + kind, "빵 카드 %s (투명 배경 컷아웃, 어두운 윤곽선)" % kind)
	sp["cutout"] = true
	return sp


# 빵 상자: 윗면이 열린 나무 상자(바닥 + 사방 판). 안에 빵 카드를 세워 꽂는다(여러 장이 겹쳐 "빵이 가득 든" 모양).
static func _add_bread_bin(b: PartBuilder, p: Dictionary, x: float, z: float, kind: String) -> void:
	var plank: Dictionary = wood(p, Color(1.0, 0.84, 0.6), "bin_wood")
	var inner: Dictionary = spec(_tex("flat", p["ts"], Color(0.42, 0.26, 0.14)), Color.WHITE, "bin_inner", "빵 상자 안쪽 어두운 갈색 단색 %d×%d" % [p["ts"], p["ts"]])
	var hx: float = 0.42
	var hz: float = 0.22
	var rim: float = 0.34
	box(b, "bin_bottom", inner, Vector3(x - hx, 0.0, z - hz), Vector3(x + hx, 0.05, z + hz))
	box(b, "bin_back", plank, Vector3(x - hx, 0.0, z - hz), Vector3(x + hx, rim, z - hz + 0.04))
	box(b, "bin_left", plank, Vector3(x - hx, 0.0, z - hz), Vector3(x - hx + 0.04, rim, z + hz))

	var card: Dictionary = _card_spec(kind, p)

	if kind == "baguette":
		var xs: Array = [-0.3, -0.15, 0.0, 0.15, 0.3]
		var hs: Array = [0.74, 0.86, 0.78, 0.9, 0.72]

		for i in range(xs.size()):
			_card(b, card, x + float(xs[i]) * 0.9, 0.08, z - 0.04 + 0.03 * float(i % 2), 0.24, float(hs[i]))
	else:
		# 둥근 빵은 앞뒤 두 줄(뒤는 높게)
		for i in range(3):
			_card(b, card, x + (float(i) - 1.0) * 0.27, 0.2, z - 0.1, 0.34, 0.3)

		for i in range(2):
			_card(b, card, x + (float(i) - 0.5) * 0.3, 0.1, z + 0.06, 0.34, 0.3)

	box(b, "bin_right", plank, Vector3(x + hx - 0.04, 0.0, z - hz), Vector3(x + hx, rim, z + hz))
	box(b, "bin_front", plank, Vector3(x - hx, 0.0, z + hz - 0.04), Vector3(x + hx, rim, z + hz))


# 가게 앞면 천 차양(줄무늬): 진열창 칸 위에만(문 칸은 비움). 앞 가장자리에 톱니 단.
static func _add_cloth_awning(b: PartBuilder, p: Dictionary, lo: Vector2, hi: Vector2, wall_h: float, cells: int, door_cell: int, tint: Color) -> void:
	var ts: int = p["ts"]
	var cloth: Dictionary = spec(PlaceholderTextures.awning_stripes(ts, Color(0.98, 0.95, 0.86), tint), Color.WHITE, "cloth_awning", "천 차양 줄무늬 %d×%d 반복(크림 + 가게 색)" % [ts, ts])
	var width: float = hi.x - lo.x
	var cell_w: float = width / float(cells)
	var y_top: float = wall_h - 0.72
	var y_bot: float = y_top - 0.34
	var out: float = 0.55

	for k in range(cells):
		if k == door_cell:
			continue

		var x0: float = lo.x + float(k) * cell_w + 0.04
		var x1: float = lo.x + float(k + 1) * cell_w - 0.04
		slope(b, "awning", cloth, Vector3(x0, y_top, hi.y), Vector3(x1, y_top, hi.y), Vector3(x1, y_bot, hi.y + out), Vector3(x0, y_bot, hi.y + out), Vector3(0, out, (y_top - y_bot)).normalized(), x1 - x0, 1.0)
		var tooth: int = maxi(int(roundf((x1 - x0) / 0.2)), 2)
		var tw: float = (x1 - x0) / float(tooth)

		for t in range(tooth):
			if t % 2 == 0:
				box(b, "valance", cloth, Vector3(x0 + tw * float(t), y_bot - 0.09, hi.y + out - 0.03), Vector3(x0 + tw * float(t + 1), y_bot, hi.y + out + 0.01))


# 가게 이름 간판(앞벽 맨 위): 가로로 긴 판, 정면(+z)에 한 장 그림.
static func _add_fascia(b: PartBuilder, p: Dictionary, lo: Vector2, hi: Vector2, wall_h: float, h_texels: int) -> void:
	var ts: int = p["ts"]
	var sign_h: float = 11.0 * wall_h / float(h_texels)
	var x0: float = lo.x + 0.08
	var x1: float = hi.x - 0.08
	# 지붕 처마(0.14)와 처마 끝 조각(0.09)보다 앞으로 내밀어야 지붕에 가려지지 않는다.
	var y1: float = wall_h - 0.06
	var y0: float = y1 - sign_h
	var z: float = hi.y + 0.28
	var tex: ImageTexture = PlaceholderTextures.bakery_fascia(int(roundf((x1 - x0) * float(ts))), 11)
	var board: Dictionary = spec(tex, Color.WHITE, "bakery_fascia", "빵집 간판 %d×11 (BAKERY 글자 + 양끝 빵), 한 장 전체" % tex.get_width())
	var back: Dictionary = spec(_tex("flat", ts, Color(0.36, 0.22, 0.12)), Color.WHITE, "sign_frame", "간판 뒤판·테두리 어두운 나무 단색 %d×%d" % [ts, ts])
	box(b, "fascia_back", back, Vector3(x0 - 0.02, y0 - 0.02, hi.y + 0.1), Vector3(x1 + 0.02, y1 + 0.02, z - 0.01))
	var st: SurfaceTool = b.new_part(board, Vector3(x0, y0, z), Vector3(x1, y1, z + 0.01))
	BuildingMesh._quad(st, Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1 - 0.01, z), Vector3(x0, y1 - 0.01, z), Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


# 진열대: 나무 카운터. 윗면에 위에서 본 빵 그림(바게트·둥근 빵)을 평면으로 붙인다(입체 빵은 작아서 어색해 보였다).
static func _add_counter(b: PartBuilder, p: Dictionary, x: float, z: float) -> void:
	var wood_a: Dictionary = wood(p, Color(1.0, 0.82, 0.58), "counter_wood")
	var top: Dictionary = spec(PlaceholderTextures.bread_counter_top(p["ts"]), Color.WHITE, "counter_top_bread", "진열대 윗면 %d×%d: 쟁반 + 바게트 둘 + 둥근 빵 셋(위에서 본 평면 그림, 앞쪽 17×8 칸 사용)" % [p["ts"], p["ts"]])
	box(b, "counter", wood_a, Vector3(x - 0.46, 0.0, z - 0.2), Vector3(x + 0.46, 0.5, z + 0.2))
	box(b, "counter_top", top, Vector3(x - 0.48, 0.5, z - 0.22), Vector3(x + 0.48, 0.55, z + 0.22))


# 걸이 간판: 벽에서 앞으로 뻗은 팔 끝에 빵 그림 판이 매달린다. 판은 카메라가 보는 +x 쪽 면에 그림이 나온다.
static func _add_hang_sign(b: PartBuilder, p: Dictionary, x: float, wall_z: float, tip_dz: float, wall_h: float) -> void:
	var iron: Dictionary = spec(_tex("flat", p["ts"], Color(0.2, 0.2, 0.24)), Color.WHITE, "iron", "검은 쇠(기둥·테두리) 단색 %d×%d" % [p["ts"], p["ts"]])
	var frame_wood: Dictionary = spec(_tex("flat", p["ts"], Color(0.36, 0.22, 0.12)), Color.WHITE, "sign_frame", "간판 뒤판·테두리 어두운 나무 단색 %d×%d" % [p["ts"], p["ts"]])
	var board: Dictionary = spec(PlaceholderTextures.bread_sign(), Color.WHITE, "bread_sign", "빵집 간판 그림 16×12 (베이지 판 + 둥근 빵), +x 쪽 면 한 장")
	var y_arm: float = wall_h * 0.8
	var tip_z: float = wall_z + tip_dz
	box(b, "arm", iron, Vector3(x - 0.02, y_arm, wall_z), Vector3(x + 0.02, y_arm + 0.04, tip_z + 0.02))
	var z0: float = tip_z - 1.14
	var z1: float = tip_z - 0.04
	var y1: float = y_arm - 0.07
	var y0: float = y1 - 0.82
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

		if display != null and f[0] in ["counter", "hang_sign", "basket", "bin_baguette", "bin_loaf"]:
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
				_add_hang_sign(tb, p, x, hi.y, z - hi.y, wall_h)
			"basket":
				oct(tb, "basket", spec(PlaceholderTextures.crate(p["ts"], Color(0.62, 0.42, 0.22)), Color.WHITE, "basket", "바구니 옆면 %d×%d 갈색 엮음" % [p["ts"], p["ts"]]), x, z, 0.19, 0.0, 0.26, 0.17)
				_card(tb, _card_spec("loaf", p), x - 0.05, 0.16, z, 0.28, 0.25)
				_card(tb, _card_spec("loaf", p), x + 0.07, 0.2, z - 0.03, 0.26, 0.23)
			"bin_baguette":
				_add_bread_bin(tb, p, x, z, "baguette")
			"bin_loaf":
				_add_bread_bin(tb, p, x, z, "loaf")
			"bush":
				dome(b, "bush", spec(_tex("foliage", p["ts"], Color(0.95, 0.4, 0.55)), Color.WHITE, "bush", "덤불 %d×%d 반복(꽃 점)" % [p["ts"], p["ts"]]), x, z, 0.27, 0.0, 0.34)


# ---------------------------------------------------------------- 소품

static func build_prop(style: String, lo: Vector2, hi: Vector2, rule: Dictionary, p: Dictionary) -> Dictionary:
	var ts: int = p["ts"]
	var b := PartBuilder.new()
	var c: Vector2 = (lo + hi) * 0.5
	var sx: float = hi.x - lo.x
	var sz: float = hi.y - lo.y
	var along_x: bool = sx >= sz
	var total: float = 1.0
	var roof_tint: Color = rule.get("roof_tint", Color(0.8, 0.42, 0.25))
	var tint: Color = rule.get("tint", Color(1, 1, 1))
	var bark: Dictionary = wood(p, Color(0.42, 0.3, 0.2), "bark")
	var iron: Dictionary = spec(_tex("flat", ts, Color(0.2, 0.2, 0.24)), Color.WHITE, "iron", "검은 쇠(기둥·테두리) 단색 %d×%d" % [ts, ts])
	var roof_spec: Dictionary = spec(PlaceholderTextures.roof_tiles(ts, roof_tint), Color.WHITE, "small_roof_tiles", "작은 지붕 기와 %d×%d 반복" % [ts, ts], PlaceholderTextures.roof_normal(ts))

	match style:
		"tree":
			var leaf: Dictionary = spec(_tex("foliage", ts, Color(0.9, 0.3, 0.3)), tint, "tree_foliage", "나뭇잎 %d×%d 반복(짙은 초록 + 밝은 점 + 빨간 열매 점)" % [ts, ts])
			oct(b, "bark", bark, c.x, c.y, 0.13, 0.0, 1.0, 0.1)
			dome(b, "leaf", leaf, c.x, c.y, 0.66, 0.85, 1.55, 3, 12)
			dome(b, "leaf", leaf, c.x, c.y, 0.5, 1.4, 2.0, 3, 12)
			dome(b, "leaf", leaf, c.x, c.y, 0.3, 1.9, 2.35, 2, 10)
			total = 2.25
		"well":
			oct(b, "stone", stone_spec(p, Color(1, 1, 1), "well_stone"), c.x, c.y, 0.58, 0.0, 0.55)
			oct(b, "water", spec(_tex("flat", ts, Color(0.18, 0.3, 0.5)), Color.WHITE, "well_water", "우물 물 단색 %d×%d 어두운 파랑" % [ts, ts]), c.x, c.y, 0.44, 0.5, 0.53)
			box(b, "post", bark, Vector3(c.x - 0.52, 0.0, c.y - 0.04), Vector3(c.x - 0.44, 1.5, c.y + 0.04))
			box(b, "post", bark, Vector3(c.x + 0.44, 0.0, c.y - 0.04), Vector3(c.x + 0.52, 1.5, c.y + 0.04))
			roof_prism(b, "roof", roof_spec, c.x - 0.66, c.x + 0.66, c.y - 0.55, c.y + 0.55, 1.5, 0.45, true)
			total = 1.95
		"stall":
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
			box(b, "lamp", spec(_tex("flat", ts, Color(1.0, 0.85, 0.45)), Color(1.4, 1.3, 1.0), "lantern_glass", "가로등 유리 단색 %d×%d 따뜻한 노랑(밤에 빛남)" % [ts, ts]), Vector3(c.x - 0.1, 1.6, c.y - 0.1), Vector3(c.x + 0.1, 1.86, c.y + 0.1))
			box(b, "cap", iron, Vector3(c.x - 0.13, 1.86, c.y - 0.13), Vector3(c.x + 0.13, 1.92, c.y + 0.13))
			total = 1.95
		"flower_bush":
			dome(b, "bush", spec(_tex("foliage", ts, Color(0.95, 0.4, 0.55)), tint, "flower_bush", "꽃 덤불 %d×%d 반복(짙은 초록 + 분홍 꽃 점)" % [ts, ts]), c.x, c.y, 0.32, 0.0, 0.4)
			total = 0.45
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
	return {"mesh": mesh, "specs": specs, "apron": null, "total_blocks": total, "lo": plo, "hi": phi}


# l(길이 방향)·w(폭 방향) 좌표로 상자를 놓는다(along_x 면 l=x, w=z / 아니면 l=z, w=x).
static func _cart_box(b: PartBuilder, along_x: bool, sp: Dictionary, l0: float, l1: float, w0: float, w1: float, y0: float, y1: float) -> void:
	if along_x:
		box(b, str(sp["name"]), sp, Vector3(l0, y0, w0), Vector3(l1, y1, w1))
	else:
		box(b, str(sp["name"]), sp, Vector3(w0, y0, l0), Vector3(w1, y1, l1))
