class_name BookStage3D
extends Control
## 관리 창 = 3D 책. 메뉴의 실제 UI(MainPanel)는 SubViewport 안에서 계속 돌아가고, 그 화면이 3D 책의 두 쪽과 포스트잇의 질감으로 붙는다.
## 그래서 책을 꺼내 올리고, 표지를 넘겨 펼치고, 책장을 넘기는 내내 같은 책이고(2D 와 3D 를 갈아끼우는 순간이 없고),
## 넘어가는 쪽에는 살아 있는 화면이 실린다. 펼친 뒤(정지 상태)에는 정사영 카메라가 바로 위에서 내려다보며 화면 1:1 로 보이므로,
## 마우스 위치를 UI 화면 좌표로 바꿔 SubViewport 에 그대로 넘겨 준다(push_input).
## 월드 1칸 = 화면 100px. 제본선 x = 0, 책등 방향 z, 위가 y. 오른쪽 쪽은 x > 0, 표지는 제본선에서 오른쪽으로 놓인 채 시작해
## 제본선을 축으로(z 축 회전) 왼쪽으로 넘어가 왼쪽 쪽(= 표지 안쪽 면지)이 된다.

signal page_dragged(direction: int)  # +1 = 다음 탭(오른쪽 쪽을 왼쪽으로 끌어 넘김), -1 = 이전 탭
signal tab_picked(tab: int)

const PX := 100.0
const COVER_T := 0.05
const BACK_T := 0.05
const PAGES_T := 0.16
const PITCH_START := 54.0  # 시작할 때 카메라가 내려다보는 각도(도). 90 = 바로 위
const LEFT_FLAG_SHIFT := 40.0  # 책을 오른쪽으로 옮기는 정도(px)
const DRAG_DIST := 110.0  # 쪽을 이만큼 가로로 끌면 책장이 넘어간다(px)
const PAGE_MARGIN := 18.0  # UI 화면(MainPanel) 안에서 쪽이 시작하는 여백(= 둘레 여백)

var ui_viewport: SubViewport
var camera: Camera3D
var book: Node3D
var cover_pivot: Node3D
var left_block: MeshInstance3D
var outer_mat: StandardMaterial3D
var inner_page_mat: StandardMaterial3D
var right_page_mat: StandardMaterial3D
var nav_mat: StandardMaterial3D
var hint: Control
var left_flags: BookViews.LeftFlags
var _art_viewport: SubViewport
var _viewport: SubViewport
var _target: Vector3 = Vector3.ZERO
var _vp_h: float = 648.0
var _half_w: float = 4.5
var _page_w_px: float = 900.0
var _page_h_px: float = 541.0
var _ui_size: Vector2 = Vector2(1040,580)
var _offset: Vector2 = Vector2.ZERO  # UI 화면 좌표 → 모니터 화면 좌표(정지 상태)
var _spine_screen: Vector2 = Vector2.ZERO
var _rise: float = 0.0
var _open: float = 0.0
var _frozen: bool = false
var _drag_from: Vector2 = Vector2(-1.0,-1.0)  # 왼쪽 버튼을 누른 자리(UI 좌표), 끌기 중이 아니면 (-1,-1)
var _drag_used: bool = false  # 이번 누름에서 이미 책장을 넘겼는지


