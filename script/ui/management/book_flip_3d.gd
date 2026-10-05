class_name BookFlip3D
extends Control
## 탭을 옮길 때의 3D 책장 넘김. 정사영 카메라는 2D 펼침면과 같은 자리·크기로 시작하고(첫 장면 = 옛 화면 그대로), 넘기는 동안 살짝 기울었다가 끝나면 다시 바로 위로 돌아온다(끝 장면 = 새 화면 그대로).
## 바닥에는 넘어가지 않는 쪽의 사진 두 장(옛 화면의 한 쪽, 새 화면의 한 쪽)이 깔리고, 넘어가는 한 장은 앞면(옛 화면의 그 쪽)과 뒷면(새 화면의 반대쪽)을 가진다.
## 한 장은 여러 마디로 나뉘어 자유 모서리가 뒤처지며 휘어 오르고, 밑에는 그림자가 진다. 앞으로 가면(뒤쪽 탭) 오른쪽 쪽이 왼쪽으로, 뒤로 가면(앞쪽 탭) 왼쪽 쪽이 오른쪽으로 넘어간다.

const PX := 100.0
const SEGMENTS := 14
const CURL := 0.6  # 자유 모서리가 뒤처지는 정도(라디안)
const TILT_DEG := 22.0  # 넘기는 한가운데에서 카메라가 기우는 정도(도)
const SKIN := 0.006  # 앞면·뒷면 사이 두께의 절반

var viewport: SubViewport
var camera: Camera3D
var leaf: MeshInstance3D
var front_mat: StandardMaterial3D
var back_mat: StandardMaterial3D
var shadow: MeshInstance3D
var shadow_mat: StandardMaterial3D
var forward: bool = true
var _half: float = 4.5
var _z0: float = 0.0
var _z1: float = 0.0
var _target: Vector3 = Vector3.ZERO


func build(page_w_px: float,page_h_px: float,spine_px: Vector2,vp_size: Vector2,old_left: Texture2D,old_right: Texture2D,new_left: Texture2D,new_right: Texture2D,is_forward: bool) -> void:
	forward = is_forward
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
	# 그림자(넘어가는 한 장 밑)
	shadow_mat = StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.12,0.08,0.04,0.0)
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow = MeshInstance3D.new()
	var sm := QuadMesh.new()
	sm.orientation = PlaneMesh.FACE_Y
	sm.size = Vector2(1.0,_z1 - _z0)
	shadow.mesh = sm
	shadow.material_override = shadow_mat
	viewport.add_child(shadow)
	# 넘어가는 한 장
	var front_tex: Texture2D = old_right if forward else old_left
	var back_tex: Texture2D = new_left if forward else new_right
	front_mat = _tex_mat(front_tex)
	back_mat = _tex_mat(back_tex)
	leaf = MeshInstance3D.new()
	viewport.add_child(leaf)
	if not forward:
		leaf.scale.x = -1.0  # 왼쪽 쪽에서 오른쪽으로: 거울상으로 뒤집어 같은 마디 계산을 쓴다
	set_progress(0.0)


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


# p: 0 = 넘기기 전(옛 화면), 1 = 다 넘김(새 화면)
func set_progress(p: float) -> void:
	var theta := PI * smoothstep(0.0,1.0,p)
	_rebuild_leaf(theta)
	var s := sin(theta)
	front_mat.albedo_color = _gray(lerpf(1.0,0.8,minf(s * 1.4,1.0)) if theta < PI * 0.5 else 0.8)
	back_mat.albedo_color = _gray(lerpf(0.62,1.0,smoothstep(PI * 0.5,PI,theta)))
	# 카메라: 한가운데에서 가장 기울고 양 끝에서는 정확히 위
	var pitch := deg_to_rad(90.0 - TILT_DEG * sin(PI * clampf(p,0.0,1.0)))
	camera.position = _target + Vector3(0.0,sin(pitch),cos(pitch)) * 30.0
	camera.look_at(_target,Vector3(0.0,0.0,-1.0))
	# 그림자: 한 장이 일어서며 바닥에 드리우는 길쭉한 그림. 한 장의 자유 모서리 아래까지
	var tip := absf(_tip_x(theta))
	var under_right := (forward and theta < PI * 0.5) or (not forward and theta >= PI * 0.5)
	var width := maxf(tip,0.001)
	shadow.scale = Vector3(width,1.0,1.0)
	shadow.position = Vector3((width * 0.5) * (1.0 if under_right else -1.0),-0.02,(_z0 + _z1) * 0.5)
	shadow_mat.albedo_color = Color(0.12,0.08,0.04,0.34 * s * (1.0 - 0.4 * s))


func _gray(v: float) -> Color:
	return Color(v,v,v,1.0)


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


func _rebuild_leaf(theta: float) -> void:
	var pr := _profile(theta)
	var pts: Array = pr[0]
	var angles: Array = pr[1]
	var mesh := ArrayMesh.new()
	for face in [0,1]:  # 0 = 앞면, 1 = 뒷면
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(front_mat if face == 0 else back_mat)
		var sign_n := 1.0 if face == 0 else -1.0
		for j in range(SEGMENTS):
			var corners: Array = []
			for k in [j,j + 1]:
				var a: float = angles[mini(k,SEGMENTS - 1)]
				var n := Vector2(-sin(a),cos(a)) * SKIN * sign_n
				var q: Vector2 = (pts[k] as Vector2) + n
				corners.append(q)
			var u0 := float(j) / float(SEGMENTS)
			var u1 := float(j + 1) / float(SEGMENTS)
			# 앞으로 가는 한 장의 앞면은 왼→오른 순서로 그림이 펼쳐지고, 뒷면은 반대(넘어간 뒤 거울상이 되므로)
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
	leaf.mesh = mesh
