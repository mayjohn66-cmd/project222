class_name ShelfSlotCard
extends Button


signal slot_selected(slot_index: int)


@onready var icon_rect: TextureRect = $IconRect
@onready var status_label: Label = $StatusLabel
@onready var stock_label: Label = $StockLabel


var slot_index: int = -1


func _ready() -> void:
	preload("res://script/ui/common/inventory/inventory_slot_style.gd").apply(self)
	pressed.connect(_on_pressed)


func setup(
	new_slot_index: int,
	slot_data: Dictionary,
	is_selected: bool = false
) -> void:
	slot_index = new_slot_index

	var item_id: String = str(
		slot_data.get("item_id", "")
	)
	var stock: int = maxi(
		int(slot_data.get("stock", 0)),
		0
	)
	var capacity: int = maxi(
		int(slot_data.get("capacity", 0)),
		0
	)

	if item_id.is_empty():
		icon_rect.texture = null
		status_label.text = (
			"선택됨" if is_selected else "빈 슬롯"
		)
		status_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER
		)
		stock_label.text = "%d / %d" % [stock, capacity]
		tooltip_text = ""
	else:
		icon_rect.texture = ItemData.get_item_icon(item_id)
		status_label.text = str(stock)
		status_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT
		)
		stock_label.text = (
			str(ItemData.get_item_price(item_id))
			+ "G"
		)
		tooltip_text = ItemData.get_item_name(item_id)
		if FoodShelfLife.tracked(item_id) and stock > 0:
			var batches := FoodShelfLife.slot_batches(slot_data)
			var oldest := batches.duplicate(true)
			var receipt := FoodShelfLife.take(oldest, 1)
			stock_label.text = "%dG" % FoodShelfLife.receipt_total(item_id, receipt)
			tooltip_text += "\n" + FoodShelfLife.describe(item_id, batches)


func _on_pressed() -> void:
	if slot_index < 0:
		return

	slot_selected.emit(slot_index)
