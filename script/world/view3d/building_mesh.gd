class_name BuildingMesh
extends RefCounted
## 박공(삼각형 단면) 지붕을 가진 건물 모양 메시. 발자국 칸 사각형(lo~hi, 칸 좌표)과 벽 높이·지붕 높이(세계 단위)로 만든다.
## 지붕은 얇은 판이 아니라 두께가 있는 판(처마 단면, 박공 가장자리)이고, 용마루 덮개·굴뚝·차양·바닥 돌 마당을 함께 만든다.
## 면(surface) 순서와 재질 (store_view_3d / village_mirror 가 이 순서대로 재질을 붙인다):
##   0 = +z 면 벽, 1 = +x 면 벽, 2 = 지붕 윗면 경사 둘(기와, 법선 맵), 3 = 박공 삼각형 + 안 보이는 뒷벽,
##   4 = 지붕 두께(처마·박공 가장자리·밑면)와 용마루 덮개, 5 = 굴뚝(돌), 6 = 차양
##   (바닥 돌 마당은 별도 메시 apron_mesh 로 돌려준다)
## 카메라는 +x, +z 쪽에서 보므로 +z·+x 면 벽과 그쪽 지붕 경사가 주로 보인다.

const SURFACE_WALL_Z: int = 0
const SURFACE_WALL_X: int = 1
const SURFACE_ROOF: int = 2
const SURFACE_GABLE: int = 3
const SURFACE_TRIM: int = 4
const SURFACE_STONE: int = 5
const SURFACE_AWNING: int = 6
const SURFACE_COUNT: int = 7


# options: overhang(처마 내밀기), thickness(지붕 두께), ridge_cap(용마루 덮개 높이), chimney(굴뚝 유무), awning(차양 유무), apron(마당 여백, 0 이면 없음)
# into: 이미 부품(돌 기단 등 건물 뒤에 그릴 것)이 담긴 메시에 이어서 만들고 싶을 때 넘긴다.
# 굴뚝을 용마루 끝에서 안쪽으로 들이는 거리(처마 끝에 걸쳐 위태롭게 보이지 않게). 굴뚝 연기 위치도 같은 값을 쓴다.
const CHIMNEY_INSET: float = 1.0


