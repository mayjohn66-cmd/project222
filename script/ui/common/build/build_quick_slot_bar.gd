extends Control

# 건축 퀵슬롯과 가구 가방 UI를 제어한다.
# 고정 레이아웃은 대응하는 씬이 소유하며, 가구 수에 따라 달라지는
# 슬롯 버튼과 가구 카드는 이 스크립트가 동적으로 생성한다.


signal slot_pressed(
	slot_index: int,
	build_id: String
)


const FURNITURE_DRAG_TYPE: String = (
	"build_furniture_registration"
)

const QUICK_SLOT_DRAG_TYPE: String = (
	"build_quick_slot_return"
)

const NORMAL_SLOT_COLOR: Color = Color.WHITE
const SELECTED_SLOT_COLOR: Color = Color(1.0, 0.8, 0.25, 1.0)

const INVENTORY_HEIGHT: float = 250.0
const SLIDE_DURATION: float = 0.22


@onready var slot_container: HBoxContainer = (
	$QuickSlotPanel/Slots
)

@onready var quick_panel: PanelContainer = (
	$QuickSlotPanel
)

@onready var bag_button: Button = (
	$FurnitureBagButton
)

@onready var inventory_clip: Control = (
	$FurnitureInventoryClip
)

@onready var inventory_panel: PanelContainer = (
	$FurnitureInventoryClip/FurnitureInventoryPanel
)

@onready var empty_label: Label = (
	$FurnitureInventoryClip/FurnitureInventoryPanel/Margin/Column/Scroll/Content/EmptyLabel
)

@onready var inventory_grid: GridContainer = (
	$FurnitureInventoryClip/FurnitureInventoryPanel/Margin/Column/Scroll/Content/InventoryGrid
)


var slot_buttons: Array[Button] = []
var selected_slot_index: int = -1

var inventory_open: bool = false
var inventory_tween: Tween

# 0 = 닫힘, 1 = 완전히 열림
var inventory_slide_progress: float = 0.0

func _ready() -> void:
	_setup_build_presentation()
	quick_panel.resized.connect(_sync_bag_width)
	call_deferred("_sync_bag_width")
	process_mode = Node.PROCESS_MODE_ALWAYS

	set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	# 화면 전체를 덮는 루트는 마우스 입력을 막지 않음
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	quick_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_container.mouse_filter = Control.MOUSE_FILTER_PASS

	create_slot_buttons()

	_connect_inventory_return_targets(
		inventory_panel
	)

	bag_button.pressed.connect(
		_on_bag_button_pressed
	)

	apply_inventory_slide(0.0)

	refresh_slots()
	refresh_furniture_inventory()

	if not GameState.furniture_inventory_changed.is_connected(
		_on_furniture_inventory_changed
	):
		GameState.furniture_inventory_changed.connect(
			_on_furniture_inventory_changed
		)

	if not GameState.build_quick_slot_changed.is_connected(
		_on_build_quick_slot_changed
	):
		GameState.build_quick_slot_changed.connect(
			_on_build_quick_slot_changed
		)

	visible = false


func create_slot_buttons() -> void:
	for child in slot_container.get_children():
		slot_container.remove_child(child)
		child.queue_free()

	slot_buttons.clear()

	for i in range(GameState.BUILD_QUICK_SLOT_COUNT):
		var button := Button.new()
		preload("res://script/ui/common/inventory/inventory_slot_style.gd").apply(button)

		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_NONE

		button.custom_minimum_size = Vector2(
			72.0,
			72.0
		)

		button.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)

		button.pressed.connect(
			_on_slot_button_pressed.bind(i)
		)

		button.set_drag_forwarding(
			_get_quick_slot_drag_data.bind(i),
			_can_drop_on_quick_slot.bind(i),
			_drop_on_quick_slot.bind(i)
		)

		slot_container.add_child(button)
		slot_buttons.append(button)
		_create_slot_content(button,i)