# ui: 메뉴 UI(MainPanel)가 들어 있는 SubViewport. 쪽(BookViews.Paper)은 그 안에서 둘레 여백 PAGE_MARGIN 만큼 안쪽에 놓인다.
func build(ui: SubViewport,screen_size: Vector2,title_text: String,owner_text: String) -> void:
	ui_viewport = ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp_h = screen_size.y
	_ui_size = Vector2(ui.size)
	var paper_size := _ui_size - Vector2(PAGE_MARGIN,PAGE_MARGIN) * 2.0
	_page_w_px = BookViews.page_width(paper_size)
	_page_h_px = paper_size.y - 3.0
	_half_w = _page_w_px * 0.5 / PX
	# 정지 상태에서 UI 화면 한가운데가 모니터 한가운데에 오도록 놓는다
	# 왼쪽 가장자리의 포스트잇(앞 탭)이 화면 밖으로 잘리지 않도록 책을 오른쪽으로 조금 옮긴다(오른쪽 포스트잇 줄은 UI 안에 이미 있다)
	_offset = (screen_size - _ui_size) * 0.5 + Vector2(LEFT_FLAG_SHIFT,0.0)
	var spine_ui := Vector2(PAGE_MARGIN,PAGE_MARGIN) + Vector2(_page_w_px * 0.5,_page_h_px * 0.5)
	_spine_screen = spine_ui + _offset
	_target = Vector3((screen_size.x * 0.5 - _spine_screen.x) / PX,0.0,(screen_size.y * 0.5 - _spine_screen.y) / PX)
	var h := _page_h_px / PX
	var pad := BookViews.COVER_PAD / PX
	var wc := _half_w + (BookViews.FORE_W + 4.0) / PX
	var pz0 := -h * 0.5
	var pz1 := h * 0.5
	var z0 := pz0 - pad
	var z1 := pz1 + (BookViews.BOTTOM_T + pad) / PX
	# 표지 바깥면 질감: 2D 로 그린 표지 그림을 한 번 그려 쓴다
	_art_viewport = SubViewport.new()
	_art_viewport.size = Vector2i(roundi(wc * PX),roundi((z1 - z0) * PX))
	_art_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
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
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(screen_size)
	container.add_child(_viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _vp_h / PX
	camera.near = 0.05
	camera.far = 80.0
	_viewport.add_child(camera)
	book = Node3D.new()
	_viewport.add_child(book)
	var y_pages := BACK_T
	var y_pivot := BACK_T + PAGES_T
	var leather := _flat(Color("4a3223"))
	var leather_dark := _flat(Color("3d2a1d"))
	var rim := _flat(Color("5c4130"))
	_box(Vector3(0.0,0.0,z0),Vector3(wc,BACK_T,z1),leather)  # 뒷표지(오른쪽 반)
	# 쪽 더미: 윗면 = 오른쪽 쪽의 UI 화면, 옆면 = 쪽이 쌓인 줄무늬
	right_page_mat = _ui_mat(Rect2(PAGE_MARGIN + _page_w_px * 0.5,PAGE_MARGIN,_page_w_px * 0.5,_page_h_px))
	var page_side := _flat(Color.WHITE)
	page_side.albedo_texture = _stripe_texture()
	page_side.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	page_side.uv1_scale = Vector3(1,6,1)
	var pages := MeshInstance3D.new()
	pages.mesh = _box_mesh(Vector3(0.0,y_pages,pz0),Vector3(_half_w,y_pages + PAGES_T,pz1),[right_page_mat,page_side,page_side])
	book.add_child(pages)
	_box(Vector3(-0.02,0.0,z0),Vector3(0.02,y_pivot - 0.012,z1),leather_dark)  # 책등
	left_block = MeshInstance3D.new()
	left_block.mesh = _box_mesh(Vector3(-wc,0.0,z0),Vector3(0.0,y_pivot - COVER_T,z1),[leather,leather,leather])
	book.add_child(left_block)
	# 넘어가는 표지: 바깥면(가죽·금박·명패), 안쪽 면(왼쪽 쪽 = UI 화면 + 가죽 테두리)
	cover_pivot = Node3D.new()
	cover_pivot.position = Vector3(0.0,y_pivot,0.0)
	book.add_child(cover_pivot)
	outer_mat = _flat(Color.WHITE)
	outer_mat.albedo_texture = _art_viewport.get_texture()
	inner_page_mat = _ui_mat(Rect2(PAGE_MARGIN,PAGE_MARGIN,_page_w_px * 0.5,_page_h_px))
	var cover := MeshInstance3D.new()
	cover.mesh = _cover_mesh(wc,z0,z1,COVER_T,pz0,pz1,_half_w,outer_mat,inner_page_mat,rim,leather_dark)
	cover_pivot.add_child(cover)
	# 포스트잇 줄(UI 화면의 오른쪽 내비게이션 부분, 투명 배경): 쪽 오른쪽 옆면에 붙는다
	var nav_x0 := PAGE_MARGIN + _page_w_px
	nav_mat = _ui_mat(Rect2(nav_x0,0.0,_ui_size.x - nav_x0,_ui_size.y))
	nav_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var nav := MeshInstance3D.new()
	var ny := y_pivot + 0.012
	nav.mesh = _quad_mesh(Vector3(_half_w,ny,(0.0 - spine_ui.y) / PX),Vector3(_half_w + (_ui_size.x - nav_x0) / PX,ny,(_ui_size.y - spine_ui.y) / PX),nav_mat)
	book.add_child(nav)
	# 책 아래 "ESC 닫기" 안내
	hint = BookViews.Hint.new()
	hint.position = Vector2(_spine_screen.x + _half_w * PX - 112.0,_spine_screen.y + _page_h_px * 0.5 + BookViews.BOTTOM_T + BookViews.COVER_PAD + 8.0)
	hint.visible = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	# 왼쪽 가장자리 포스트잇(앞 탭들): 화면 위에 얹는 2D. 펼침이 끝난 뒤에만 보인다
	left_flags = BookViews.LeftFlags.new()
	left_flags.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left_flags.visible = false
	left_flags.picked.connect(func(t: int) -> void: tab_picked.emit(t))
	add_child(left_flags)
	set_state(0.0,0.0)


# ---------------------------------------------------------------- 상태
# rise: 0 = 화면 아래(밖), 1 = 제자리. open: 0 = 닫힘, 1 = 활짝 펼침(카메라는 바로 위에서 내려다봄).
func set_state(rise: float,open: float) -> void:
	_rise = rise
	_open = open
	var th := PI * smoothstep(0.0,1.0,open)
	cover_pivot.rotation.z = th
	# 왼쪽 덩어리(펼친 책의 왼쪽 두께)는 표지가 거의 다 넘어가 내려앉을 때만 나타난다. 그 전에 보이면 표지 없이 어두운 판이 떠 있게 된다.
	left_block.visible = th > PI * 0.88
	left_block.scale.y = clampf(smoothstep(PI * 0.88,PI,th),0.02,1.0)
	outer_mat.albedo_color = _gray(lerpf(1.0,0.74,sin(minf(th,PI * 0.5))))
	inner_page_mat.albedo_color = _gray(lerpf(0.58,1.0,smoothstep(PI * 0.55,PI,th)))
	var pitch := deg_to_rad(lerpf(PITCH_START,90.0,smoothstep(0.0,1.0,open)))
	camera.position = _target + Vector3(0.0,sin(pitch),cos(pitch)) * 30.0
	camera.look_at(_target,Vector3(0.0,0.0,-1.0))
	var drop := clampf(1.0 - rise,0.0,1.0)
	book.position = Vector3(lerpf(-_half_w * 0.5,0.0,smoothstep(0.0,1.0,open)),0.0,drop * drop * (_vp_h / PX) * 1.9)
	hint.visible = at_rest()
	_sync_left_flags()


# 오른쪽 포스트잇(내비게이션 버튼) 자리 rect(UI 화면 좌표)를 제본선 기준으로 뒤집어 왼쪽 가장자리 자리로 바꿔 건넨다.
# list = [{tab, rect(UI 좌표, 오른쪽 자리), color, label}]
func set_left_flags(list: Array) -> void:
	var out: Array = []
	for it in list:
		var rs: Rect2 = Rect2((it["rect"] as Rect2).position + _offset,(it["rect"] as Rect2).size)
		var end_x := 2.0 * _spine_screen.x - rs.position.x
		out.append({"tab": it["tab"],"rect": Rect2(end_x - rs.size.x,rs.position.y,rs.size.x,rs.size.y),"color": it["color"],"label": it["label"]})
	left_flags.set_items(out)
	_sync_left_flags()


func _sync_left_flags() -> void:
	if left_flags == null: return
	left_flags.visible = _rise >= 0.999 and _open >= 0.999 and not left_flags.items.is_empty()
	left_flags.enabled = at_rest()


# 쪽 질감 영역 rect(UI 좌표)의 위아래를 책 월드 z 로 바꾼다(책장에 실려 가는 포스트잇의 자리)
func flag_z_range(ui_rect: Rect2) -> Vector2:
	var sy := _spine_screen.y - _offset.y
	return Vector2((ui_rect.position.y - sy) / PX,(ui_rect.end.y - sy) / PX)


func rise_value() -> float:
	return _rise


func open_value() -> float:
	return _open


func at_rest() -> bool:
	return _rise >= 0.999 and _open >= 0.999 and not _frozen


# ---------------------------------------------------------------- 입력: 화면 → UI 화면 좌표
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouse): return
	accept_event()
	if not at_rest(): return
	var p: Vector2 = (event as InputEventMouse).position - _offset
	# 책 바깥을 눌러도 닫히지 않는다(잘못 눌러서 꺼지는 것을 막는다). 닫기는 ESC·관리 메뉴 키.
	var inside := Rect2(Vector2.ZERO,_ui_size).has_point(p)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_from = p if inside else Vector2(-1.0,-1.0)
			_drag_used = false
		else:
			var was_used := _drag_used
			_drag_from = Vector2(-1.0,-1.0)
			_drag_used = false
			if was_used: return  # 책장을 넘긴 누름의 떼기는 UI 로 보내지 않는다(버튼이 눌린 것으로 처리되지 않게)
	elif event is InputEventMouseMotion and _drag_from.x >= 0.0 and not _drag_used and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		# 오른쪽 쪽에서 왼쪽으로 끌면 다음 탭, 왼쪽 쪽에서 오른쪽으로 끌면 이전 탭
		var d := p - _drag_from
		if absf(d.x) >= DRAG_DIST and absf(d.x) > absf(d.y) * 1.5:
			var spine_x := _spine_screen.x - _offset.x
			var dir := 0
			if _drag_from.x > spine_x and d.x < 0.0: dir = 1
			elif _drag_from.x < spine_x and d.x > 0.0: dir = -1
			if dir != 0:
				_drag_used = true
				var cancel := InputEventMouseButton.new()  # UI 쪽에서 누른 채로 남지 않도록 바깥에서 뗀 것으로 알린다
				cancel.button_index = MOUSE_BUTTON_LEFT
				cancel.pressed = false
				cancel.position = Vector2(-9999.0,-9999.0)
				cancel.global_position = cancel.position
				ui_viewport.push_input(cancel,true)
				page_dragged.emit(dir)
				return
	if not inside and not (event is InputEventMouseMotion): return
	var e: InputEventMouse = event.duplicate()
	e.position = p
	e.global_position = p
	ui_viewport.push_input(e,true)


