class_name TransferInventorySlot
extends Button


signal item_drop_received(
	drag_data: Dictionary,
	target_side: String,
	target_slot_index: int
)


const DRAG_TYPE: String = (
	"item_transfer_slot"
)


@onready var icon_rect: TextureRect = (
	$IconRect
)

@onready var count_label: Label = (
	$CountLabel
)


var slot_index: int = -1
var inventory_side: String = ""

var item_id: String = ""
var item_amount: int = 0


func _ready() -> void:
	preload("res://script/ui/common/inventory/inventory_slot_style.gd").content(self)
	count_label.text = ""


func configure_slot(
	new_slot_index: int,
	new_inventory_side: String,
	new_item_id: String = "",
	new_item_amount: int = 0
) -> void:

	slot_index = new_slot_index
	inventory_side = new_inventory_side
	item_id = new_item_id
	item_amount = maxi(new_item_amount, 0)

	disabled = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	if (
		item_id.is_empty()
		or item_amount <= 0
	):
		clear_item()
		return

	if not ItemData.has_item(
		item_id
	):
		clear_item()
		return

	icon_rect.visible = true
	count_label.visible = true

	icon_rect.texture = (
		ItemData.get_item_icon(
			item_id
		)
	)

	count_label.text = (
		str(item_amount)
	)

	tooltip_text = (
		ItemData.get_item_name(
			item_id
		)
		+ "\n보유 수량: "
		+ str(item_amount)
	)


func clear_item() -> void:
	item_id = ""
	item_amount = 0

	icon_rect.texture = null
	icon_rect.visible = false

	count_label.text = ""
	count_label.visible = false

	# 빈 슬롯도 드롭을 받아야 하므로 비활성화하면 안 된다.
	disabled = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	tooltip_text = "빈 슬롯"


func has_item() -> bool:
	return (
		not item_id.is_empty()
		and item_amount > 0
	)


func _get_drag_data(
	_at_position: Vector2
) -> Variant:
	if not has_item():
		return null

	if inventory_side.is_empty():
		return null

	var preview := TextureRect.new()

	preview.texture = icon_rect.texture

	preview.custom_minimum_size = Vector2(
		64.0,
		64.0
	)

	preview.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)

	preview.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	preview.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	set_drag_preview(
		preview
	)

	return {
		"type": DRAG_TYPE,
		"source_side": inventory_side,
		"source_slot_index": slot_index,
		"item_id": item_id,
		"amount": item_amount
	}


func _can_drop_data(
	_at_position: Vector2,
	data: Variant
) -> bool:
	if not data is Dictionary:
		return false

	var drag_data: Dictionary = data

	if str(
		drag_data.get(
			"type",
			""
		)
	) != "item_transfer_slot":
		return false

	var source_side: String = str(
		drag_data.get(
			"source_side",
			""
		)
	)

	var source_slot_index: int = int(
		drag_data.get(
			"source_slot_index",
			-1
		)
	)

	if source_side.is_empty():
		return false

	if source_slot_index < 0:
		return false

	# 플레이어 인벤토리 안에서는 위치를 변경하지 않는다.
	if (
		source_side == "player"
		and inventory_side == "player"
	):
		return false

	# 같은 창고 슬롯에 다시 놓는 경우만 거부한다.
	if (
		source_side == "container"
		and inventory_side == "container"
	):
		return (
			source_slot_index
			!= slot_index
		)

	# 플레이어와 창고 사이 이동
	return (
		source_side
		!= inventory_side
	)


func _drop_data(
	at_position: Vector2,
	data: Variant
) -> void:
	if not _can_drop_data(
		at_position,
		data
	):
		return

	if not data is Dictionary:
		return

	var drag_data: Dictionary = (
		data.duplicate(true)
	)

	item_drop_received.emit(
		drag_data,
		inventory_side,
		slot_index
	)