func refresh_furniture_inventory() -> void:
	for child in inventory_grid.get_children():
		inventory_grid.remove_child(child)
		child.queue_free()

	GameState.initialize_furniture_inventory()

	var displayed_count: int = 0

	for raw_build_id in GameState.get_furniture_inventory_ids():
		var build_id: String = str(raw_build_id)
		if not ShopSpaceProgression.furniture_visible(build_id): continue

		var count: int = GameState.get_furniture_count(
			build_id
		)

		if count <= 0:
			continue

		if not FurnitureData.has_furniture(build_id):
			continue

		# 퀵슬롯으로 옮긴 가구는 인벤토리에 표시하지 않음
		if GameState.find_build_quick_slot(build_id) >= 0:
			continue

		var card = GameConfig.ITEM_CARD_SCENE.instantiate()
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.set_meta("build_id", build_id)

		card.tooltip_text = (
			"원하는 퀵슬롯으로 드래그해 이동"
		)

		card.set_drag_forwarding(
			_get_furniture_drag_data.bind(
				build_id,
				card
			),
			_can_return_quick_slot,
			_return_quick_slot
		)

		inventory_grid.add_child(card)
		card.setup_furniture(build_id,count)
		displayed_count += 1

	empty_label.text = "인벤토리에 남은 가구가 없습니다."
	empty_label.hide()
	var capacity: int = maxi(18,ceili(float(displayed_count)/9.0)*9)
	while inventory_grid.get_child_count()<capacity:
		var empty := Button.new()
		empty.custom_minimum_size = Vector2(72,72)
		empty.focus_mode = Control.FOCUS_NONE
		empty.tooltip_text = "퀵슬롯의 가구를 이곳으로 옮길 수 있습니다."
		preload("res://script/ui/common/inventory/inventory_slot_style.gd").apply(empty)
		empty.set_drag_forwarding(Callable(),_can_return_quick_slot,_return_quick_slot)
		inventory_grid.add_child(empty)



func _on_bag_button_pressed() -> void:
	set_inventory_open(not inventory_open)


func set_inventory_open(open: bool) -> void:
	if open and not visible:
		return

	inventory_open = open

	if inventory_tween != null and inventory_tween.is_valid():
		inventory_tween.kill()

	if open:
		refresh_furniture_inventory()
		inventory_clip.show()
		bag_button.text = "가방 닫기"
	else:
		bag_button.text = "가구 가방"

	var target_progress: float = 0.0

	if open:
		target_progress = 1.0

	inventory_tween = create_tween()
	inventory_tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS
	)
	inventory_tween.set_trans(Tween.TRANS_CUBIC)
	inventory_tween.set_ease(Tween.EASE_OUT)

	# 하나의 진행값으로 세 요소를 동시에 이동
	inventory_tween.tween_method(
		apply_inventory_slide,
		inventory_slide_progress,
		target_progress,
		SLIDE_DURATION
	)

	if not open:
		inventory_tween.tween_callback(
			inventory_clip.hide
		)



func close_inventory_immediately() -> void:
	if inventory_tween != null and inventory_tween.is_valid():
		inventory_tween.kill()

	inventory_open = false

	apply_inventory_slide(0.0)

	inventory_clip.hide()
	bag_button.text = "가구 가방"


func set_build_mode_active(active: bool) -> void:
	visible = active

	if active:
		refresh_slots()
		refresh_furniture_inventory()
	else:
		close_inventory_immediately()
		clear_selected_slot()


func _on_furniture_inventory_changed(
	_furniture_id: String,
	_count: int
) -> void:
	refresh_slots()

	if inventory_open:
		refresh_furniture_inventory()

func _on_build_quick_slot_changed(
	_slot_index: int,
	_previous_build_id: String,
	_new_build_id: String
) -> void:
	refresh_slots()

	if inventory_open:
		call_deferred(
			"refresh_furniture_inventory"
		)



func refresh_slots() -> void:
	for i in range(slot_buttons.size()):
		var button: Button = slot_buttons[i]
		var build_id: String = GameState.get_build_quick_slot(i)
		button.visible = build_id.is_empty() or ShopSpaceProgression.furniture_visible(build_id)

		button.text = ""
		var icon_rect: TextureRect = button.get_node("FurnitureIcon")
		var title: Label = button.get_node("FurnitureTitle")
		var amount: Label = button.get_node("FurnitureCount")
		icon_rect.texture = FurnitureData.get_furniture_icon(build_id) if not build_id.is_empty() else null
		title.text = FurnitureData.get_furniture_name(build_id) if not build_id.is_empty() else "—"
		amount.text = str(GameState.get_furniture_count(build_id)) if not build_id.is_empty() else ""
		button.tooltip_text = title.text
		title.hide()

	refresh_slot_highlight()


