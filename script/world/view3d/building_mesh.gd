class_name BuildingMesh
extends RefCounted
## 박공(삼각형 단면) 지붕을 가진 건물 모양 메시. 발자국 칸 사각형(lo~hi, 칸 좌표)과 벽 높이·지붕 높이(세계 단위)로 만든다.
## 면(surface) 순서: 0 = +z 면 벽, 1 = +x 면 벽, 2 = 지붕 경사 둘(기와 반복), 3 = 박공 삼각형(+ 안 보이는 뒷벽, 그림자용).
## 카메라는 +x, +z 쪽에서 보므로 +z 면과 +x 면 벽, 그리고 +z/+x 쪽 지붕 경사가 주로 보인다.

const SURFACE_WALL_Z: int = 0
const SURFACE_WALL_X: int = 1
const SURFACE_ROOF: int = 2
const SURFACE_GABLE: int = 3


# 반환: {"mesh": ArrayMesh, "ridge_x": 용마루가 x 방향인가}
static func build(lo: Vector2, hi: Vector2, wall_h: float, roof_h: float, overhang: float = 0.12) -> Dictionary:
	var w: float = hi.x - lo.x
	var d: float = hi.y - lo.y
	var ridge_x: bool = w >= d
	var mesh := ArrayMesh.new()
	var x0: float = lo.x
	var x1: float = hi.x
	var z0: float = lo.y
	var z1: float = hi.y
	var zc: float = (z0 + z1) * 0.5
	var xc: float = (x0 + x1) * 0.5

	# 0) +z 면 벽: 왼쪽(x0) → 오른쪽(x1), 아래 → 위. UV: u = x 방향, v = 위 0 아래 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, wall_h, z1), Vector3(x0, wall_h, z1), Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	st.commit(mesh)

	# 1) +x 면 벽: 왼쪽(z1) → 오른쪽(z0) (카메라에서 보이는 순서), UV u 는 z 가 줄어드는 방향
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x1, wall_h, z0), Vector3(x1, wall_h, z1), Vector3(1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	st.commit(mesh)

	# 2) 지붕 경사 둘. UV 는 세계 길이(칸) 단위 → 질감 한 장 = 한 칸(uv_scale 1)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var peak: float = wall_h + roof_h

	if ridge_x:
		var a: float = x0 - overhang
		var b: float = x1 + overhang
		var slope_len: float = sqrt(pow(d * 0.5 + overhang, 2.0) + roof_h * roof_h)
		# +z 쪽 경사
		var n_pos: Vector3 = Vector3(0.0, d * 0.5 + overhang, roof_h).normalized()
		_quad(st, Vector3(a, wall_h, z1 + overhang), Vector3(b, wall_h, z1 + overhang), Vector3(b, peak, zc), Vector3(a, peak, zc), n_pos, Vector2(0, slope_len), Vector2(b - a, slope_len), Vector2(b - a, 0), Vector2(0, 0))
		# -z 쪽 경사
		var n_neg: Vector3 = Vector3(0.0, d * 0.5 + overhang, -roof_h).normalized()
		_quad(st, Vector3(b, wall_h, z0 - overhang), Vector3(a, wall_h, z0 - overhang), Vector3(a, peak, zc), Vector3(b, peak, zc), n_neg, Vector2(0, slope_len), Vector2(b - a, slope_len), Vector2(b - a, 0), Vector2(0, 0))
	else:
		var a2: float = z0 - overhang
		var b2: float = z1 + overhang
		var slope_len2: float = sqrt(pow(w * 0.5 + overhang, 2.0) + roof_h * roof_h)
		# +x 쪽 경사
		var n_pos2: Vector3 = Vector3(roof_h, w * 0.5 + overhang, 0.0).normalized()
		_quad(st, Vector3(x1 + overhang, wall_h, b2), Vector3(x1 + overhang, wall_h, a2), Vector3(xc, peak, a2), Vector3(xc, peak, b2), n_pos2, Vector2(0, slope_len2), Vector2(b2 - a2, slope_len2), Vector2(b2 - a2, 0), Vector2(0, 0))
		# -x 쪽 경사
		var n_neg2: Vector3 = Vector3(-roof_h, w * 0.5 + overhang, 0.0).normalized()
		_quad(st, Vector3(x0 - overhang, wall_h, a2), Vector3(x0 - overhang, wall_h, b2), Vector3(xc, peak, b2), Vector3(xc, peak, a2), n_neg2, Vector2(0, slope_len2), Vector2(b2 - a2, slope_len2), Vector2(b2 - a2, 0), Vector2(0, 0))

	st.commit(mesh)

	# 3) 박공 삼각형 둘(용마루 양 끝) + 안 보이는 뒷벽 둘(그림자 모양용). 색은 벽 질감 한 칸을 반복해 쓴다.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if ridge_x:
		_tri(st, Vector3(x1, wall_h, z1), Vector3(x1, wall_h, z0), Vector3(x1, peak, zc), Vector3(1, 0, 0), Vector2(0, 1), Vector2(d, 1), Vector2(d * 0.5, 1 - roof_h))
		_tri(st, Vector3(x0, wall_h, z0), Vector3(x0, wall_h, z1), Vector3(x0, peak, zc), Vector3(-1, 0, 0), Vector2(0, 1), Vector2(d, 1), Vector2(d * 0.5, 1 - roof_h))
	else:
		_tri(st, Vector3(x0, wall_h, z1), Vector3(x1, wall_h, z1), Vector3(xc, peak, z1), Vector3(0, 0, 1), Vector2(0, 1), Vector2(w, 1), Vector2(w * 0.5, 1 - roof_h))
		_tri(st, Vector3(x1, wall_h, z0), Vector3(x0, wall_h, z0), Vector3(xc, peak, z0), Vector3(0, 0, -1), Vector2(0, 1), Vector2(w, 1), Vector2(w * 0.5, 1 - roof_h))

	# 뒷벽(-x, -z 면): 카메라에서 안 보이지만 그림자와 가림에 필요
	_quad(st, Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(x0, wall_h, z1), Vector3(x0, wall_h, z0), Vector3(-1, 0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	_quad(st, Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3(x0, wall_h, z0), Vector3(x1, wall_h, z0), Vector3(0, 0, -1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	st.commit(mesh)
	return {"mesh": mesh, "ridge_x": ridge_x}


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
