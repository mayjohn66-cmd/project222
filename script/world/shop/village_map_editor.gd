extends Node2D

## F12 editor for the exterior village. Positions and painted tiles are saved
## separately from the player's ordinary game save.
const GROUPS := [
	"NearbyHouses","VillageExtraHouses","VillageBlacksmith","VillageToolShop",
	"VillageBuildings","VillageDecor","VillageGathering","DungeonRoadside","DungeonWall"
]
const MODE_NAMES := ["이동","돌길","잔디","자동","타일 추가","타일 삭제","원정 위치"]
const CAMERA_PAN_SPEED := 650.0
const OBJECT_CATALOG := [
	["붉은 지붕 집","NearbyHouses/RedRoofHouse"],
	["붉은 지붕 집 · 90°","NearbyHouses/RedRoofHouse","quarter_turn"],
	["작은 집","VillageExtraHouses/EastCottage"],
	["작은 집 · 파란 지붕","VillageExtraHouses/EastCottage","blue"],
	["작은 집 · 적갈 지붕","VillageExtraHouses/EastCottage","terracotta"],
	["작은 집 · 황토 지붕","VillageExtraHouses/EastCottage","ochre"],
	["작은 집 · 180°","VillageExtraHouses/EastCottage","front"],
	["작은 집 · 180° 파란 지붕","VillageExtraHouses/EastCottage","front_blue"],
	["작은 집 · 180° 적갈 지붕","VillageExtraHouses/EastCottage","front_terracotta"],
	["작은 집 · 180° 황토 지붕","VillageExtraHouses/EastCottage","front_ochre"],
	["대장간","VillageBlacksmith/Smithy"],
	["도구점","VillageToolShop/ToolShop"],
	["빵집","VillageBuildings/VillageBakery"],
	["마구간","VillageBuildings/VillageStable"],
	["나무","VillageDecor/OrchardTree1"],
	["우물","VillageDecor/VillageWell"],
	["장터","VillageDecor/MarketStall"],
	["생선 노점 · 장터 방향","VillageDecor/MarketStall","fish_front"],
	["생선 노점 · 반대 방향","VillageDecor/MarketStall","fish_rear"],
	["빵 노점 · 장터 방향","VillageDecor/MarketStall","bakery_front"],
	["빵 노점 · 반대 방향","VillageDecor/MarketStall","bakery_rear"],
	["천 노점 · 장터 방향","VillageDecor/MarketStall","cloth_front"],
	["천 노점 · 반대 방향","VillageDecor/MarketStall","cloth_rear"],
	["낮은 담장","VillageDecor/GardenWall1"],
	["약초 가판대","VillageDecor/PlazaHerbStall"],
	["보급 수레","VillageDecor/PlazaSupplyCart"],
	["상자","VillageDecor/PlazaCrates"],
	["게시판","VillageGathering/VillageNoticeboard"],
	["벤치","VillageGathering/WellBench"],
	["가로등","VillageGathering/MarketLantern"],
	["꽃 덤불","VillageGathering/EastFlowerBed"],
	["표지판","DungeonRoadside/ExitSign"],
	["나무 울타리","DungeonRoadside/WestFence"]
]

@onready var terrain: StoreExterior = $"../StoreExterior"
@onready var camera: Camera2D = $"../Actors/Player/Camera2D"

var active := false
var mode := 0
var selected: StaticBody2D
var hover_cell := Vector2i.ZERO
var dragging := false
var painting := false
var panning := false
var placing_object := false
var stroke_changed := false
var drag_start := Vector2i.ZERO
var stroke_snapshot: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var image_cache: Dictionary = {}
var previous_paused := false
var previous_grid := false
var previous_camera_position := Vector2.ZERO
var previous_camera_zoom := Vector2.ONE
var previous_camera_process_mode := Node.PROCESS_MODE_INHERIT
var panel: PanelContainer
var selection_label: Label
var object_picker: OptionButton
var status_label: Label
var mode_buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_as_relative = false
	z_index = 95
	_make_panel()
	set_process_unhandled_input(true)