func _on_slot_button_pressed(slot_index: int) -> void:
	var build_id: String = (
		GameState.get_build_quick_slot(slot_index)
	)

	# 빈 슬롯 클릭으로 팝업을 열던 기능 제거
	if build_id.is_empty():
		return

	slot_pressed.emit(slot_index, build_id)


func set_selected_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slot_buttons.size():
		clear_selected_slot()
		return

	selected_slot_index = slot_index
	refresh_slot_highlight()


func clear_selected_slot() -> void:
	selected_slot_index = -1
	refresh_slot_highlight()


func refresh_slot_highlight() -> void:
	for i in range(slot_buttons.size()):
		var button: Button = slot_buttons[i]

		if i == selected_slot_index:
			button.modulate = SELECTED_SLOT_COLOR
		else:
			button.modulate = NORMAL_SLOT_COLOR

func apply_inventory_slide(progress: float) -> void:
	inventory_slide_progress = progress

	# 인벤토리 높이 + 퀵슬롯과의 간격
	var slide_distance: float = INVENTORY_HEIGHT + 10.0
	var lift: float = slide_distance * progress

	# 퀵슬롯을 위로 밀어 올림
	quick_panel.offset_top = -112.0 - lift
	quick_panel.offset_bottom = -16.0 - lift

	# 가방 버튼은 화면 아래에 고정
	bag_button.offset_top = -104.0
	bag_button.offset_bottom = -56.0

	# 인벤토리는 아래에서 올라옴
	inventory_panel.position.y = slide_distance - lift

func try_close_inventory() -> bool:
	if not visible:
		return false

	if inventory_open:
		set_inventory_open(false)
		return true

	# 닫히는 애니메이션 중에도 ESC가
	# 배치 저장 확인창으로 넘어가지 않도록 처리
	if inventory_clip.visible:
		return true

	return false

func is_inventory_active() -> bool:
	return (
		visible
		and (
			inventory_open
			or inventory_clip.visible
		)
	)

# =========================
# 드래그 공통 처리
# =========================

func _is_inventory_interactive() -> bool:
	return (
		is_visible_in_tree()
		and inventory_open
	)


func _is_valid_slot_index(
	slot_index: int
) -> bool:
	return (
		slot_index >= 0
		and slot_index < GameState.BUILD_QUICK_SLOT_COUNT
	)


func _is_available_furniture(
	build_id: String
) -> bool:
	if not ShopSpaceProgression.furniture_visible(build_id): return false
	if build_id.is_empty():
		return false

	if not FurnitureData.has_furniture(build_id):
		return false

	return (
		GameState.get_furniture_count(build_id)
		> 0
	)


func _is_drag_type(
	data: Variant,
	expected_type: String
) -> bool:
	if not data is Dictionary:
		return false

	return (
		str(data.get("type", ""))
		== expected_type
	)