# 펼친 뒤(정지 상태)에는 키 입력도 UI 화면으로 넘겨 준다(입력칸 글자 등). ESC 는 메뉴가 직접 처리한다.
func _input(event: InputEvent) -> void:
	if not visible or not at_rest() or not (event is InputEventKey): return
	if (event as InputEventKey).keycode == KEY_ESCAPE: return
	var focus := ui_viewport.gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit): return
	ui_viewport.push_input(event.duplicate(),false)
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 책장 넘김용: 지금 쪽 화면 사진, 쪽 고정
# 두 쪽(왼쪽 = 면지, 오른쪽)의 지금 UI 화면을 사진으로 뜬다. [왼쪽 텍스처, 오른쪽 텍스처]
func capture_halves() -> Array:
	var img := ui_viewport.get_texture().get_image()
	if img == null or img.is_empty(): return []
	var m := int(PAGE_MARGIN)
	var half := int(round(_page_w_px * 0.5))
	var ph := int(round(_page_h_px))
	var left := img.get_region(Rect2i(m,m,half,ph))
	var right := img.get_region(Rect2i(m + half,m,half,ph))
	return [ImageTexture.create_from_image(left),ImageTexture.create_from_image(right)]


# 넘기는 동안 쪽 질감을 사진으로 바꿔 두었다가(살아 있는 화면이 먼저 바뀌어도 보이지 않게) 끝나면 되돌린다.
func freeze_pages(left_tex: Texture2D,right_tex: Texture2D) -> void:
	_frozen = true
	for pair in [[inner_page_mat,left_tex],[right_page_mat,right_tex]]:
		var m: StandardMaterial3D = pair[0]
		m.albedo_texture = pair[1]
		m.uv1_scale = Vector3.ONE
		m.uv1_offset = Vector3.ZERO
	hint.visible = false
	_sync_left_flags()


