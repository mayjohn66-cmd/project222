class_name GridInventoryView
extends Control


const GRID_ITEM_VISUAL_SCRIPT = preload(
	"res://script/ui/common/inventory/grid_item_visual.gd"
)


var grid_source: String = ""
var grid_model = null
var controller: Node = null

var grid_width: int = 6
var grid_height: int = 5
var cell_size: int = 52
var cell_color: Color = Color("d8b47c")


func setup(
	new_source: String,
	new_model,
	new_controller: Node,
	new_width: int = 6,
	new_height: int = 5,
	new_cell_size: int = 52
) -> void:
	grid_source = new_source
	grid_model = new_model
	controller = new_controller

	grid_width = new_width
	grid_height = new_height
	cell_size = new_cell_size

	custom_minimum_size = Vector2(
		grid_width * cell_size,
		grid_height * cell_size
	)

	size = custom_minimum_size

	mouse_filter = Control.MOUSE_FILTER_STOP

	queue_redraw()
	refresh()


# =========================
# 격자 배경
# =========================

func _draw() -> void:
	for y in range(grid_height):
		for x in range(grid_width):
			draw_rect(Rect2(x*cell_size+2,y*cell_size+2,cell_size-4,cell_size-4),cell_color,true)


# =========================
# 화면 갱신
# =========================

func refresh() -> void:
	_clear_item_visuals()

	if grid_model == null:
		return

	for placement in grid_model.placements:
		_create_item_visual(
			placement
		)


func refresh_selection_visuals() -> void:
	if controller == null:
		return

	for child in get_children():
		if not child.has_method(
			"set_selected"
		):
			continue

		var uid: int = int(
			child.get(
				"placement_uid"
			)
		)

		var is_selected: bool = false

		if controller.has_method(
			"is_grid_item_selected"
		):
			is_selected = bool(
				controller.call(
					"is_grid_item_selected",
					grid_source,
					uid
				)
			)

		child.call(
			"set_selected",
			is_selected
		)


func _create_item_visual(
	placement: Dictionary
) -> void:
	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var uid: int = int(
		placement.get(
			"uid",
			-1
		)
	)

	var cell: Vector2i = (
		placement.get(
			"cell",
			Vector2i.ZERO
		)
	)

	var rotated: bool = bool(
		placement.get(
			"rotated",
			false
		)
	)

	var amount: int = int(
		placement.get(
			"amount",
			1
		)
	)

	var enhancement_level: int = int(
		placement.get(
			"enhancement_level",
			0
		)
	)

	var item_size: Vector2i = (
		ItemData.get_bag_size(
			item_id,
			rotated
		)
	)

	var item = (
		GRID_ITEM_VISUAL_SCRIPT.new()
	)

	add_child(item)

	item.setup(
		grid_source,
		item_id,
		item_size,
		cell_size,
		uid,
		cell,
		rotated,
		amount,
		enhancement_level,
		self
	)

	item.position = Vector2(
		cell.x * cell_size,
		cell.y * cell_size
	)

	var is_selected: bool = false

	if (
		controller != null
		and controller.has_method(
			"is_grid_item_selected"
		)
	):
		is_selected = bool(
			controller.call(
				"is_grid_item_selected",
				grid_source,
				uid
			)
		)

	item.set_selected(
		is_selected
	)


func _clear_item_visuals() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


# =========================
# GridItemVisual → Controller
# =========================

func select_grid_item(
	source: String,
	uid: int
) -> void:
	if controller == null:
		return

	if controller.has_method(
		"select_grid_item"
	):
		controller.call(
			"select_grid_item",
			source,
			uid
		)

	refresh_selection_visuals()


func toggle_grid_item(
	source: String,
	uid: int
) -> void:
	if controller == null:
		return

	if controller.has_method(
		"toggle_grid_item"
	):
		controller.call(
			"toggle_grid_item",
			source,
			uid
		)

	refresh_selection_visuals()


# =========================
# 드롭 좌표
# =========================

func _get_cursor_cell(
	at_position: Vector2
) -> Vector2i:
	return Vector2i(
		floori(
			at_position.x
			/ float(cell_size)
		),
		floori(
			at_position.y
			/ float(cell_size)
		)
	)


# =========================
# 드롭
# =========================

func _can_drop_data(
	at_position: Vector2,
	data: Variant
) -> bool:
	if controller == null:
		return false

	if not data is Dictionary:
		return false

	if not controller.has_method(
		"can_drop_grid_data"
	):
		return false

	var cursor_cell: Vector2i = (
		_get_cursor_cell(
			at_position
		)
	)

	return bool(
		controller.call(
			"can_drop_grid_data",
			grid_source,
			data,
			cursor_cell
		)
	)


func _drop_data(
	at_position: Vector2,
	data: Variant
) -> void:
	if controller == null:
		return

	if not data is Dictionary:
		return

	if not controller.has_method(
		"drop_grid_data"
	):
		return

	var cursor_cell: Vector2i = (
		_get_cursor_cell(
			at_position
		)
	)

	controller.call(
		"drop_grid_data",
		grid_source,
		data,
		cursor_cell
	)

	refresh()


# 아이템 위에 놓을 때도 부모 격자의 드롭 판정 사용
func can_drop_data_from_child(
	data: Variant
) -> bool:
	return _can_drop_data(
		get_local_mouse_position(),
		data
	)


func drop_data_from_child(
	data: Variant
) -> void:
	_drop_data(
		get_local_mouse_position(),
		data
	)


# =========================
# 빈칸 클릭
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

	if controller == null:
		return

	if controller.has_method(
		"clear_grid_selection"
	):
		controller.call(
			"clear_grid_selection",
			grid_source
		)

	refresh_selection_visuals()
