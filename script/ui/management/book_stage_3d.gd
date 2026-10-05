class_name BookStage3D
extends Control
## 관리 창을 열고 닫을 때 보이는 3D 책. 정사영 카메라가 비스듬히 내려다보다가 펼침이 끝나면 정확히 위에서 내려다보는 각도로 돌아,
## 3D 쪽과 2D 펼침면(BookViews.Paper)이 같은 자리·같은 크기·같은 종이색으로 겹친다(그 위에서 3D 를 서서히 걷어 낸다).
## 월드 1칸 = 화면 100px. 제본선이 x = 0, 책등 방향이 z, 위가 y. 오른쪽 쪽은 x > 0 이고, 표지는 제본선에서 오른쪽으로 놓인 채 시작해
## 제본선을 축으로(z 축 회전) 왼쪽으로 넘어가 왼쪽 쪽(= 표지 안쪽 면지)이 된다. 포스트잇은 오른쪽 옆면에 3D 로 붙는다.

const PX := 100.0
const COVER_T := 0.05  # 표지 두께
const BACK_T := 0.05  # 뒷표지 두께
const PAGES_T := 0.16  # 쪽 더미 두께
const PITCH_START := 54.0  # 시작할 때 카메라가 내려다보는 각도(도). 90 = 바로 위
const PARCHMENT := Color("f5eddc")

var viewport: SubViewport
var camera: Camera3D
var book: Node3D
var cover_pivot: Node3D
var left_block: MeshInstance3D
var outer_mat: StandardMaterial3D
var inner_mat: StandardMaterial3D
var _target: Vector3 = Vector3.ZERO
var _vp_h: float = 648.0
var _half_w: float = 4.5
var _rise: float = 0.0
var _open: float = 0.0
var _art_viewport: SubViewport