func unfreeze_pages() -> void:
	_frozen = false
	_set_ui_region(inner_page_mat,Rect2(PAGE_MARGIN,PAGE_MARGIN,_page_w_px * 0.5,_page_h_px))
	_set_ui_region(right_page_mat,Rect2(PAGE_MARGIN + _page_w_px * 0.5,PAGE_MARGIN,_page_w_px * 0.5,_page_h_px))
	hint.visible = at_rest()
	_sync_left_flags()


func page_geometry() -> Dictionary:
	return {"page_w": _page_w_px,"page_h": _page_h_px,"spine": _spine_screen}


# ---------------------------------------------------------------- 재료·모양
func _gray(v: float) -> Color:
	return Color(v,v,v,1.0)


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# UI 화면(ViewportTexture) 중 region(UI 화면 픽셀)만 골라 입히는 재료
func _ui_mat(region: Rect2) -> StandardMaterial3D:
	var m := _flat(Color.WHITE)
	m.albedo_texture = ui_viewport.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_set_ui_region(m,region)
	return m


func _set_ui_region(m: StandardMaterial3D,region: Rect2) -> void:
	m.albedo_texture = ui_viewport.get_texture()
	m.uv1_scale = Vector3(region.size.x / _ui_size.x,region.size.y / _ui_size.y,1.0)
	m.uv1_offset = Vector3(region.position.x / _ui_size.x,region.position.y / _ui_size.y,0.0)


