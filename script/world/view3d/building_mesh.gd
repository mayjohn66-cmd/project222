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
static func build(lo: Vector2, hi: Vector2, wall_h: float, roof_h: float, options: Dictionary = {}, into: ArrayMesh = null) -> Dictionary:
	var overhang: float = options.get("overhang", 0.14)
	var t: float = options.get("thickness", 0.07)
	var cap: float = options.get("ridge_cap", 0.1)
	var w: float = hi.x - lo.x
	var d: float = hi.y - lo.y
	var ridge_x: bool = w >= d
	var mesh: ArrayMesh = into if into != null else ArrayMesh.new()
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

	# --- 0, 1: 벽 (+z 면, +x 면)
	var st := _begin()
	_quad(st, Vector3(lo.x, 0, hi.y), Vector3(hi.x, 0, hi.y), Vector3(hi.x, wall_h, hi.y), Vector3(lo.x, wall_h, hi.y), Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	st.commit(mesh)
	st = _begin()
	_quad(st, Vector3(hi.x, 0, hi.y), Vector3(hi.x, 0, lo.y), Vector3(hi.x, wall_h, lo.y), Vector3(hi.x, wall_h, hi.y), Vector3(1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	st.commit(mesh)

	# --- 2: 지붕 윗면 경사 둘 (UV: 용마루 방향 u 칸, 경사 방향 칸). 기와 법선 맵을 위해 접선 계산
	st = _begin()

	for side in [1.0, -1.0]:
		var n: Vector3 = _n(ridge_x, 0.0, side * nv, ny)
		var eave_v: float = vc + side * hs
		var q_a: Vector3 = _p(ridge_x, ua, eave_v, wall_h)
		var q_b: Vector3 = _p(ridge_x, ub, eave_v, wall_h)
		var r_b: Vector3 = _p(ridge_x, ub, vc, peak)
		var r_a: Vector3 = _p(ridge_x, ua, vc, peak)
		_quad(st, q_a, q_b, r_b, r_a, n, Vector2(0, slope_len), Vector2(ub - ua, slope_len), Vector2(ub - ua, 0), Vector2(0, 0))

	st.generate_tangents()
	st.commit(mesh)

	# --- 3: 박공 삼각형 둘 + 뒷벽 둘(그림자·가림용)
	st = _begin()

	for end_sign in [1.0, -1.0]:
		var uu: float = u1 if end_sign > 0.0 else u0
		_tri(st, _p(ridge_x, uu, v1, wall_h), _p(ridge_x, uu, v0, wall_h), _p(ridge_x, uu, vc, peak), _n(ridge_x, end_sign, 0.0, 0.0), Vector2(0, 1), Vector2(v1 - v0, 1), Vector2((v1 - v0) * 0.5, 1.0 - roof_h))

	_quad(st, Vector3(lo.x, 0, lo.y), Vector3(lo.x, 0, hi.y), Vector3(lo.x, wall_h, hi.y), Vector3(lo.x, wall_h, lo.y), Vector3(-1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	_quad(st, Vector3(hi.x, 0, lo.y), Vector3(lo.x, 0, lo.y), Vector3(lo.x, wall_h, lo.y), Vector3(hi.x, wall_h, lo.y), Vector3(0, 0, -1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	st.commit(mesh)

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
		# 박공 가장자리 둘(경사를 따라 달리는 두께 면): 용마루 축 바깥 방향 법선
		_quad(st, top_eave_b, top_ridge_b, bot_ridge_b, bot_eave_b, _n(ridge_x, 1.0, 0.0, 0.0), Vector2(0, 0), Vector2(slope_len, 0), Vector2(slope_len, 1), Vector2(0, 1))
		_quad(st, top_ridge_a, top_eave_a, bot_eave_a, bot_ridge_a, _n(ridge_x, -1.0, 0.0, 0.0), Vector2(0, 0), Vector2(slope_len, 0), Vector2(slope_len, 1), Vector2(0, 1))
		# 밑면
		_quad(st, bot_eave_a, bot_eave_b, bot_ridge_b, bot_ridge_a, -n_roof, Vector2(0, 0), Vector2(ub - ua, 0), Vector2(ub - ua, slope_len), Vector2(0, slope_len))

	# 용마루 덮개: 길이 ua..ub, 폭 0.16, 높이 cap (윗면 + 양쪽 옆 + 양 끝)
	var cw: float = 0.08
	_box_uv(st, ridge_x, ua, ub, vc - cw, vc + cw, peak - 0.02, peak + cap)
	st.commit(mesh)

	# --- 5: 굴뚝 (돌 질감 칸당 반복 UV). 지붕 먼 쪽 경사 위, 용마루 끝 가까이
	st = _begin()

	if options.get("chimney", true):
		var cu: float = u1 - 0.6
		var cv: float = vc + 0.2  # 보이는 쪽(+) 경사 위
		var slope_y: float = wall_h + roof_h * (1.0 - 0.2 / hs * 1.0)  # cv 위치의 지붕 표면 높이(근사)
		var base_y: float = slope_y - 0.12
		var top_y: float = peak + 0.2
		_box_uv(st, ridge_x, cu - 0.15, cu + 0.15, cv - 0.15, cv + 0.15, base_y, top_y)
		_box_uv(st, ridge_x, cu - 0.2, cu + 0.2, cv - 0.2, cv + 0.2, top_y, top_y + 0.06)  # 머릿돌

	st.commit(mesh)

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

	st.commit(mesh)

	# --- 바닥 돌 마당은 건물과 다른 메시(apron). 건물과 같은 깊이로 그리면 건물 뒤 땅이 벽 위에 덮여서 따로 둔다.
	var apron_mesh := ArrayMesh.new()
	var apron: float = options.get("apron", 0.45)

	if apron > 0.0:
		var ast := _begin()
		var y_ap: float = 0.0
		_quad(ast, Vector3(lo.x - apron, y_ap, hi.y + apron), Vector3(hi.x + apron, y_ap, hi.y + apron), Vector3(hi.x + apron, y_ap, lo.y - apron), Vector3(lo.x - apron, y_ap, lo.y - apron), Vector3(0, 1, 0), Vector2(lo.x - apron, hi.y + apron), Vector2(hi.x + apron, hi.y + apron), Vector2(hi.x + apron, lo.y - apron), Vector2(lo.x - apron, lo.y - apron))
		ast.commit(apron_mesh)

	return {"mesh": mesh, "apron_mesh": apron_mesh, "ridge_x": ridge_x}


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