static func build(lo: Vector2, hi: Vector2, wall_h: float, roof_h: float, options: Dictionary = {}, into: ArrayMesh = null) -> Dictionary:
	var overhang: float = options.get("overhang", 0.14)
	var t: float = options.get("thickness", 0.07)
	var cap: float = options.get("ridge_cap", 0.1)
	var w: float = hi.x - lo.x
	var d: float = hi.y - lo.y
	var ridge_x: bool = w >= d
	var mesh: ArrayMesh = into if into != null else ArrayMesh.new()
	var present: Array = []  # 면 순서대로, 실제로 면이 생겼는지(빈 면은 mesh 에 들어가지 않음)
	var peak: float = wall_h + roof_h
	# 용마루 축(u)과 가로(v) 좌표: 용마루가 x 방향이면 u=x, v=z / 아니면 u=z, v=x
	var u0: float = (lo.x if ridge_x else lo.y)
	var u1: float = (hi.x if ridge_x else hi.y)
	var v0: float = (lo.y if ridge_x else lo.x)
	var v1: float = (hi.y if ridge_x else hi.x)
	var vc: float = (v0 + v1) * 0.5
	var hs: float = (v1 - v0) * 0.5 + overhang
	var ua: float = u0 - overhang
	var ub: float = u1 + overhang
	var slope_len: float = sqrt(hs * hs + roof_h * roof_h)
	# 경사면의 바깥쪽 법선(v 방향 성분 nv, 위 성분 ny)
	var nv: float = roof_h / slope_len
	var ny: float = hs / slope_len
	# 사방 경사(모임지붕): 용마루를 양 끝에서 hs 만큼 줄이고, 양 끝에도 경사면을 둔다(박공 삼각형 없음).
	var hip: bool = bool(options.get("hip", false))
	var mid: float = (ua + ub) * 0.5
	var r0: float = minf(ua + hs, mid)
	var r1: float = maxf(ub - hs, mid)

	# --- 0, 1: 벽 (+z 면, +x 면)
	var st := _begin()
	_quad(st, Vector3(lo.x, 0, hi.y), Vector3(hi.x, 0, hi.y), Vector3(hi.x, wall_h, hi.y), Vector3(lo.x, wall_h, hi.y), Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	present.append(_commit(st, mesh))
	st = _begin()
	_quad(st, Vector3(hi.x, 0, hi.y), Vector3(hi.x, 0, lo.y), Vector3(hi.x, wall_h, lo.y), Vector3(hi.x, wall_h, hi.y), Vector3(1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	present.append(_commit(st, mesh))

	var roof_style: String = str(options.get("roof_style", ""))

	if LAYERED_KINDS.has(roof_style):
		_layered_roof(mesh, present, lo, hi, wall_h, roof_h, options, ridge_x, roof_style)
	else:
		_standard_roof_faces(mesh, present, lo, hi, wall_h, roof_h, options, ridge_x)

	_chimney_and_awning(mesh, present, lo, hi, wall_h, roof_h, options, ridge_x)

	# --- 바닥 돌 마당은 건물과 다른 메시(apron). 건물과 같은 깊이로 그리면 건물 뒤 땅이 벽 위에 덮여서 따로 둔다.
	var apron_mesh := ArrayMesh.new()
	var apron: float = options.get("apron", 0.45)

	if apron > 0.0:
		var ast := _begin()
		var y_ap: float = 0.0
		_quad(ast, Vector3(lo.x - apron, y_ap, hi.y + apron), Vector3(hi.x + apron, y_ap, hi.y + apron), Vector3(hi.x + apron, y_ap, lo.y - apron), Vector3(lo.x - apron, y_ap, lo.y - apron), Vector3(0, 1, 0), Vector2(lo.x - apron, hi.y + apron), Vector2(hi.x + apron, hi.y + apron), Vector2(hi.x + apron, lo.y - apron), Vector2(lo.x - apron, lo.y - apron))
		ast.commit(apron_mesh)

	return {"mesh": mesh, "apron_mesh": apron_mesh, "ridge_x": ridge_x, "present": present}


# ---------------------------------------------------------------- 좌표 변환·기본 도형

# 용마루 축 좌표계(u: 용마루 방향, v: 가로) → 세계 좌표
static func _p(ridge_x: bool, u: float, v: float, y: float) -> Vector3:
	return Vector3(u, y, v) if ridge_x else Vector3(v, y, u)


static func _n(ridge_x: bool, nu: float, nv: float, ny: float) -> Vector3:
	return Vector3(nu, ny, nv).normalized() if ridge_x else Vector3(nv, ny, nu).normalized()


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# 축에 맞춘 상자(굴뚝·용마루 덮개용). 용마루 축 좌표(u0~u1, v0~v1)와 y0~y1. 각 면 UV 는 세계 길이(칸) 단위.
static func _box_uv(st: SurfaceTool, ridge_x: bool, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	var c: Array = [
		_p(ridge_x, u0, v0, y0), _p(ridge_x, u1, v0, y0), _p(ridge_x, u1, v1, y0), _p(ridge_x, u0, v1, y0),
		_p(ridge_x, u0, v0, y1), _p(ridge_x, u1, v0, y1), _p(ridge_x, u1, v1, y1), _p(ridge_x, u0, v1, y1),
	]
	var du: float = u1 - u0
	var dv: float = v1 - v0
	var dy: float = y1 - y0
	# 윗면
	_quad(st, c[4], c[5], c[6], c[7], Vector3.UP, Vector2(0, 0), Vector2(du, 0), Vector2(du, dv), Vector2(0, dv))
	# 옆 네 면 (바깥 법선은 u/v 방향)
	_quad(st, c[0], c[1], c[5], c[4], _n(ridge_x, 0.0, -1.0, 0.0), Vector2(0, dy), Vector2(du, dy), Vector2(du, 0), Vector2(0, 0))
	_quad(st, c[1], c[2], c[6], c[5], _n(ridge_x, 1.0, 0.0, 0.0), Vector2(0, dy), Vector2(dv, dy), Vector2(dv, 0), Vector2(0, 0))
	_quad(st, c[2], c[3], c[7], c[6], _n(ridge_x, 0.0, 1.0, 0.0), Vector2(0, dy), Vector2(du, dy), Vector2(du, 0), Vector2(0, 0))
	_quad(st, c[3], c[0], c[4], c[7], _n(ridge_x, -1.0, 0.0, 0.0), Vector2(0, dy), Vector2(dv, dy), Vector2(dv, 0), Vector2(0, 0))


# 사각형 한 장. 정점 a,b,c,d 는 같은 방향으로 이어진 순서, n 은 바깥쪽 법선. Godot 앞면은 시계 방향이라 맞춰서 뒤집는다.
# 면을 mesh 에 붙이고, 실제로 면이 생겼는지 돌려준다(꼭짓점이 없으면 면이 생기지 않는다).
static func _commit(st: SurfaceTool, mesh: ArrayMesh) -> bool:
	var before: int = mesh.get_surface_count()
	st.commit(mesh)
	return mesh.get_surface_count() > before


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, n, ua, ub, uc)
	_tri(st, a, c, d, n, ua, uc, ud)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var cross: Vector3 = (b - a).cross(c - a)

	if cross.dot(n) > 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
		var tuv: Vector2 = ub
		ub = uc
		uc = tuv

	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(n)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


# ---------------------------------------------------------------- 층층 지붕(갬블·맨사드·반 박공)
const LAYERED_KINDS: Array = ["gambrel", "mansard", "half_hip"]


# 지붕을 단면 목록으로 나타낸다. 각 항목: y(높이), ui(양 끝에서 안쪽으로 들어간 거리), vh(용마루에서 처마 쪽 반폭).
# 첫 항목이 처마(벽 꼭대기), 마지막이 용마루. 기본 박공은 [처마, 용마루] 둘뿐이다.
static func roof_levels(kind: String, wall_h: float, roof_h: float, hs: float, len_u: float) -> Array:
	var peak: float = wall_h + roof_h
	var max_in: float = len_u * 0.4

	if kind == "gambrel":
		return [{"y": wall_h, "ui": 0.0, "vh": hs}, {"y": wall_h + roof_h * 0.72, "ui": 0.0, "vh": hs * 0.52}, {"y": peak, "ui": 0.0, "vh": 0.0}]

	if kind == "mansard":
		return [{"y": wall_h, "ui": 0.0, "vh": hs}, {"y": wall_h + roof_h * 0.78, "ui": minf(hs * 0.42, max_in), "vh": hs * 0.58}, {"y": peak, "ui": minf(hs * 0.95, max_in), "vh": 0.0}]

	if kind == "half_hip":
		return [{"y": wall_h, "ui": 0.0, "vh": hs}, {"y": wall_h + roof_h * 0.62, "ui": 0.0, "vh": hs * 0.38}, {"y": peak, "ui": minf(hs * 0.55, max_in), "vh": 0.0}]

	return [{"y": wall_h, "ui": 0.0, "vh": hs}, {"y": peak, "ui": 0.0, "vh": 0.0}]


# 용마루에서 가로로 w 만큼 떨어진 곳의 지붕 표면 높이(w 가 처마보다 크면 처마 높이)
static func roof_y_at(levels: Array, w: float) -> float:
	var a: float = absf(w)

	for k in range(levels.size() - 1):
		var l0: Dictionary = levels[k]
		var l1: Dictionary = levels[k + 1]

		if a <= float(l0["vh"]) and a >= float(l1["vh"]):
			var span: float = float(l0["vh"]) - float(l1["vh"])
			var t: float = 0.0 if span < 0.0001 else (float(l0["vh"]) - a) / span
			return lerpf(float(l0["y"]), float(l1["y"]), t)

	return float(levels[0]["y"]) if a > float(levels[0]["vh"]) else float(levels[levels.size() - 1]["y"])


# 면 2(지붕 윗면)·3(박공 벽)·4(두께·용마루 덮개)를 층층 지붕으로 만들어 mesh 에 붙이고, present 에 세 개를 덧붙인다.
static func _layered_roof(mesh: ArrayMesh, present: Array, lo: Vector2, hi: Vector2, wall_h: float, roof_h: float, options: Dictionary, ridge_x: bool, kind: String) -> void:
	var overhang: float = options.get("overhang", 0.14)
	var t: float = options.get("thickness", 0.07)
	var cap: float = options.get("ridge_cap", 0.1)
	var u0: float = (lo.x if ridge_x else lo.y)
	var u1: float = (hi.x if ridge_x else hi.y)
	var v0: float = (lo.y if ridge_x else lo.x)
	var v1: float = (hi.y if ridge_x else hi.x)
	var vc: float = (v0 + v1) * 0.5
	var hs: float = (v1 - v0) * 0.5 + overhang
	var ua: float = u0 - overhang
	var ub: float = u1 + overhang
	var levels: Array = roof_levels(kind, wall_h, roof_h, hs, ub - ua)
	var n_levels: int = levels.size()
	var up_st := _begin()
	var gab_st := _begin()

	for k in range(n_levels - 1):
		var l0: Dictionary = levels[k]
		var l1: Dictionary = levels[k + 1]
		var y0: float = l0["y"]
		var y1: float = l1["y"]
		var i0: float = l0["ui"]
		var i1: float = l1["ui"]
		var h0: float = l0["vh"]
		var h1: float = l1["vh"]

		# 앞뒤 경사(v 쪽)
		for side in [1.0, -1.0]:
			var a: Vector3 = _p(ridge_x, ua + i0, vc + side * h0, y0)
			var b: Vector3 = _p(ridge_x, ub - i0, vc + side * h0, y0)
			var c: Vector3 = _p(ridge_x, ub - i1, vc + side * h1, y1)
			var d: Vector3 = _p(ridge_x, ua + i1, vc + side * h1, y1)
			var run: float = h0 - h1
			var rise: float = y1 - y0
			var n: Vector3 = _n(ridge_x, 0.0, side * rise, run)
			var slen: float = sqrt(run * run + rise * rise)
			up_st_quad(up_st, a, b, c, d, n, ub - ua, slen)

		# 양 끝: 들어간 거리가 같으면 세로 박공 벽, 다르면 경사
		for end_sign in [1.0, -1.0]:
			var ue0: float = (ub - i0) if end_sign > 0.0 else (ua + i0)
			var ue1: float = (ub - i1) if end_sign > 0.0 else (ua + i1)
			var ea: Vector3 = _p(ridge_x, ue0, vc + h0, y0)
			var eb: Vector3 = _p(ridge_x, ue0, vc - h0, y0)
			var ec: Vector3 = _p(ridge_x, ue1, vc - h1, y1)
			var ed: Vector3 = _p(ridge_x, ue1, vc + h1, y1)

			if absf(i1 - i0) < 0.0001:
				_quad(gab_st, ea, eb, ec, ed, _n(ridge_x, end_sign, 0.0, 0.0), Vector2(0, 1), Vector2(h0 * 2.0, 1), Vector2(h1 * 2.0, 0), Vector2(0, 0))
			else:
				var run_u: float = absf(i1 - i0)
				var rise_e: float = y1 - y0
				_quad(up_st, ea, eb, ec, ed, _n(ridge_x, end_sign * rise_e, 0.0, run_u), Vector2(0, 1), Vector2(h0 * 2.0, 1), Vector2(h1 * 2.0, 0), Vector2(0, 0))

	up_st.generate_tangents()
	present.append(_commit(up_st, mesh))
	# 박공 벽: 세로 부분만 + 안 보이는 뒷벽 둘(그림자·가림용)
	_quad(gab_st, Vector3(lo.x, 0, lo.y), Vector3(lo.x, 0, hi.y), Vector3(lo.x, wall_h, hi.y), Vector3(lo.x, wall_h, lo.y), Vector3(-1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	_quad(gab_st, Vector3(hi.x, 0, lo.y), Vector3(lo.x, 0, lo.y), Vector3(lo.x, wall_h, lo.y), Vector3(hi.x, wall_h, lo.y), Vector3(0, 0, -1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	present.append(_commit(gab_st, mesh))
	# 두께: 처마 단면(앞뒤) + 용마루 덮개
	var tr := _begin()

	for side in [1.0, -1.0]:
		var ev: float = vc + side * hs
		_quad(tr, _p(ridge_x, ua, ev, wall_h), _p(ridge_x, ub, ev, wall_h), _p(ridge_x, ub, ev, wall_h - t), _p(ridge_x, ua, ev, wall_h - t), _n(ridge_x, 0.0, side, 0.0), Vector2(0, 0), Vector2(ub - ua, 0), Vector2(ub - ua, 1), Vector2(0, 1))

	# 끝 처마 단면(경사 끝이 있는 모양일 때)
	var first_in: float = float(levels[1]["ui"]) if n_levels > 1 else 0.0

	if first_in > 0.0001:
		for end_sign2 in [1.0, -1.0]:
			var ue2: float = ub if end_sign2 > 0.0 else ua
			_quad(tr, _p(ridge_x, ue2, vc + hs, wall_h), _p(ridge_x, ue2, vc - hs, wall_h), _p(ridge_x, ue2, vc - hs, wall_h - t), _p(ridge_x, ue2, vc + hs, wall_h - t), _n(ridge_x, end_sign2, 0.0, 0.0), Vector2(0, 0), Vector2(hs * 2.0, 0), Vector2(hs * 2.0, 1), Vector2(0, 1))

	var top_in: float = float(levels[n_levels - 1]["ui"])
	_box_uv(tr, ridge_x, ua + top_in - 0.04, ub - top_in + 0.04, vc - 0.08, vc + 0.08, wall_h + roof_h - 0.02, wall_h + roof_h + cap)
	present.append(_commit(tr, mesh))


# 사각형 한 장(지붕 윗면): 길이 방향 UV 는 u_len, 경사 방향 UV 는 s_len(칸)
static func up_st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, u_len: float, s_len: float) -> void:
	_quad(st, a, b, c, d, n, Vector2(0, s_len), Vector2(u_len, s_len), Vector2(u_len, 0), Vector2(0, 0))


static func _standard_roof_faces(mesh: ArrayMesh, present: Array, lo: Vector2, hi: Vector2, wall_h: float, roof_h: float, options: Dictionary, ridge_x: bool) -> void:
	var overhang: float = options.get("overhang", 0.14)
	var t: float = options.get("thickness", 0.07)
	var cap: float = options.get("ridge_cap", 0.1)
	var w: float = hi.x - lo.x
	var d: float = hi.y - lo.y
	var peak: float = wall_h + roof_h
	var u0: float = (lo.x if ridge_x else lo.y)
	var u1: float = (hi.x if ridge_x else hi.y)
	var v0: float = (lo.y if ridge_x else lo.x)
	var v1: float = (hi.y if ridge_x else hi.x)
	var vc: float = (v0 + v1) * 0.5
	var hs: float = (v1 - v0) * 0.5 + overhang
	var ua: float = u0 - overhang
	var ub: float = u1 + overhang
	var slope_len: float = sqrt(hs * hs + roof_h * roof_h)
	var nv: float = roof_h / slope_len
	var ny: float = hs / slope_len
	var hip: bool = bool(options.get("hip", false))
	var mid: float = (ua + ub) * 0.5
	var r0: float = minf(ua + hs, mid)
	var r1: float = maxf(ub - hs, mid)
	var st: SurfaceTool
	# --- 2: 지붕 윗면 경사 둘 (UV: 용마루 방향 u 칸, 경사 방향 칸). 기와 법선 맵을 위해 접선 계산
	st = _begin()

	for side in [1.0, -1.0]:
		var n: Vector3 = _n(ridge_x, 0.0, side * nv, ny)
		var eave_v: float = vc + side * hs
		var q_a: Vector3 = _p(ridge_x, ua, eave_v, wall_h)
		var q_b: Vector3 = _p(ridge_x, ub, eave_v, wall_h)
		var r_b: Vector3 = _p(ridge_x, (r1 if hip else ub), vc, peak)
		var r_a: Vector3 = _p(ridge_x, (r0 if hip else ua), vc, peak)

		if hip:
			_quad(st, q_a, q_b, r_b, r_a, n, Vector2(0, slope_len), Vector2(ub - ua, slope_len), Vector2(r1 - ua, 0), Vector2(r0 - ua, 0))
		else:
			_quad(st, q_a, q_b, r_b, r_a, n, Vector2(0, slope_len), Vector2(ub - ua, slope_len), Vector2(ub - ua, 0), Vector2(0, 0))

	if hip:
		for end_side in [1.0, -1.0]:
			var ue: float = ub if end_side > 0.0 else ua
			var ur: float = r1 if end_side > 0.0 else r0
			var ne: Vector3 = _n(ridge_x, end_side * nv, 0.0, ny)
			_tri(st, _p(ridge_x, ue, vc + hs, wall_h), _p(ridge_x, ue, vc - hs, wall_h), _p(ridge_x, ur, vc, peak), ne, Vector2(0, slope_len), Vector2(hs * 2.0, slope_len), Vector2(hs, 0))

	st.generate_tangents()
	present.append(_commit(st, mesh))

	# --- 3: 박공 삼각형 둘 + 뒷벽 둘(그림자·가림용)
	st = _begin()

	for end_sign in ([] if hip else [1.0, -1.0]):
		var uu: float = u1 if end_sign > 0.0 else u0
		_tri(st, _p(ridge_x, uu, v1, wall_h), _p(ridge_x, uu, v0, wall_h), _p(ridge_x, uu, vc, peak), _n(ridge_x, end_sign, 0.0, 0.0), Vector2(0, 1), Vector2(v1 - v0, 1), Vector2((v1 - v0) * 0.5, 1.0 - roof_h))

	_quad(st, Vector3(lo.x, 0, lo.y), Vector3(lo.x, 0, hi.y), Vector3(lo.x, wall_h, hi.y), Vector3(lo.x, wall_h, lo.y), Vector3(-1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	_quad(st, Vector3(hi.x, 0, lo.y), Vector3(lo.x, 0, lo.y), Vector3(lo.x, wall_h, lo.y), Vector3(hi.x, wall_h, lo.y), Vector3(0, 0, -1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	present.append(_commit(st, mesh))

	# --- 4: 지붕 두께(처마·박공 가장자리·밑면) + 용마루 덮개. 단색에 가까운 어두운 목재/기와 색 질감 사용
	st = _begin()

	for side in [1.0, -1.0]:
		var n_roof: Vector3 = _n(ridge_x, 0.0, side * nv, ny)
		var down: Vector3 = -n_roof * t  # 윗면에서 밑면으로
		var eave_v2: float = vc + side * hs
		var top_eave_a: Vector3 = _p(ridge_x, ua, eave_v2, wall_h)
		var top_eave_b: Vector3 = _p(ridge_x, ub, eave_v2, wall_h)
		var top_ridge_a: Vector3 = _p(ridge_x, ua, vc, peak)
		var top_ridge_b: Vector3 = _p(ridge_x, ub, vc, peak)
		var bot_eave_a: Vector3 = top_eave_a + down
		var bot_eave_b: Vector3 = top_eave_b + down
		var bot_ridge_a: Vector3 = top_ridge_a + down
		var bot_ridge_b: Vector3 = top_ridge_b + down
		# 처마 단면(경사 아래 끝): 바깥 방향(v) 법선
		_quad(st, top_eave_a, top_eave_b, bot_eave_b, bot_eave_a, _n(ridge_x, 0.0, side, 0.0), Vector2(0, 0), Vector2(ub - ua, 0), Vector2(ub - ua, 1), Vector2(0, 1))
		if hip:
			continue

		# 박공 가장자리 둘(경사를 따라 달리는 두께 면): 용마루 축 바깥 방향 법선
		_quad(st, top_eave_b, top_ridge_b, bot_ridge_b, bot_eave_b, _n(ridge_x, 1.0, 0.0, 0.0), Vector2(0, 0), Vector2(slope_len, 0), Vector2(slope_len, 1), Vector2(0, 1))
		_quad(st, top_ridge_a, top_eave_a, bot_eave_a, bot_ridge_a, _n(ridge_x, -1.0, 0.0, 0.0), Vector2(0, 0), Vector2(slope_len, 0), Vector2(slope_len, 1), Vector2(0, 1))
		# 밑면
		_quad(st, bot_eave_a, bot_eave_b, bot_ridge_b, bot_ridge_a, -n_roof, Vector2(0, 0), Vector2(ub - ua, 0), Vector2(ub - ua, slope_len), Vector2(0, slope_len))

	if hip:
		# 양 끝 처마 단면(두께)
		for end_side2 in [1.0, -1.0]:
			var ue2: float = ub if end_side2 > 0.0 else ua
			_quad(st, _p(ridge_x, ue2, vc + hs, wall_h), _p(ridge_x, ue2, vc - hs, wall_h), _p(ridge_x, ue2, vc - hs, wall_h - t), _p(ridge_x, ue2, vc + hs, wall_h - t), _n(ridge_x, end_side2, 0.0, 0.0), Vector2(0, 0), Vector2(hs * 2.0, 0), Vector2(hs * 2.0, 1), Vector2(0, 1))

	# 용마루 덮개: 길이 ua..ub, 폭 0.16, 높이 cap (윗면 + 양쪽 옆 + 양 끝)
	var cw: float = 0.08
	_box_uv(st, ridge_x, (r0 - 0.04 if hip else ua), (r1 + 0.04 if hip else ub), vc - cw, vc + cw, peak - 0.02, peak + cap)
	present.append(_commit(st, mesh))



static func _chimney_and_awning(mesh: ArrayMesh, present: Array, lo: Vector2, hi: Vector2, wall_h: float, roof_h: float, options: Dictionary, ridge_x: bool) -> void:
	var peak: float = wall_h + roof_h
	var u1: float = (hi.x if ridge_x else hi.y)
	var v0: float = (lo.y if ridge_x else lo.x)
	var v1: float = (hi.y if ridge_x else hi.x)
	var vc: float = (v0 + v1) * 0.5
	var hs: float = (v1 - v0) * 0.5 + options.get("overhang", 0.14)
	var st: SurfaceTool
	# --- 5: 굴뚝 (돌 질감 칸당 반복 UV). 지붕 먼 쪽 경사 위, 용마루 끝 가까이
	st = _begin()

	if options.get("chimney", true):
		var cu: float = u1 - CHIMNEY_INSET
		var cv: float = vc + 0.2  # 보이는 쪽(+) 경사 위
		var slope_y: float = wall_h + roof_h * (1.0 - 0.2 / hs * 1.0)  # cv 위치의 지붕 표면 높이(근사)
		var base_y: float = slope_y - 0.12
		var big: bool = bool(options.get("chimney_big", false))
		var ch: float = 0.26 if big else 0.15
		var top_y: float = peak + (0.65 if big else 0.2)
		_box_uv(st, ridge_x, cu - ch, cu + ch, cv - ch, cv + ch, base_y, top_y)
		_box_uv(st, ridge_x, cu - ch - 0.05, cu + ch + 0.05, cv - ch - 0.05, cv + ch + 0.05, top_y, top_y + 0.06)  # 머릿돌

	present.append(_commit(st, mesh))

	# --- 6: 차양(+z 면 위, 비스듬한 면). 위쪽은 벽에 붙고 아래쪽이 앞으로 나온다
	st = _begin()

	if options.get("awning", true):
		var ax0: float = lo.x + 0.12
		var ax1: float = hi.x - 0.12
		var top_y2: float = wall_h * 0.78
		var bot_y: float = wall_h * 0.56
		var out: float = 0.42
		var n_aw: Vector3 = Vector3(0.0, out, (top_y2 - bot_y)).normalized()
		_quad(st, Vector3(ax0, top_y2, hi.y), Vector3(ax1, top_y2, hi.y), Vector3(ax1, bot_y, hi.y + out), Vector3(ax0, bot_y, hi.y + out), n_aw, Vector2(0, 0), Vector2(ax1 - ax0, 0), Vector2(ax1 - ax0, 1), Vector2(0, 1))
		# 아래 단면(얇은 앞 가장자리)
		_quad(st, Vector3(ax0, bot_y, hi.y + out), Vector3(ax1, bot_y, hi.y + out), Vector3(ax1, bot_y - 0.05, hi.y + out), Vector3(ax0, bot_y - 0.05, hi.y + out), Vector3(0, 0, 1), Vector2(0, 0), Vector2(ax1 - ax0, 0), Vector2(ax1 - ax0, 0.1), Vector2(0, 0.1))

	present.append(_commit(st, mesh))