# page_w_px/page_h_px: 2D 쪽 영역 크기, spine_px: 제본선·쪽 세로 가운데의 화면 좌표, flags: [{rect: Rect2(화면 좌표), color: Color}], vp_size: 화면 크기
func build(page_w_px: float,page_h_px: float,spine_px: Vector2,flags: Array,vp_size: Vector2,title_text: String,owner_text: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp_h = vp_size.y
	_half_w = page_w_px * 0.5 / PX
	var h := page_h_px / PX
	var pad := BookViews.COVER_PAD / PX
	var wc := _half_w + (BookViews.FORE_W + 4.0) / PX  # 표지 폭(제본선 → 바깥 끝)
	var z0 := -h * 0.5 - pad
	var z1 := h * 0.5 + (BookViews.BOTTOM_T + pad) / PX
	# 표지 바깥면 질감: 2D 표지와 같은 그림을 SubViewport 로 한 번 그려 쓴다
	_art_viewport = SubViewport.new()
	_art_viewport.size = Vector2i(roundi(wc * PX),roundi((z1 - z0) * PX))
	_art_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_art_viewport.transparent_bg = false
	var face := BookViews.CoverFace.new()
	face.title_text = title_text
	face.owner_text = owner_text
	face.size = Vector2(_art_viewport.size)
	_art_viewport.add_child(face)
	add_child(_art_viewport)
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
	camera.size = _vp_h / PX
	camera.near = 0.05
	camera.far = 80.0
	viewport.add_child(camera)
	# 화면 가운데에 놓일 월드 지점: 제본선이 spine_px 에 오도록
	_target = Vector3((vp_size.x * 0.5 - spine_px.x) / PX,0.0,(vp_size.y * 0.5 - spine_px.y) / PX)
	book = Node3D.new()
	viewport.add_child(book)
	var y_pages := BACK_T
	var y_pivot := BACK_T + PAGES_T
	var leather := _flat(Color("4a3223"))
	var leather_dark := _flat(Color("3d2a1d"))
	# 뒷표지(오른쪽 반)
	_box(Vector3(0.0,0.0,z0),Vector3(wc,BACK_T,z1),leather)
	# 쪽 더미: 윗면은 종이색 + 제본 홈 그림자, 옆면은 쪽이 쌓인 줄무늬
	var page_top := _flat(Color.WHITE)
	page_top.albedo_texture = _gutter_texture()
	var page_side := _flat(Color.WHITE)
	page_side.albedo_texture = _stripe_texture()
	page_side.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	page_side.uv1_scale = Vector3(1,6,1)
	var pages := MeshInstance3D.new()
	pages.mesh = _box_mesh(Vector3(0.0,y_pages,-h * 0.5),Vector3(_half_w,y_pages + PAGES_T,h * 0.5),[page_top,page_side,page_side])
	book.add_child(pages)
	# 책등(제본 띠)
	_box(Vector3(-0.02,0.0,z0),Vector3(0.02,y_pivot - 0.012,z1),leather_dark)  # 책등: 쪽 윗면 아래에 있어 위에서 보면 쪽에 가려진다
	# 왼쪽 받침: 표지가 넘어와 놓일 자리(넘어갈수록 올라온다)
	left_block = MeshInstance3D.new()
	left_block.mesh = _box_mesh(Vector3(-wc,0.0,z0),Vector3(0.0,y_pivot - COVER_T,z1),[leather,leather,leather])
	book.add_child(left_block)
	# 넘어가는 표지: 바깥면(가죽 + 금박 + 명패)과 안쪽 면(면지 = 왼쪽 쪽)
	cover_pivot = Node3D.new()
	cover_pivot.position = Vector3(0.0,y_pivot,0.0)
	book.add_child(cover_pivot)
	outer_mat = _flat(Color.WHITE)
	outer_mat.albedo_texture = _art_viewport.get_texture()
	inner_mat = _flat(Color.WHITE)
	inner_mat.albedo_texture = _inner_texture(Vector2i(roundi(wc * PX),roundi((z1 - z0) * PX)),page_h_px)
	var cover := MeshInstance3D.new()
	cover.mesh = _cover_mesh(wc,z0,z1,COVER_T,outer_mat,inner_mat,leather_dark)
	cover_pivot.add_child(cover)
	# 포스트잇: 2D 내비게이션 버튼의 화면 위치를 월드로 옮겨 쪽 오른쪽 옆면에 붙인다
	for f in flags:
		var r: Rect2 = f["rect"]
		var onto: float = float(f.get("onto",0.0))
		var m := _flat(f["color"])
		var y_top := y_pages + PAGES_T + 0.012
		var flag := MeshInstance3D.new()
		flag.mesh = _box_mesh(Vector3((r.position.x - spine_px.x) / PX,y_top,(r.position.y - spine_px.y) / PX),Vector3((r.end.x - spine_px.x) / PX,y_top + 0.025,(r.end.y - spine_px.y) / PX),[m,m,m])
		book.add_child(flag)
		if onto > 0.0:
			# 펼친 탭의 포스트잇: 쪽 위로 넘어온 연한 부분(2D 의 BookViews.Note 와 같은 자리)
			var light := _flat(Color(f["color"]).lerp(Color.WHITE,0.72))
			var part := MeshInstance3D.new()
			part.mesh = _box_mesh(Vector3((r.position.x - onto - spine_px.x) / PX,y_top,(r.position.y - spine_px.y) / PX),Vector3((r.position.x - spine_px.x) / PX,y_top + 0.025,(r.end.y - spine_px.y) / PX),[light,light,light])
			book.add_child(part)
	set_state(0.0,0.0)


# ---------------------------------------------------------------- 상태
# rise: 0 = 화면 아래(밖), 1 = 제자리. open: 0 = 닫힘, 1 = 활짝 펼침(카메라는 바로 위에서 내려다봄).
func set_state(rise: float,open: float) -> void:
	_rise = rise
	_open = open
	var th := PI * smoothstep(0.0,1.0,open)
	cover_pivot.rotation.z = th
	left_block.visible = th > 0.04
	left_block.scale.y = clampf(smoothstep(0.0,PI,th) * 1.6,0.02,1.0)
	# 표지 두 면의 밝기: 위로 세워질수록 옆으로 기울어 어두워지고, 바닥에 눕는 쪽은 종이색 그대로 돌아온다(조명 대신 밝기로 입체감을 낸다)
	outer_mat.albedo_color = _gray(lerpf(1.0,0.74,sin(minf(th,PI * 0.5))))
	inner_mat.albedo_color = _gray(lerpf(0.58,1.0,smoothstep(PI * 0.55,PI,th)))
	# 카메라: 시작은 비스듬히, 펼칠수록 바로 위로
	var pitch := deg_to_rad(lerpf(PITCH_START,90.0,smoothstep(0.0,1.0,open)))
	var dir := Vector3(0.0,sin(pitch),cos(pitch))
	camera.position = _target + dir * 30.0
	camera.look_at(_target,Vector3(0.0,0.0,-1.0))
	# 책: 올라오며(rise) 닫힌 상태에서는 가운데에 오도록 왼쪽 반만큼 치우쳤다가 펼치며 제자리로
	var drop := (1.0 - rise)
	var rise_ease := drop * drop
	book.position = Vector3(lerpf(-_half_w * 0.5,0.0,smoothstep(0.0,1.0,open)),0.0,rise_ease * (_vp_h / PX) * 0.9)


func _gray(v: float) -> Color:
	return Color(v,v,v,1.0)


# ---------------------------------------------------------------- 재료·모양
func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _box(lo: Vector3,hi: Vector3,mat: StandardMaterial3D) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = _box_mesh(lo,hi,[mat,mat,mat])
	book.add_child(inst)


# 면마다 다른 재료를 쓰는 상자. mats = [윗면, 아랫면, 옆면들]
func _box_mesh(lo: Vector3,hi: Vector3,mats: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var sx := hi.x - lo.x
	var sz := hi.z - lo.z
	# 윗면과 아랫면은 uv = (x 방향 0~1, z 방향 0~1)
	_quad(mesh,[Vector3(lo.x,hi.y,lo.z),Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,hi.y,hi.z),Vector3(lo.x,hi.y,hi.z)],[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],mats[0])
	_quad(mesh,[Vector3(lo.x,lo.y,lo.z),Vector3(hi.x,lo.y,lo.z),Vector3(hi.x,lo.y,hi.z),Vector3(lo.x,lo.y,hi.z)],[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],mats[1])
	# 옆면(+x, -z, +z, -x): uv 의 세로가 두께 방향
	var side: Array = [
		[Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,hi.y,hi.z),Vector3(hi.x,lo.y,hi.z),Vector3(hi.x,lo.y,lo.z)],
		[Vector3(lo.x,hi.y,lo.z),Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,lo.y,lo.z),Vector3(lo.x,lo.y,lo.z)],
		[Vector3(lo.x,hi.y,hi.z),Vector3(hi.x,hi.y,hi.z),Vector3(hi.x,lo.y,hi.z),Vector3(lo.x,lo.y,hi.z)],
		[Vector3(lo.x,hi.y,lo.z),Vector3(lo.x,hi.y,hi.z),Vector3(lo.x,lo.y,hi.z),Vector3(lo.x,lo.y,lo.z)],
	]
	for corners in side:
		_quad(mesh,corners,[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],mats[2])
	return mesh