func _make_furniture_drag_icon(build_id: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = FurnitureData.get_furniture_icon(build_id)
	icon.custom_minimum_size = Vector2(64,64)
	icon.size = Vector2(64,64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _create_drag_preview(source_control: Control, build_id: String) -> void:
	source_control.set_drag_preview(_make_furniture_drag_icon(build_id))


# =========================
# 인벤토리 → 퀵슬롯
# =========================

func _get_furniture_drag_data(
	_at_position: Vector2,
	build_id: String,
	card: Button
) -> Variant:
	if not _is_inventory_interactive():
		return null

	if not _is_available_furniture(build_id):
		return null

	_create_drag_preview(
		card,
		build_id
	)

	return {
		"type": FURNITURE_DRAG_TYPE,
		"build_id": build_id
	}


func _can_drop_on_quick_slot(
	_at_position: Vector2,
	data: Variant,
	slot_index: int
) -> bool:
	if not _is_inventory_interactive():
		return false

	if not _is_valid_slot_index(slot_index):
		return false

	if not data is Dictionary:
		return false

	var drag_type: String = str(
		data.get("type", "")
	)

	# 가구 인벤토리에서 퀵슬롯으로 등록
	if drag_type == FURNITURE_DRAG_TYPE:
		var inventory_build_id: String = str(
			data.get("build_id", "")
		)

		return _is_available_furniture(
			inventory_build_id
		)

	# 다른 퀵슬롯에서 이동하거나 서로 교환
	if drag_type == QUICK_SLOT_DRAG_TYPE:
		var source_slot_index: int = int(
			data.get("slot_index", -1)
		)

		if not _is_valid_slot_index(
			source_slot_index
		):
			return false

		if source_slot_index == slot_index:
			return false

		var source_build_id: String = str(
			data.get("build_id", "")
		)

		# 드래그를 시작한 뒤 슬롯 내용이 바뀌었다면 취소한다.
		return (
			not source_build_id.is_empty()
			and GameState.get_build_quick_slot(
				source_slot_index
			) == source_build_id
		)

	return false


func _drop_on_quick_slot(
	at_position: Vector2,
	data: Variant,
	slot_index: int
) -> void:
	if not _can_drop_on_quick_slot(
		at_position,
		data,
		slot_index
	):
		return

	var drag_type: String = str(
		data.get("type", "")
	)

	if drag_type == FURNITURE_DRAG_TYPE:
		var build_id: String = str(
			data.get("build_id", "")
		)

		_change_quick_slot(
			slot_index,
			build_id
		)
		return

	if drag_type == QUICK_SLOT_DRAG_TYPE:
		_move_or_swap_quick_slots(
			int(data.get("slot_index", -1)),
			slot_index
		)


func _move_or_swap_quick_slots(
	source_slot_index: int,
	target_slot_index: int
) -> bool:
	if (
		not _is_valid_slot_index(source_slot_index)
		or not _is_valid_slot_index(target_slot_index)
		or source_slot_index == target_slot_index
	):
		return false

	var source_build_id: String = (
		GameState.get_build_quick_slot(
			source_slot_index
		)
	)

	if source_build_id.is_empty():
		return false

	var target_build_id: String = (
		GameState.get_build_quick_slot(
			target_slot_index
		)
	)

	# 대상이 비어 있으면 이동하고, 차 있으면 두 슬롯을 교환한다.
	if not GameState.set_build_quick_slot(
		source_slot_index,
		target_build_id
	):
		return false

	if not GameState.set_build_quick_slot(
		target_slot_index,
		source_build_id
	):
		# 두 번째 변경이 실패하면 원래 슬롯을 복구한다.
		GameState.set_build_quick_slot(
			source_slot_index,
			source_build_id
		)
		return false

	selected_slot_index = target_slot_index
	refresh_slots()

	return true


# =========================
# 퀵슬롯 → 인벤토리
# =========================

func _get_quick_slot_drag_data(
	_at_position: Vector2,
	slot_index: int
) -> Variant:
	if not _is_inventory_interactive():
		return null

	if not _is_valid_slot_index(slot_index):
		return null

	var build_id: String = (
		GameState.get_build_quick_slot(
			slot_index
		)
	)

	if build_id.is_empty():
		return null

	_create_drag_preview(
		slot_buttons[slot_index],
		build_id
	)

	return {
		"type": QUICK_SLOT_DRAG_TYPE,
		"slot_index": slot_index,
		"build_id": build_id
	}


func _can_return_quick_slot(
	_at_position: Vector2,
	data: Variant
) -> bool:
	if not _is_inventory_interactive():
		return false

	if not _is_drag_type(
		data,
		QUICK_SLOT_DRAG_TYPE
	):
		return false

	if (
		typeof(data.get("slot_index", null))
		!= TYPE_INT
	):
		return false

	var slot_index: int = int(
		data.get("slot_index", -1)
	)

	if not _is_valid_slot_index(slot_index):
		return false

	var build_id: String = str(
		data.get("build_id", "")
	)

	if build_id.is_empty():
		return false

	# 드래그 도중 슬롯이 변경됐는지 확인
	return (
		GameState.get_build_quick_slot(
			slot_index
		)
		== build_id
	)


func _return_quick_slot(
	at_position: Vector2,
	data: Variant
) -> void:
	if not _can_return_quick_slot(
		at_position,
		data
	):
		return

	var slot_index: int = int(
		data.get("slot_index", -1)
	)

	_change_quick_slot(
		slot_index,
		""
	)


# =========================
# 슬롯 변경 공통 처리
# =========================

func _change_quick_slot(
	slot_index: int,
	new_build_id: String
) -> bool:
	if not _is_valid_slot_index(slot_index):
		return false

	var current_build_id: String = (
		GameState.get_build_quick_slot(
			slot_index
		)
	)

	if current_build_id == new_build_id:
		return false

	if new_build_id.is_empty():
		GameState.clear_build_quick_slot(
			slot_index
		)

		return true

	if not _is_available_furniture(
		new_build_id
	):
		return false

	# 같은 종류의 가구는 한 슬롯에만 등록
	var existing_slot: int = (
		GameState.find_build_quick_slot(
			new_build_id
		)
	)

	if existing_slot >= 0:
		return false

	return GameState.set_build_quick_slot(
		slot_index,
		new_build_id
	)


# =========================
# 인벤토리 드롭 영역 연결
# =========================

func _connect_inventory_return_targets(
	control: Control
) -> void:
	control.set_drag_forwarding(
		Callable(),
		_can_return_quick_slot,
		_return_quick_slot
	)

	for child in control.get_children():
		if child is Control:
			_connect_inventory_return_targets(
				child
			)

func _create_slot_content(button: Button, index: int) -> void:
	var icon_rect := TextureRect.new()
	icon_rect.name = "FurnitureIcon"
	icon_rect.anchor_left = 0.5
	icon_rect.anchor_right = 0.5
	icon_rect.offset_left = -24
	icon_rect.offset_right = 24
	icon_rect.offset_top = 12
	icon_rect.offset_bottom = 60
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon_rect)
	for definition in [["Shortcut",str(index+1),4,20,13],["FurnitureTitle","",61,77,12],["FurnitureCount","",50,71,16]]:
		var label := Label.new()
		label.name = definition[0]
		label.text = definition[1]
		label.anchor_right = 1.0
		label.offset_left = 7
		label.offset_right = -7
		label.offset_top = definition[2]
		label.offset_bottom = definition[3]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if label.name == "Shortcut" else HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",definition[4])
		if label.name == "FurnitureCount":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_color_override("font_color",Color("fff4d6"))
			label.add_theme_color_override("font_outline_color",Color("593e28"))
			label.add_theme_constant_override("outline_size",3)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)


