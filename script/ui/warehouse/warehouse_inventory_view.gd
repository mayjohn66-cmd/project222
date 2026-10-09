class_name WarehouseInventoryView
extends VBoxContainer


signal contents_changed


@onready var capacity_label: Label = (
	$Header/CapacityLabel
)

@onready var empty_label: Label = (
	$EmptyLabel
)

@onready var item_scroll: ScrollContainer = (
	$ItemScroll
)

@onready var item_grid: GridContainer = (
	$ItemScroll/ItemGrid
)


var storage: Node = null


func _ready() -> void:
	# 빈 영역에서도 부모가 드롭 데이터를 받을 수 있게 한다.
	item_scroll.mouse_filter = (
		Control.MOUSE_FILTER_PASS
	)

	item_grid.mouse_filter = (
		Control.MOUSE_FILTER_PASS
	)

	empty_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	refresh_view()


func refresh_view() -> void:
	clear_item_grid()

	if not is_instance_valid(storage):
		capacity_label.text = "0 / 0"
		empty_label.show()
		return

	if storage.is_queued_for_deletion():
		capacity_label.text = "0 / 0"
		empty_label.show()
		return

	var stored_amount: int = 0
	var storage_capacity: int = int(
		storage.get(
			"storage_capacity"
		)
	)

	if storage.has_method(
		"get_total_stored_amount"
	):
		stored_amount = int(
			storage.call(
				"get_total_stored_amount"
			)
		)

	capacity_label.text = (
		"%d / %d"
		% [
			stored_amount,
			storage_capacity
		]
	)

	var stored_items: Dictionary = {}

	if storage.has_method(
		"get_stored_items"
	):
		stored_items = storage.call(
			"get_stored_items"
		)

	var item_ids: Array[String] = []

	for raw_item_id in stored_items.keys():
		var item_id: String = str(
			raw_item_id
		)

		if item_id.is_empty():
			continue

		if not ItemData.has_item(
			item_id
		):
			continue

		var amount: int = int(
			stored_items.get(
				item_id,
				0
			)
		)

		if amount <= 0:
			continue

		item_ids.append(
			item_id
		)

	item_ids.sort()

	empty_label.visible = (
		item_ids.is_empty()
	)

	for item_id in item_ids:
		create_storage_item_card(
			item_id,
			int(
				stored_items.get(
					item_id,
					0
				)
			)
		)


func create_storage_item_card(
	item_id: String,
	amount: int
) -> void:
	var card: ItemCard = (
		GameConfig.ITEM_CARD_SCENE.instantiate()
		as ItemCard
	)

	if card == null:
		push_error(
			"[창고 인벤토리] ItemCard 생성 실패"
		)
		return

	item_grid.add_child(
		card
	)

	card.setup(
		item_id,
		amount
	)

	card.enable_item_drag(
		"warehouse",
		amount
	)


func clear_item_grid() -> void:
	for child in item_grid.get_children():
		item_grid.remove_child(
			child
		)

		child.queue_free()


func _can_drop_data(
	_at_position: Vector2,
	data: Variant
) -> bool:
	if not is_instance_valid(storage):
		return false

	if storage.is_queued_for_deletion():
		return false

	if not data is Dictionary:
		return false

	if str(
		data.get(
			"type",
			""
		)
	) != ItemCard.DRAG_TYPE_ITEM_TRANSFER:
		return false

	if str(
		data.get(
			"source",
			""
		)
	) != "player":
		return false

	var item_id: String = str(
		data.get(
			"item_id",
			""
		)
	)

	if item_id.is_empty():
		return false

	if not ItemData.has_item(
		item_id
	):
		return false

	if not storage.has_method(
		"get_remaining_capacity"
	):
		return false

	return int(
		storage.call(
			"get_remaining_capacity"
		)
	) > 0


func _drop_data(
	_at_position: Vector2,
	data: Variant
) -> void:
	if not is_instance_valid(storage):
		return

	var item_id: String = str(
		data.get(
			"item_id",
			""
		)
	)

	var requested_amount: int = maxi(
		int(
			data.get(
				"amount",
				0
			)
		),
		0
	)

	if (
		item_id.is_empty()
		or requested_amount <= 0
	):
		return

	if not storage.has_method(
		"deposit_from_inventory"
	):
		return

	var moved_amount: int = int(
		storage.call(
			"deposit_from_inventory",
			item_id,
			requested_amount
		)
	)

	if moved_amount <= 0:
		return

	refresh_view()

	contents_changed.emit()