# 표지: 제본선(x = 0)에서 오른쪽으로 wc, z0~z1. y 는 0 ~ t (바깥면이 위, 안쪽 면이 아래). 바깥면 uv 는 표지 그림 전체.
func _cover_mesh(wc: float,z0: float,z1: float,t: float,outer: StandardMaterial3D,inner: StandardMaterial3D,edge: StandardMaterial3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var uv := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	_quad(mesh,[Vector3(0,t,z0),Vector3(wc,t,z0),Vector3(wc,t,z1),Vector3(0,t,z1)],uv,outer)
	_quad(mesh,[Vector3(0,0,z0),Vector3(wc,0,z0),Vector3(wc,0,z1),Vector3(0,0,z1)],uv,inner)
	for corners in [
		[Vector3(wc,t,z0),Vector3(wc,t,z1),Vector3(wc,0,z1),Vector3(wc,0,z0)],
		[Vector3(0,t,z0),Vector3(wc,t,z0),Vector3(wc,0,z0),Vector3(0,0,z0)],
		[Vector3(0,t,z1),Vector3(wc,t,z1),Vector3(wc,0,z1),Vector3(0,0,z1)],
	]:
		_quad(mesh,corners,uv,edge)
	return mesh


func _quad(mesh: ArrayMesh,p: Array,uv: Array,mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for i in [0,1,2,0,2,3]:
		st.set_uv(uv[i])
		st.add_vertex(p[i])
	st.generate_normals()
	st.commit(mesh)


# 쪽 윗면·표지 안쪽 면 질감: 제본선(u = 0) 쪽이 어둡고 바깥으로 갈수록 종이색(2D 쪽의 홈 그림자와 같은 폭)
func _gutter_texture() -> Texture2D:
	var w := 256
	var img := Image.create(w,2,false,Image.FORMAT_RGBA8)
	for x in range(w):
		var u := float(x) / float(w - 1)
		var dist_px := u * _half_w * PX
		var k := clampf(1.0 - dist_px / 20.0,0.0,1.0)
		var shade := 1.0 - 0.20 * k * k
		var c := Color(PARCHMENT.r * shade,PARCHMENT.g * shade,PARCHMENT.b * shade,1.0)
		img.set_pixel(x,0,c)
		img.set_pixel(x,1,c)
	return ImageTexture.create_from_image(img)


func _stripe_texture() -> Texture2D:
	var img := Image.create(2,4,false,Image.FORMAT_RGBA8)
	var light := Color("fffaf0")
	var dark := Color("b9a582")
	for y in range(4):
		for x in range(2):
			img.set_pixel(x,y,light if y % 2 == 0 else dark)
	return ImageTexture.create_from_image(img)


# 표지 안쪽 면 질감: 가장자리는 가죽 테두리, 안쪽 쪽 영역(제본선 쪽부터 쪽 폭 × 쪽 높이)은 종이색 + 제본 홈 그림자.
# 넘어가 왼쪽에 놓였을 때 2D 왼쪽 쪽(BookViews.Paper)과 같은 자리·크기가 된다.
func _inner_texture(size_px: Vector2i,page_h_px: float) -> Texture2D:
	var img := Image.create(size_px.x,size_px.y,false,Image.FORMAT_RGBA8)
	img.fill(Color("5c4130"))
	var half_px := int(round(_half_w * PX))
	var top := int(round(BookViews.COVER_PAD))
	var bottom := mini(top + int(round(page_h_px)),size_px.y)
	for x in range(mini(half_px,size_px.x)):
		var k := clampf(1.0 - float(x) / 20.0,0.0,1.0)
		var shade := 1.0 - 0.20 * k * k
		var c := Color(PARCHMENT.r * shade,PARCHMENT.g * shade,PARCHMENT.b * shade,1.0)
		for y in range(top,bottom):
			img.set_pixel(x,y,c)
	return ImageTexture.create_from_image(img)