func _sync_bag_width() -> void:
	var width: float = quick_panel.size.x
	inventory_clip.offset_left = -width*0.5
	inventory_clip.offset_right = width*0.5
	inventory_panel.custom_minimum_size.x = width
	inventory_panel.size.x = width

func _setup_build_presentation() -> void:
	var style = preload("res://script/ui/common/build/build_ui_style.gd")
	quick_panel.add_theme_stylebox_override("panel",style.paper())
	inventory_panel.add_theme_stylebox_override("panel",style.paper())
	quick_panel.offset_left = -360
	quick_panel.offset_right = 360
	slot_container.add_theme_constant_override("separation",6)
	inventory_panel.custom_minimum_size = Vector2(720,250)
	inventory_panel.size = Vector2(720,250)
	inventory_clip.offset_top = -266
	inventory_clip.offset_bottom = -16
	var margin = inventory_panel.get_node("Margin")
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,0)
	var title = inventory_panel.get_node("Margin/Column/Header/Title")
	title.text = "가구 가방"
	title.add_theme_font_size_override("font_size",18)
	var hint := Label.new()
	hint.text = "드래그하여 퀵슬롯에 등록"
	hint.add_theme_font_size_override("font_size",14)
	hint.add_theme_color_override("font_color",Color("896440"))
	inventory_panel.get_node("Margin/Column/Header").add_child(hint)
	style.button(bag_button)
	bag_button.text = "가구 가방"
	bag_button.offset_left = 374
	bag_button.offset_right = 490
	var finish := Button.new()
	finish.name = "FinishBuildButton"
	finish.text = "건설 완료"
	style.button(finish)
	add_child(finish)
	finish.anchor_left = 1
	finish.anchor_right = 1
	finish.offset_left = -152
	finish.offset_right = -24
	finish.offset_top = 24
	finish.offset_bottom = 70
	finish.pressed.connect(func(): get_tree().call_group("build_manager","request_build_mode_exit"))
	var guide := Label.new()
	guide.name = "BuildGuide"
	guide.text = "건설 모드   ·   1–9 선택   /   R 회전   /   Esc 완료"
	guide.add_theme_font_size_override("font_size",16)
	guide.add_theme_color_override("font_color",Color("fff1d4"))
	guide.add_theme_color_override("font_outline_color",Color("493b2d"))
	guide.add_theme_constant_override("outline_size",4)
	guide.position = Vector2(24,30)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(guide)