func _make_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MapEditorUI"
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	panel = PanelContainer.new()
	panel.name = "EditorPanel"
	panel.theme = preload("res://art/ui/pixel_theme/pixel_ui_theme.tres")
	panel.position = Vector2(16,16)
	panel.custom_minimum_size = Vector2(370,0)
	panel.visible = false
	layer.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",5)
	panel.add_child(content)
	var title := Label.new()
	title.text = "마을 지도 편집  ·  F12 닫기"
	content.add_child(title)
	var modes := HBoxContainer.new()
	content.add_child(modes)
	for index in range(MODE_NAMES.size()):
		if index == 4:
			modes = HBoxContainer.new()
			content.add_child(modes)
		var button := Button.new()
		button.text = MODE_NAMES[index]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(80,36)
		button.pressed.connect(Callable(self,"_set_mode").bind(index))
		modes.add_child(button)
		mode_buttons.append(button)
	selection_label = Label.new()
	selection_label.text = "오브젝트를 클릭해서 선택하세요."
	content.add_child(selection_label)
	var object_row := HBoxContainer.new()
	content.add_child(object_row)
	object_picker = OptionButton.new()
	object_picker.custom_minimum_size = Vector2(175,34)
	for entry in OBJECT_CATALOG:
		object_picker.add_item(entry[0])
	object_picker.select(0)
	object_row.add_child(object_picker)
	var add_button := Button.new()
	add_button.text = "오브젝트 추가"
	add_button.pressed.connect(_start_placing_object)
	object_row.add_child(add_button)
	var remove_button := Button.new()
	remove_button.text = "선택 삭제"
	remove_button.pressed.connect(_remove_selected)
	object_row.add_child(remove_button)
	var help := Label.new()
	help.text = "빈 가장자리 타일 클릭·끌기: 확장 / 기존 타일: 삭제\n오브젝트 추가: 종류 선택 후 타일 클릭 / Delete: 선택 삭제\n원정 위치: 출발할 돌바닥 타일 클릭 (주변 5×5칸)\nWASD·방향키 / 가운데·우클릭 끌기: 화면 이동\n1~7: 도구 / Ctrl+Z: 취소 / Backspace: 원위치"
	content.add_child(help)
	var save_button := Button.new()
	save_button.text = "배치 저장  Ctrl+S"
	save_button.pressed.connect(_save_layout)
	content.add_child(save_button)
	status_label = Label.new()
	status_label.text = "변경 내용 자동 저장"
	content.add_child(status_label)
	_set_mode(0)

func _set_mode(value: int) -> void:
	if painting: _finish_paint()
	mode = value
	placing_object = false
	for index in range(mode_buttons.size()):
		mode_buttons[index].button_pressed = index == value
	if status_label != null:
		status_label.text = ["오브젝트를 타일에 맞춰 옮깁니다.","돌길을 칠합니다.","잔디를 칠합니다.","기본 타일로 되돌립니다.","지도 가장자리의 빈 타일을 추가합니다.","기존 지도 타일을 지웁니다.","원정 출발 지점을 돌바닥 타일로 지정합니다."][value]

