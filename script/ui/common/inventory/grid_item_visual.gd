class_name GridItemVisual
extends PanelContainer


const GRID_DRAG_HELPER = preload(
	"res://script/inventory/grid_drag_helper.gd"
)


var source: String = ""

var item_id: String = ""
var item_size: Vector2i = Vector2i.ONE
var cell_size: int = 52

var placement_uid: int = -1
var origin_cell: Vector2i = Vector2i(-1, -1)
var rotated: bool = false

var grid_controller: Node = null

var selected: bool = false
var amount: int = 1
var enhancement_level: int = 0

# =========================
# 초기 설정
# =========================

func setup(
	new_source: String,
	new_item_id: String,
	new_item_size: Vector2i,
	new_cell_size: int,
	new_placement_uid: int,
	new_origin_cell: Vector2i,
	new_rotated: bool,
	new_amount: int,
	new_enhancement_level: int,
	new_grid_controller: Node
) -> void:
	source = new_source

	item_id = new_item_id
	item_size = new_item_size
	cell_size = new_cell_size

	placement_uid = new_placement_uid
	origin_cell = new_origin_cell
	rotated = new_rotated

	amount = maxi(
		new_amount,
		1
	)

	enhancement_level = maxi(
		new_enhancement_level,
		0
	)

	grid_controller = new_grid_controller

	custom_minimum_size = Vector2(
		item_size.x * cell_size,
		item_size.y * cell_size
	)

	size = custom_minimum_size

	mouse_filter = Control.MOUSE_FILTER_STOP

	_create_visual_content()

	set_selected(false)

func _create_visual_content() -> void:
	var icon: Texture2D = (
		ItemData.get_item_icon(
			item_id
		)
	)

	if icon != null:
		_create_icon_visual(
			icon
		)
	else:
		_create_fallback_label()

	# 현재 구조에서는 장비는 개별 인스턴스이고,
	# 장비가 아닌 원정 아이템은 수량 중첩 아이템이다.
	var is_stackable: bool = (
		not ExpeditionEquipmentData.has_equipment(
			item_id
		)
	)

	if is_stackable:
		_create_count_badge(
			str(amount)
		)

	tooltip_text = _get_tooltip_text()

func _create_icon_visual(
	icon: Texture2D
) -> void:
	var icon_layer := Control.new()

	icon_layer.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	icon_layer.clip_contents = true

	icon_layer.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	add_child(
		icon_layer
	)

	var icon_rect := TextureRect.new()

	icon_rect.texture = icon

	icon_rect.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)

	icon_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	icon_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	icon_layer.add_child(
		icon_rect
	)

	var inner_size := Vector2(
		maxf(
			size.x - 8.0,
			1.0
		),
		maxf(
			size.y - 8.0,
			1.0
		)
	)

	if rotated:
		# 원본 이미지는 기본 방향 하나만 사용하고
		# 가방 회전 상태에 맞춰 화면에서 90도 회전한다.
		var unrotated_size := Vector2(
			inner_size.y,
			inner_size.x
		)

		icon_rect.size = unrotated_size

		icon_rect.position = (
			size - unrotated_size
		) * 0.5

		icon_rect.pivot_offset = (
			unrotated_size * 0.5
		)

		icon_rect.rotation = (
			PI * 0.5
		)

	else:
		icon_rect.size = inner_size

		icon_rect.position = Vector2(
			4.0,
			4.0
		)

func _create_fallback_label() -> void:
	var label := Label.new()

	label.text = (
		ItemData.get_item_name(
			item_id
		)
	)

	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	label.clip_text = true

	label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	label.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	label.offset_left = 3.0
	label.offset_top = 3.0
	label.offset_right = -3.0
	label.offset_bottom = -3.0

	label.add_theme_font_size_override(
		"font_size",
		10
	)

	add_child(
		label
	)

func _create_count_badge(count_text: String) -> void:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = count_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_right = -4
	label.offset_bottom = -2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",Color("fff4d6"))
	label.add_theme_color_override("font_outline_color",Color("593e28"))
	label.add_theme_constant_override("outline_size",3)


func _get_tooltip_text() -> String:
	var item_data: Dictionary = (
		ItemData.get_item(
			item_id
		)
	)

	var result: String = (
		ItemData.get_item_name(
			item_id
		)
	)

	var description: String = str(
		item_data.get(
			"description",
			""
		)
	)

	if not description.is_empty():
		result += (
			"\n\n"
			+ description
		)

	var base_size: Vector2i = (
		ItemData.get_bag_size(
			item_id,
			false
		)
	)

	if (
		base_size.x > 0
		and base_size.y > 0
	):
		result += (
			"\n\n가방 크기: "
			+ str(base_size.x)
			+ "×"
			+ str(base_size.y)
		)

	if ExpeditionEquipmentData.has_equipment(
		item_id
	):
		result += _get_equipment_tooltip_text()

	else:
		result += (
			"\n보유 개수: "
			+ str(amount)
		)

	return result

# ==========================
# 공통 표시 문자열
# ==========================

func _get_display_text() -> String:
	return ItemData.get_item_name(
		item_id
	)