func _box(lo: Vector3,hi: Vector3,mat: StandardMaterial3D) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = _box_mesh(lo,hi,[mat,mat,mat])
	book.add_child(inst)


func _quad_mesh(lo: Vector3,hi: Vector3,mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_quad(mesh,[Vector3(lo.x,lo.y,lo.z),Vector3(hi.x,lo.y,lo.z),Vector3(hi.x,lo.y,hi.z),Vector3(lo.x,lo.y,hi.z)],[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],mat)
	return mesh


# 면마다 다른 재료를 쓰는 상자. mats = [윗면, 아랫면, 옆면들]
func _box_mesh(lo: Vector3,hi: Vector3,mats: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_quad(mesh,[Vector3(lo.x,hi.y,lo.z),Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,hi.y,hi.z),Vector3(lo.x,hi.y,hi.z)],[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],mats[0])
	_quad(mesh,[Vector3(lo.x,lo.y,lo.z),Vector3(hi.x,lo.y,lo.z),Vector3(hi.x,lo.y,hi.z),Vector3(lo.x,lo.y,hi.z)],[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],mats[1])
	var side: Array = [
		[Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,hi.y,hi.z),Vector3(hi.x,lo.y,hi.z),Vector3(hi.x,lo.y,lo.z)],
		[Vector3(lo.x,hi.y,lo.z),Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,lo.y,lo.z),Vector3(lo.x,lo.y,lo.z)],
		[Vector3(lo.x,hi.y,hi.z),Vector3(hi.x,hi.y,hi.z),Vector3(hi.x,lo.y,hi.z),Vector3(lo.x,lo.y,hi.z)],
		[Vector3(lo.x,hi.y,lo.z),Vector3(lo.x,hi.y,hi.z),Vector3(lo.x,lo.y,hi.z),Vector3(lo.x,lo.y,lo.z)],
	]
	for corners in side:
		_quad(mesh,corners,[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],mats[2])
	return mesh


# 표지: 제본선(x = 0)에서 오른쪽으로 wc. y 는 0 ~ t (바깥면이 위, 안쪽 면이 아래). 안쪽 면은 쪽(UI 화면)과 가죽 테두리로 나뉜다.
func _cover_mesh(wc: float,z0: float,z1: float,t: float,pz0: float,pz1: float,half: float,outer: StandardMaterial3D,inner_page: StandardMaterial3D,rim: StandardMaterial3D,edge: StandardMaterial3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var uv := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	_quad(mesh,[Vector3(0,t,z0),Vector3(wc,t,z0),Vector3(wc,t,z1),Vector3(0,t,z1)],uv,outer)
	# 안쪽 면의 쪽: 제본선에서 멀수록 UI 화면의 왼쪽(넘어간 뒤 왼쪽 끝)이므로 가로 uv 를 뒤집는다
	_quad(mesh,[Vector3(0,0,pz0),Vector3(half,0,pz0),Vector3(half,0,pz1),Vector3(0,0,pz1)],[Vector2(1,0),Vector2(0,0),Vector2(0,1),Vector2(1,1)],inner_page)
	for r in [
		[Vector3(half,0,z0),Vector3(wc,0,z0),Vector3(wc,0,z1),Vector3(half,0,z1)],
		[Vector3(0,0,z0),Vector3(half,0,z0),Vector3(half,0,pz0),Vector3(0,0,pz0)],
		[Vector3(0,0,pz1),Vector3(half,0,pz1),Vector3(half,0,z1),Vector3(0,0,z1)],
	]:
		_quad(mesh,r,uv,rim)
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


func _stripe_texture() -> Texture2D:
	var img := Image.create(2,4,false,Image.FORMAT_RGBA8)
	var light := Color("fffaf0")
	var dark := Color("b9a582")
	for y in range(4):
		for x in range(2):
			img.set_pixel(x,y,light if y % 2 == 0 else dark)
	return ImageTexture.create_from_image(img)