func _input(event: InputEvent) -> void:
	if active and event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			panning = not panel.get_global_rect().has_point(event.position)
		else:
			panning = false
		get_viewport().set_input_as_handled()
		return
	if active and panning and event is InputEventMouseMotion:
		_pan_camera(-event.relative/camera.zoom.x)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F12:
		set_editor_active(not active)
		get_viewport().set_input_as_handled()
		return
	if not active: return
	if event.keycode == KEY_ESCAPE:
		set_editor_active(false)
	elif event.ctrl_pressed and event.keycode == KEY_S:
		_save_layout()
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		_undo()
	elif event.keycode == KEY_BACKSPACE:
		_reset_selected()
	elif event.keycode == KEY_DELETE:
		_remove_selected()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_7:
		_set_mode(event.keycode-KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active or Input.is_key_pressed(KEY_CTRL): return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y += 1
	if direction != Vector2.ZERO:
		_pan_camera(direction.normalized()*CAMERA_PAN_SPEED*delta/camera.zoom.x)

func _pan_camera(offset: Vector2) -> void:
	camera.global_position += offset
	camera.force_update_scroll()

func set_editor_active(enabled: bool) -> void:
	if active == enabled: return
	active = enabled
	if enabled:
		previous_paused = get_tree().paused
		previous_grid = terrain.show_tile_grid
		previous_camera_position = camera.position
		previous_camera_zoom = camera.zoom
		previous_camera_process_mode = camera.process_mode
		camera.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
		camera.zoom = Vector2(0.30,0.30)
		camera.global_position = terrain.to_global(terrain.get_village_map_center_local())
		terrain.show_tile_grid = true
		panel.visible = true
		status_label.text = "편집 중 · 자동 저장"
	else:
		if dragging: _finish_drag()
		if painting: _finish_paint()
		panning = false
		selected = null
		placing_object = false
		panel.visible = false
		terrain.show_tile_grid = previous_grid
		camera.position = previous_camera_position
		camera.zoom = previous_camera_zoom
		camera.process_mode = previous_camera_process_mode
		get_tree().paused = previous_paused
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(1.0/1.12)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_stroke()
			else:
				if dragging: _finish_drag()
				if painting: _finish_paint()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		hover_cell = _mouse_cell()
		if dragging and is_instance_valid(selected) and terrain.is_exterior_cell(hover_cell):
			selected.global_position = terrain.to_global(terrain.grid_to_local(hover_cell))
		elif painting:
			_paint_cell()
		queue_redraw()
		get_viewport().set_input_as_handled()

func _zoom(factor: float) -> void:
	var amount := clampf(camera.zoom.x*factor,0.30,1.50)
	camera.zoom = Vector2(amount,amount)

func _mouse_cell() -> Vector2i:
	var pos := terrain.to_local(get_global_mouse_position())
	return Vector2i(roundi(pos.x/terrain.tile_width+pos.y/terrain.tile_height),roundi(pos.y/terrain.tile_height-pos.x/terrain.tile_width))

func _begin_stroke() -> void:
	hover_cell = _mouse_cell()
	if mode == 4:
		if not terrain.can_add_layout_cell(hover_cell): return
	elif not terrain.is_exterior_cell(hover_cell):
		return
	if placing_object:
		_place_object(hover_cell)
		return
	if mode == 6:
		if terrain.get_layout_tile(hover_cell) != "road":
			status_label.text = "돌바닥 타일을 선택하세요."
			return
		_remember(terrain.get_village_layout_snapshot())
		terrain.set_layout_cell("ExpeditionDeparture",hover_cell)
		selection_label.text = "원정 출발 위치 · "+str(hover_cell)
		_save_layout()
		queue_redraw()
		return
	if mode == 0:
		selected = _pick_object(get_global_mouse_position())
		if is_instance_valid(selected):
			drag_start = _cell_at(selected.global_position)
			dragging = true
			selection_label.text = selected.get_parent().name+"/"+selected.name+"  "+str(drag_start)
		else:
			selection_label.text = "오브젝트를 클릭해서 선택하세요."
	else:
		stroke_snapshot = terrain.get_village_layout_snapshot()
		stroke_changed = false
		painting = true
		_paint_cell()
	queue_redraw()

func _finish_drag() -> void:
	dragging = false
	if not is_instance_valid(selected): return
	var target := _cell_at(selected.global_position)
	if not terrain.is_exterior_cell(target):
		target = drag_start
	if target != drag_start:
		_remember(terrain.get_village_layout_snapshot())
		terrain.set_layout_cell(selected.get_parent().name+"/"+selected.name,target)
		selected = null
		terrain.refresh_village_layout()
		_save_layout()
	else:
		selected.global_position = terrain.to_global(terrain.grid_to_local(drag_start))
	queue_redraw()

func _paint_cell() -> void:
	if mode == 4 or mode == 5:
		if terrain.set_layout_cell_present(hover_cell,mode == 4): stroke_changed = true
		return
	if not terrain.is_exterior_cell(hover_cell): return
	var kind: String = ["","road","grass",""][mode]
	if terrain.get_layout_tile(hover_cell) == kind: return
	terrain.set_layout_tile(hover_cell,kind)
	stroke_changed = true

func _finish_paint() -> void:
	painting = false
	if not stroke_changed: return
	_remember(stroke_snapshot)
	if mode == 4 or mode == 5: terrain.refresh_map_footprint()
	_save_layout()

func _remember(snapshot: Dictionary) -> void:
	undo_stack.append(snapshot)
	if undo_stack.size() > 30: undo_stack.pop_front()

func _undo() -> void:
	if undo_stack.is_empty(): return
	selected = null
	placing_object = false
	terrain.restore_village_layout_snapshot(undo_stack.pop_back())
	_save_layout()
	selection_label.text = "이전 배치로 되돌렸습니다."
	queue_redraw()

func _reset_selected() -> void:
	if not is_instance_valid(selected): return
	var key := selected.get_parent().name+"/"+selected.name
	_remember(terrain.get_village_layout_snapshot())
	var was_added: bool = terrain.is_added_layout_object(key)
	if was_added:
		terrain.remove_layout_object(key)
	else:
		terrain.clear_layout_cell(key)
		terrain.refresh_village_layout()
	selected = null
	_save_layout()
	selection_label.text = key+(" 추가 오브젝트 삭제" if was_added else " 기본 위치로 복구")

func _start_placing_object() -> void:
	_set_mode(0)
	selected = null
	placing_object = true
	selection_label.text = OBJECT_CATALOG[object_picker.selected][0]+"을 놓을 타일을 클릭하세요."

func _place_object(cell: Vector2i) -> void:
	var entry: Array = OBJECT_CATALOG[object_picker.selected]
	var source: String = entry[1]
	var variant: String = str(entry[2]) if entry.size() > 2 else ""
	var snapshot: Dictionary = terrain.get_village_layout_snapshot()
	var key: String = terrain.add_layout_object(source,cell,variant)
	if key.is_empty():
		status_label.text = "이 오브젝트를 추가할 수 없습니다."
		return
	_remember(snapshot)
	selected = get_parent().get_node_or_null(key) as StaticBody2D
	placing_object = false
	selection_label.text = OBJECT_CATALOG[object_picker.selected][0]+" 추가 · "+str(cell)
	_save_layout()

func _remove_selected() -> void:
	if not is_instance_valid(selected):
		selection_label.text = "먼저 삭제할 오브젝트를 클릭하세요."
		return
	var key := selected.get_parent().name+"/"+selected.name
	_remember(terrain.get_village_layout_snapshot())
	selected = null
	terrain.remove_layout_object(key)
	_save_layout()
	selection_label.text = key+" 삭제 · Ctrl+Z로 되돌리기"

func _save_layout() -> void:
	var path := terrain.save_village_map_layout()
	if path.is_empty():
		status_label.text = "저장 실패: 지도 파일을 쓸 수 없습니다."
	else:
		status_label.text = "저장 완료 · "+("프로젝트 지도 파일" if path.ends_with("data\\village_map_layout.json") or path.ends_with("data/village_map_layout.json") else "사용자 데이터 파일")

func _cell_at(world_position: Vector2) -> Vector2i:
	var pos := terrain.to_local(world_position)
	return Vector2i(roundi(pos.x/terrain.tile_width+pos.y/terrain.tile_height),roundi(pos.y/terrain.tile_height-pos.x/terrain.tile_width))

func _pick_object(world_position: Vector2) -> StaticBody2D:
	var best: StaticBody2D
	var best_y := -INF
	for group_name in GROUPS:
		var group := get_parent().get_node_or_null(group_name)
		if group == null: continue
		for child in group.get_children():
			if not child is StaticBody2D: continue
			if not child.visible: continue
			for piece in child.get_children():
				var sprite := piece as Sprite2D
				if sprite == null or sprite.texture == null: continue
				var pixel: Vector2 = sprite.to_local(world_position)
				var size: Vector2i = sprite.texture.get_size()
				if pixel.x < 0 or pixel.y < 0 or pixel.x >= size.x or pixel.y >= size.y: continue
				var image_id: int = sprite.texture.get_instance_id()
				if not image_cache.has(image_id):
					image_cache[image_id] = sprite.texture.get_image()
				var image: Image = image_cache[image_id]
				if image == null or image.get_pixelv(Vector2i(pixel)).a < 0.10: continue
				if child.global_position.y > best_y:
					best = child
					best_y = child.global_position.y
	return best

func _draw() -> void:
	if not active: return
	if mode == 4 and terrain.can_add_layout_cell(hover_cell):
		_draw_cell_outline(hover_cell,Color(0.32,1.0,0.43,0.95))
	elif mode == 5 and terrain.is_exterior_cell(hover_cell):
		_draw_cell_outline(hover_cell,Color(1.0,0.34,0.28,0.95))
	elif mode == 6:
		var departure: Vector2i = terrain.get_expedition_departure_cell()
		for x in range(-2,3):
			for y in range(-2,3):
				var cell := departure+Vector2i(x,y)
				if terrain.is_exterior_cell(cell):
					_draw_cell_outline(cell,Color(1.0,0.71,0.17,0.7))
		if terrain.is_exterior_cell(hover_cell):
			_draw_cell_outline(hover_cell,Color(0.15,0.96,0.94,0.75))
	elif terrain.is_exterior_cell(hover_cell):
		_draw_cell_outline(hover_cell,Color(0.15,0.96,0.94,0.75))
	if is_instance_valid(selected):
		_draw_cell_outline(_cell_at(selected.global_position),Color(1.0,0.71,0.17,0.95))

func _draw_cell_outline(cell: Vector2i, color: Color) -> void:
	var center := to_local(terrain.to_global(terrain.grid_to_local(cell)))
	var half_width := terrain.tile_width*0.5
	var half_height := terrain.tile_height*0.5
	var corners := PackedVector2Array([
		center+Vector2(0,-half_height),center+Vector2(half_width,0),
		center+Vector2(0,half_height),center+Vector2(-half_width,0),
		center+Vector2(0,-half_height)
	])
	draw_colored_polygon(corners,Color(color.r,color.g,color.b,0.14))
	draw_polyline(corners,color,3.0,true)
