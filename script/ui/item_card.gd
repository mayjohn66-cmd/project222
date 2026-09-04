class_name ItemCard
extends Button


signal item_selected(item_id: String)


@onready var icon_rect: TextureRect = $IconRect
@onready var count_label: Label = $CountLabel


var item_id: String = ""


func _ready():
	pressed.connect(
		_on_pressed
	)


func setup(
	new_item_id: String,
	count: int
):
	item_id = new_item_id

	icon_rect.texture = (
		ItemData.get_item_icon(
			item_id
		)
	)

	count_label.text = (
		"×" + str(count)
	)


func _on_pressed():
	if item_id.is_empty():
		return

	item_selected.emit(
		item_id
	)
