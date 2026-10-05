class_name BookFlip3D
extends Control
## 탭을 옮길 때의 3D 책장 넘김. 정사영 카메라는 2D 펼침면과 같은 자리·크기로 시작하고(첫 장면 = 옛 화면 그대로), 넘기는 동안에도 기울지 않는다(끝 장면 = 새 화면 그대로).
## 바닥에는 넘어가지 않는 쪽의 사진 두 장(옛 화면의 한 쪽, 새 화면의 한 쪽)이 깔리고, 넘어가는 한 장은 앞면(옛 화면의 그 쪽)과 뒷면(새 화면의 반대쪽)을 가진다.
## 한 장은 제본선을 축으로 살짝만 휘며 넘어가고(CURL 로 휨 조절), 밑에는 그림자가 진다. 앞으로 가면(뒤쪽 탭) 오른쪽 쪽이 왼쪽으로, 뒤로 가면(앞쪽 탭) 왼쪽 쪽이 오른쪽으로 넘어간다.
## 탭이 멀수록 종이를 더 넘긴다: 건너뛰는 탭 수만큼(최대 MAX_LEAVES) 겹쳐 있는 종이가 차례로 넘어가고, 맨 위 한 장의 앞면만 옛 화면, 맨 마지막 한 장의 뒷면만 새 화면이며 나머지는 빈 종이다.

const PX := 100.0
const SEGMENTS := 14
const CURL := 0.22  # 자유 모서리가 뒤처지는 정도(라디안). 0 = 판판하게, 값이 클수록 휜다
const TILT_DEG := 0.0  # 넘기는 한가운데에서 카메라가 기우는 정도(도). 0 = 늘 바로 위에서 본다
const SKIN := 0.006  # 앞면·뒷면 사이 두께의 절반

const LEAF_TIME := 0.55  # 종이 한 장이 넘어가는 시간(초)
const LEAF_STAGGER := 0.09  # 다음 장이 넘어가기 시작하기까지의 간격(초)
const MAX_LEAVES := 6
const GAP := 0.012  # 겹친 종이 사이 높이
const PARCHMENT := Color("f5eddc")

var viewport: SubViewport
var camera: Camera3D
var leaves: Array = []  # [{node, front, back, shadow, shadow_mat}]
var forward: bool = true
var duration: float = LEAF_TIME
var _half: float = 4.5
var _z0: float = 0.0
var _z1: float = 0.0
var _target: Vector3 = Vector3.ZERO


# count: 건너뛰는 탭 수(= 넘길 종이 수)
func build(page_w_px: float,page_h_px: float,spine_px: Vector2,vp_size: Vector2,old_left: Texture2D,old_right: Texture2D,new_left: Texture2D,new_right: Texture2D,is_forward: bool,count: int = 1) -> void:
	forward = is_forward
	var n := clampi(count,1,MAX_LEAVES)
	duration = LEAF_TIME + LEAF_STAGGER * float(n - 1)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_half = page_w_px * 0.5 / PX
	_z0 = -page_h_px * 0.5 / PX
	_z1 = page_h_px * 0.5 / PX
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(vp_size)
	container.add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = vp_size.y / PX
	camera.near = 0.05
	camera.far = 80.0
	viewport.add_child(camera)
	_target = Vector3((vp_size.x * 0.5 - spine_px.x) / PX,0.0,(vp_size.y * 0.5 - spine_px.y) / PX)
	# 바닥의 두 쪽: 넘어가지 않는 쪽의 옛 화면 + 넘어간 뒤 드러나는 쪽의 새 화면
	var base_left: Texture2D = old_left if forward else new_left
	var base_right: Texture2D = new_right if forward else old_right
	_plane(Vector3(-_half,-0.03,_z0),Vector3(0.0,-0.03,_z1),base_left)
	_plane(Vector3(0.0,-0.03,_z0),Vector3(_half,-0.03,_z1),base_right)
	var front_tex: Texture2D = old_right if forward else old_left
	var back_tex: Texture2D = new_left if forward else new_right
	for i in range(n):
		var info := {}
		info["front"] = _tex_mat(front_tex) if i == 0 else _blank_mat()
		info["back"] = _tex_mat(back_tex) if i == n - 1 else _blank_mat()
		var inst := MeshInstance3D.new()
		viewport.add_child(inst)
		if not forward:
			inst.scale.x = -1.0  # 왼쪽 쪽에서 오른쪽으로: 거울상으로 뒤집어 같은 마디 계산을 쓴다
		info["node"] = inst
		# 그림자(이 종이 밑)
		var sm := QuadMesh.new()
		sm.orientation = PlaneMesh.FACE_Y
		sm.size = Vector2(1.0,_z1 - _z0)
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(0.12,0.08,0.04,0.0)
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var sh := MeshInstance3D.new()
		sh.mesh = sm
		sh.material_override = smat
		viewport.add_child(sh)
		info["shadow"] = sh
		info["shadow_mat"] = smat
		leaves.append(info)
	set_progress(0.0)


func _blank_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = PARCHMENT
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _tex_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _plane(lo: Vector3,hi: Vector3,tex: Texture2D) -> void:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_tex_mat(tex))
	var pts := [Vector3(lo.x,lo.y,lo.z),Vector3(hi.x,lo.y,lo.z),Vector3(hi.x,lo.y,hi.z),Vector3(lo.x,lo.y,hi.z)]
	var uv := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	for i in [0,1,2,0,2,3]:
		st.set_uv(uv[i])
		st.add_vertex(pts[i])
	st.commit(mesh)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	viewport.add_child(inst)