# =========================
# 선택 표시
# =========================

func set_selected(
	value: bool
) -> void:
	selected = value

	var style := StyleBoxFlat.new()

	style.bg_color = Color("88aaa0") if selected else Color("d8b47c")

	add_theme_stylebox_override(
		"panel",
		style
	)


# =========================
# 클릭
# =========================

func _gui_input(
	event: InputEvent
) -> void:
	if not (
		event is InputEventMouseButton
	):
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		return

	if grid_controller == null:
		return

	if not grid_controller.has_method(
		"toggle_grid_item"
	):
		return

	grid_controller.call(
		"toggle_grid_item",
		source,
		placement_uid
	)


# =========================
# 드래그 시작
# =========================

func _get_drag_data(
	at_position: Vector2
) -> Variant:
	if item_id.is_empty():
		return null

	if placement_uid == -1:
		return null

	# 드래그 시작 시 해당 아이템 선택
	if (
		grid_controller != null
		and grid_controller.has_method(
			"select_grid_item"
		)
	):
		grid_controller.call(
			"select_grid_item",
			source,
			placement_uid
		)

	var grab_offset_cell: Vector2i = (
		GRID_DRAG_HELPER.get_grab_offset_from_local(
			at_position,
			item_size,
			cell_size
		)
	)

	_create_drag_preview(
		at_position
	)

	return GRID_DRAG_HELPER.make_drag_data(
		source,
		placement_uid,
		item_id,
		rotated,
		grab_offset_cell,
		{
			"origin_cell": origin_cell,
			"item_size": item_size
		}
	)


# =========================
# 드래그 미리보기
# =========================

func _create_drag_preview(
	at_position: Vector2
) -> void:
	var preview_root := Control.new()

	preview_root.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	var preview := PanelContainer.new()

	preview.custom_minimum_size = Vector2(
		item_size.x * cell_size,
		item_size.y * cell_size
	)

	preview.size = preview.custom_minimum_size

	# 실제 잡은 부분이 커서 위치를 유지
	preview.position = -at_position

	var style := StyleBoxFlat.new()

	style.bg_color = Color(
		0.18,
		0.50,
		0.22,
		0.85
	)

	style.border_color = Color(
		0.35,
		0.90,
		0.40
	)

	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0

	preview.add_theme_stylebox_override(
		"panel",
		style
	)

	var label := Label.new()

	label.text = _get_display_text()

	label.add_theme_font_size_override(
		"font_size",
		12
	)

	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	label.clip_text = true

	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	label.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	preview.add_child(label)

	preview_root.add_child(
		preview
	)

	set_drag_preview(
		preview_root
	)

func _can_drop_data(
	_at_position: Vector2,
	data: Variant
) -> bool:
	if grid_controller == null:
		return false

	if not grid_controller.has_method(
		"can_drop_data_from_child"
	):
		return false

	return bool(
		grid_controller.call(
			"can_drop_data_from_child",
			data
		)
	)


func _drop_data(
	_at_position: Vector2,
	data: Variant
) -> void:
	if grid_controller == null:
		return

	if not grid_controller.has_method(
		"drop_data_from_child"
	):
		return

	grid_controller.call(
		"drop_data_from_child",
		data
	)

func _get_equipment_tooltip_text() -> String:
	var equipment_type: String = (
		ExpeditionEquipmentData.get_equipment_type(
			item_id
		)
	)

	var type_text: String = "장비"

	match equipment_type:
		ExpeditionEquipmentData.TYPE_WEAPON:
			type_text = "무기"

		ExpeditionEquipmentData.TYPE_ARMOR:
			type_text = "방어구"

		ExpeditionEquipmentData.TYPE_TOOL:
			type_text = "채집 도구"

	var max_level: int = (
		ExpeditionEquipmentData
		.get_max_enhancement_level(
			item_id
		)
	)

	var effective_value: int = (
		EquipmentEnhancementService
		.get_effective_value(
			{
				"item_id": item_id,
				"enhancement_level": (
					enhancement_level
				)
			}
		)
	)

	var result: String = (
		"\n분류: "
		+ type_text
	)

	result += (
		"\n강화 단계: +"
		+ str(enhancement_level)
		+ " / +"
		+ str(max_level)
	)

	var effect_id: String = (
		ExpeditionEquipmentData.get_effect_id(
			item_id
		)
	)

	match effect_id:
		"attack":
			# 공격력 숫자는 보이지 않고 공격 방식만 보인다.
			result += (
				"\n공격 방식: "
				+ ExpeditionWeaponLoadout.get_style_text(item_id)
			)

		"defense":
			result += (
				"\n방어력: +"
				+ str(effective_value)
			)

		"harvest_wheat":
			result += (
				"\n밀 채집 성공률: 100%"
				+ "\n밀 추가 획득: +"
				+ str(effective_value)
				+ "개"
			)

		"collect_water":
			result += (
				"\n호수에서 물 채집 가능"
				+ "\n물 추가 획득: +"
				+ str(effective_value)
				+ "개"
			)

		_:
			if effective_value > 0:
				result += (
					"\n효과 수치: "
					+ str(effective_value)
				)

	return result