# p: 0 = 넘기기 전(옛 화면), 1 = 다 넘김(새 화면). 종이마다 LEAF_STAGGER 씩 늦게 시작한다.
func set_progress(p: float) -> void:
	var n := leaves.size()
	var t := clampf(p,0.0,1.0) * duration
	for i in range(n):
		var info: Dictionary = leaves[i]
		var pi_ := clampf((t - LEAF_STAGGER * float(i)) / LEAF_TIME,0.0,1.0)
		var theta := PI * smoothstep(0.0,1.0,pi_)
		_rebuild_leaf(info,theta)
		var s := sin(theta)
		(info["front"] as StandardMaterial3D).albedo_color = _gray(lerpf(1.0,0.8,minf(s * 1.4,1.0)) if theta < PI * 0.5 else 0.8, i == 0)
		(info["back"] as StandardMaterial3D).albedo_color = _gray(lerpf(0.62,1.0,smoothstep(PI * 0.5,PI,theta)), i == n - 1)
		# 쌓인 높이: 처음엔 먼저 넘어갈 종이가 맨 위, 넘어간 뒤엔 나중에 넘어간 종이가 맨 위
		var y_start := float(n - 1 - i) * GAP + 0.01
		var y_end := float(i) * GAP + 0.01
		(info["node"] as Node3D).position.y = lerpf(y_start,y_end,smoothstep(0.0,1.0,pi_))
		# 그림자
		var tip := absf(_tip_x(theta))
		var under_right := (forward and theta < PI * 0.5) or (not forward and theta >= PI * 0.5)
		var width := maxf(tip,0.001)
		var sh: MeshInstance3D = info["shadow"]
		sh.scale = Vector3(width,1.0,1.0)
		sh.position = Vector3((width * 0.5) * (1.0 if under_right else -1.0),-0.02,(_z0 + _z1) * 0.5)
		(info["shadow_mat"] as StandardMaterial3D).albedo_color = Color(0.12,0.08,0.04,0.3 * s * (1.0 - 0.4 * s) / sqrt(float(n)))
	# 카메라: 한가운데에서 가장 기울고 양 끝에서는 정확히 위
	var pitch := deg_to_rad(90.0 - TILT_DEG * sin(PI * clampf(p,0.0,1.0)))
	camera.position = _target + Vector3(0.0,sin(pitch),cos(pitch)) * 30.0
	camera.look_at(_target,Vector3(0.0,0.0,-1.0))


# 사진이 있는 면(textured)만 밝기를 줄이고, 빈 종이는 종이색 그대로 밝기만 곱한다(두 경우 모두 곱셈이라 같은 식).
func _gray(v: float,textured: bool) -> Color:
	return Color(v,v,v,1.0) if textured else Color(PARCHMENT.r * v,PARCHMENT.g * v,PARCHMENT.b * v,1.0)


# 마디마다 각도를 달리해 휜 한 장의 단면(x, y). 자유 모서리일수록 theta 보다 뒤처진다.
func _profile(theta: float) -> Array:
	var seg := _half / float(SEGMENTS)
	var pts: Array = [Vector2(0.0,0.0)]
	var angles: Array = []
	for j in range(SEGMENTS):
		var a := theta - CURL * sin(theta) * (float(j) + 0.5) / float(SEGMENTS)
		angles.append(a)
		var last: Vector2 = pts[pts.size() - 1]
		pts.append(last + Vector2(cos(a),sin(a)) * seg)
	return [pts,angles]


func _tip_x(theta: float) -> float:
	var pr := _profile(theta)
	return (pr[0] as Array)[SEGMENTS].x * (1.0 if forward else -1.0)


func _rebuild_leaf(info: Dictionary,theta: float) -> void:
	var pr := _profile(theta)
	var pts: Array = pr[0]
	var angles: Array = pr[1]
	var mesh := ArrayMesh.new()
	for face in [0,1]:  # 0 = 앞면, 1 = 뒷면
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(info["front"] if face == 0 else info["back"])
		var sign_n := 1.0 if face == 0 else -1.0
		for j in range(SEGMENTS):
			var corners: Array = []
			for k in [j,j + 1]:
				var a: float = angles[mini(k,SEGMENTS - 1)]
				var nrm := Vector2(-sin(a),cos(a)) * SKIN * sign_n
				var q: Vector2 = (pts[k] as Vector2) + nrm
				corners.append(q)
			var u0 := float(j) / float(SEGMENTS)
			var u1 := float(j + 1) / float(SEGMENTS)
			var flip_u: bool = (face == 0) != forward
			if flip_u:
				u0 = 1.0 - u0
				u1 = 1.0 - u1
			var qa: Vector2 = corners[0]
			var qb: Vector2 = corners[1]
			var v := [Vector3(qa.x,qa.y,_z0),Vector3(qb.x,qb.y,_z0),Vector3(qb.x,qb.y,_z1),Vector3(qa.x,qa.y,_z1)]
			var uv := [Vector2(u0,0),Vector2(u1,0),Vector2(u1,1),Vector2(u0,1)]
			for i in [0,1,2,0,2,3]:
				st.set_uv(uv[i])
				st.add_vertex(v[i])
		st.commit(mesh)
	(info["node"] as MeshInstance3D).mesh = mesh
