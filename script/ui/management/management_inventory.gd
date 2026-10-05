extends Control


# 통합 인벤토리의 분류 탭과 아이템 목록을 관리한다.
# 일반 아이템은 ItemData와 GameState에서 가져오며,
# 가구와 고유 장비는 별도 데이터 구조이므로 이후 단계에서 연결한다.


@onready var shelf_button: Button = (
	$MainVBox/CategoryTabs/ShelfButton
)

@onready var furniture_button: Button = (
	$MainVBox/CategoryTabs/FurnitureButton
)

@onready var expedition_button: Button = (
	$MainVBox/CategoryTabs/ExpeditionButton
)

@onready var item_grid: GridContainer = (
	$MainVBox/ItemScroll/ItemGrid
)


var inventory_group_button_group: ButtonGroup = (
	ButtonGroup.new()
)

var selected_inventory_group: String = (
	ItemData.INVENTORY_GROUP_SHELF
)


var recipe_scroll_dialog: ConfirmationDialog = null
var pending_scroll_item_id: String = ""

var item_transfer_mode: bool = false
var item_transfer_source: String = "player"
var default_item_grid_columns: int = 1
var minimum_display_rows: int = 3

#==============================================

func _ready() -> void:
	PreservationPanel.install(self)
	default_item_grid_columns = (
		item_grid.columns
	)
	inventory_group_button_group.allow_unpress = false

	var group_buttons: Array[Button] = [
		shelf_button,
		furniture_button,
		expedition_button
	]

	for button in group_buttons:
		button.toggle_mode = true
		button.button_group = (
			inventory_group_button_group
		)

	shelf_button.button_pressed = true

	shelf_button.pressed.connect(
		select_inventory_group.bind(
			ItemData.INVENTORY_GROUP_SHELF
		)
	)

	furniture_button.pressed.connect(
		select_inventory_group.bind(
			ItemData.INVENTORY_GROUP_FURNITURE
		)
	)

	expedition_button.pressed.connect(
		select_inventory_group.bind(
			ItemData.INVENTORY_GROUP_EXPEDITION
		)
	)

	if not GameState.furniture_inventory_changed.is_connected(
		_on_furniture_inventory_changed
	):
		GameState.furniture_inventory_changed.connect(
			_on_furniture_inventory_changed
		)

	refresh_inventory()

	DebugLog.write(
		"[통합 인벤토리] 준비 완료"
	)

func set_item_transfer_mode(
	enabled: bool,
	source_inventory: String = "player"
) -> void:
	item_transfer_mode = enabled

	if source_inventory.is_empty():
		item_transfer_source = "player"
	else:
		item_transfer_source = source_inventory

	if not is_node_ready():
		return

	if item_transfer_mode:
		item_grid.columns = 3
	else:
		item_grid.columns = (
			default_item_grid_columns
		)

	refresh_inventory()

func select_inventory_group(
	inventory_group: String
) -> void:
	if not ItemData.VALID_INVENTORY_GROUPS.has(
		inventory_group
	):
		return

	selected_inventory_group = inventory_group

	refresh_inventory()

	DebugLog.write(
		"[통합 인벤토리] 분류 변경: ",
		selected_inventory_group
	)


func refresh_inventory() -> void:
	clear_item_grid()

	match selected_inventory_group:
		ItemData.INVENTORY_GROUP_FURNITURE:
			refresh_furniture_inventory()

		ItemData.INVENTORY_GROUP_EXPEDITION:
			refresh_expedition_inventory()

		ItemData.INVENTORY_GROUP_SHELF:
			refresh_shelf_inventory()

		_:
			push_warning(
				"[통합 인벤토리] 알 수 없는 분류: "
				+ selected_inventory_group
			)

	# Keep a quiet, regular grid behind the owned items.
	var capacity: int = maxi(item_grid.columns*minimum_display_rows,ceili(float(item_grid.get_child_count())/item_grid.columns)*item_grid.columns)
	while item_grid.get_child_count()<capacity:
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(72,72)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.add_theme_stylebox_override("panel",preload("res://script/ui/common/inventory/inventory_slot_style.gd").box("ddbf8f"))
		item_grid.add_child(empty)

# 창고와 진열대에 있는 판매 상품을 함께 표시한다.
func refresh_shelf_inventory() -> void:
	if item_transfer_mode:
		var stored_item_ids: Array[String] = (
			ItemData.get_items_by_inventory_group(
				ItemData.INVENTORY_GROUP_SHELF
			)
		)

		for item_id in stored_item_ids:
			var stored_count: int = (
				GameState.get_item_count(
					item_id
				)
			)

			if stored_count <= 0:
				continue

			create_item_card(
				item_id,
				stored_count
			)

		return
	var shelf_stock_counts: Dictionary = (
		get_shelf_stock_counts()
	)

	var item_ids: Array[String] = (
		ItemData.get_items_by_inventory_group(
			ItemData.INVENTORY_GROUP_SHELF
		)
	)

	for raw_item_id in shelf_stock_counts.keys():
		var item_id: String = str(
			raw_item_id
		)

		if not item_ids.has(
			item_id
		):
			item_ids.append(
				item_id
			)

	item_ids.sort()

	for item_id in item_ids:
		var stored_count: int = (
			GameState.get_item_count(
				item_id
			)
		)

		var displayed_count: int = int(
			shelf_stock_counts.get(
				item_id,
				0
			)
		)

		if (
			stored_count <= 0
			and displayed_count <= 0
		):
			continue

		create_item_card(
			item_id,
			stored_count,
			displayed_count
		)

# 매장에서는 실제 진열대를 읽고,
# 원정 중에는 저장된 매장 배치를 읽는다.
func get_shelf_stock_counts() -> Dictionary:
	var result: Dictionary = {}

	var live_shelves: Array[Node] = (
		get_tree().get_nodes_in_group(
			"shelf"
		)
	)

	if not live_shelves.is_empty():
		for shelf in live_shelves:
			var slots: Variant = shelf.get(
				"slots"
			)

			if slots is Array:
				add_shelf_slots_to_counts(
					slots,
					result
				)

		return result

	var store_layout: Array[Dictionary] = (
		GameState.get_store_layout()
	)

	for entry in store_layout:
		var slots: Variant = entry.get(
			"shelf_slots",
			[]
		)

		if slots is Array:
			add_shelf_slots_to_counts(
				slots,
				result
			)

	return result


# 슬롯 배열의 상품 수량을 품목별로 합산한다.
func add_shelf_slots_to_counts(
	slots: Array,
	counts: Dictionary
) -> void:
	for raw_slot in slots:
		if not raw_slot is Dictionary:
			continue

		var slot: Dictionary = raw_slot

		var item_id: String = str(
			slot.get(
				"item_id",
				""
			)
		)

		var stock: int = maxi(
			int(
				slot.get(
					"stock",
					0
				)
			),
			0
		)

		if (
			item_id.is_empty()
			or stock <= 0
		):
			continue

		counts[item_id] = (
			int(
				counts.get(
					item_id,
					0
				)
			)
			+ stock
		)

func refresh_furniture_inventory() -> void:
	FurnitureData.ensure_loaded()

	var stored_ids: Array[String] = (
		GameState.get_furniture_inventory_ids()
	)

	var placed_counts: Dictionary = (
		get_placed_furniture_counts()
	)

	# 보관함과 매장 배치 목록의 ID를 합친다.
	var furniture_ids: Array[String] = []

	for furniture_id in stored_ids:
		if not furniture_ids.has(
			furniture_id
		):
			furniture_ids.append(
				furniture_id
			)

	for raw_furniture_id in placed_counts.keys():
		var furniture_id: String = str(
			raw_furniture_id
		)

		if not furniture_ids.has(
			furniture_id
		):
			furniture_ids.append(
				furniture_id
			)

	furniture_ids.sort()

	for furniture_id in furniture_ids:
		if not FurnitureData.has_furniture(
			furniture_id
		):
			continue

		var stored_count: int = (
			GameState.get_furniture_count(
				furniture_id
			)
		)

		var placed_count: int = int(
			placed_counts.get(
				furniture_id,
				0
			)
		)

		if (
			stored_count <= 0
			and placed_count <= 0
		):
			continue

		create_furniture_card(
			furniture_id,
			stored_count,
			placed_count
		)

# 매장과 생산실에 배치된 가구 수량을 종류별로 계산한다.
func get_placed_furniture_counts() -> Dictionary:
	var result: Dictionary = {}

	var store_layout: Array[Dictionary] = (
		GameState.get_store_layout()
	)

	for entry in store_layout:
		var furniture_id: String = str(
			entry.get(
				"build_id",
				""
			)
		)

		if furniture_id.is_empty():
			continue

		result[furniture_id] = (
			int(
				result.get(
					furniture_id,
					0
				)
			)
			+ 1
		)

	return result

func create_furniture_card(
	furniture_id: String,
	stored_count: int,
	placed_count: int
) -> void:
	var card = (
		GameConfig.ITEM_CARD_SCENE.instantiate()
	)

	item_grid.add_child(
		card
	)

	card.setup_furniture(
		furniture_id,
		stored_count,
		placed_count
	)

func get_expedition_bag_placements() -> Array[Dictionary]:
	var current_scene: Node = (
		get_tree().current_scene
	)

	var current_scene_name: String = "없음"

	if is_instance_valid(current_scene):
		current_scene_name = str(
			current_scene.name
		)

	DebugLog.write(
		"[통합 인벤토리 확인] 현재 씬: ",
		current_scene_name
	)

	var has_active_bag_method: bool = (
		is_instance_valid(current_scene)
		and current_scene.has_method(
			"get_active_expedition_bag_placements"
		)
	)

	DebugLog.write(
		"[통합 인벤토리 확인] 실시간 가방 함수 존재: ",
		has_active_bag_method
	)

	if has_active_bag_method:
		var active_placements: Variant = (
			current_scene.call(
				"get_active_expedition_bag_placements"
			)
		)

		DebugLog.write(
			"[통합 인벤토리 확인] 전달받은 데이터: ",
			active_placements
		)

		if active_placements is Array:
			var result: Array[Dictionary] = []

			for placement in active_placements:
				if placement is Dictionary:
					result.append(
						placement.duplicate(true)
					)

			return result

	var saved_placements: Array[Dictionary] = (
		GameState.get_saved_expedition_bag()
	)

	DebugLog.write(
		"[통합 인벤토리 확인] 저장된 가방 사용: ",
		saved_placements
	)

	return saved_placements

func refresh_expedition_inventory() -> void:
	# 일반 원정 아이템을 표시한다.
	var item_ids: Array[String] = (
		ItemData.get_items_by_inventory_group(
			ItemData.INVENTORY_GROUP_EXPEDITION
		)
	)

	for item_id in item_ids:
		var amount: int = (
			GameState.get_item_count(
				item_id
			)
		)

		if amount <= 0:
			continue

		create_item_card(
			item_id,
			amount
		)

	# 보유 장비와 원정 가방에 배치된 장비를 함께 표시한다.
	refresh_owned_equipment_instances()

func refresh_owned_equipment_instances() -> void:
	# 예전 저장 방식의 장비가 남아 있다면
	# 개별 인스턴스로 먼저 변환한다.
	GameState.migrate_legacy_equipment_inventory()

	var displayed_instance_ids: Dictionary = {}

	# =========================
	# 보관함에 있는 장비
	# =========================

	var owned_instances: Array[Dictionary] = (
		GameState.get_owned_equipment_instances()
	)

	for instance_data in owned_instances:
		var instance_id: int = int(
			instance_data.get(
				"instance_id",
				-1
			)
		)

		var item_id: String = str(
			instance_data.get(
				"item_id",
				""
			)
		)

		if instance_id <= 0:
			continue

		if item_id.is_empty():
			continue

		if not ExpeditionEquipmentData.has_equipment(
			item_id
		):
			continue

		displayed_instance_ids[instance_id] = true

		create_equipment_instance_card(
			instance_data,
			"보유 장비"
		)

	# =========================
	# 원정 가방에 배치된 장비
	# =========================

	var bag_placements: Array[Dictionary] = (
		get_expedition_bag_placements()
	)

	for placement in bag_placements:
		var instance_id: int = int(
			placement.get(
				"instance_id",
				-1
			)
		)

		var item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		if instance_id <= 0:
			continue

		if item_id.is_empty():
			continue

		if displayed_instance_ids.has(
			instance_id
		):
			continue

		if not ExpeditionEquipmentData.has_equipment(
			item_id
		):
			continue

		displayed_instance_ids[instance_id] = true

		create_equipment_instance_card(
			placement,
			"원정 가방"
		)


func create_equipment_instance_card(
	instance_data: Dictionary,
	location_text: String
) -> void:
	var card = (
		GameConfig.ITEM_CARD_SCENE.instantiate()
	)

	item_grid.add_child(
		card
	)

	card.setup_equipment_instance(
		instance_data,
		location_text
	)

func create_item_card(
	item_id: String,
	stored_count: int,
	displayed_count: int = 0
) -> void:
	var card: ItemCard = (
		GameConfig.ITEM_CARD_SCENE.instantiate()
		as ItemCard
	)

	if card == null:
		push_error(
			"[통합 인벤토리] ItemCard 생성 실패"
		)
		return

	item_grid.add_child(
		card
	)

	card.setup(
		item_id,
		stored_count,
		displayed_count
	)

	# 레시피 두루마리는 눌러서 사용(습득)한다.
	if (
		not item_transfer_mode
		and stored_count > 0
		and RecipeUnlockData.is_scroll(item_id)
	):
		card.item_selected.connect(
			_on_recipe_scroll_selected
		)

	if (
		item_transfer_mode
		and stored_count > 0
	):
		card.enable_item_drag(
			item_transfer_source,
			stored_count
		)

func _on_recipe_scroll_selected(
	item_id: String
) -> void:
	var recipe_id: String = (
		RecipeUnlockData.get_recipe_id_for_scroll(
			item_id
		)
	)

	if recipe_id.is_empty():
		return

	if recipe_scroll_dialog == null:
		recipe_scroll_dialog = ConfirmationDialog.new()
		recipe_scroll_dialog.title = "레시피 두루마리"
		recipe_scroll_dialog.ok_button_text = "배우기"
		recipe_scroll_dialog.cancel_button_text = "취소"
		recipe_scroll_dialog.confirmed.connect(
			_on_recipe_scroll_confirmed
		)
		add_child(recipe_scroll_dialog)

	pending_scroll_item_id = item_id

	if PlayerProgress.is_recipe_learned(recipe_id):
		recipe_scroll_dialog.dialog_text = (
			"이미 배운 레시피입니다.\n"
			+ "이 두루마리는 사용해도 얻는 것이 없습니다."
		)
		recipe_scroll_dialog.ok_button_text = "확인"
		pending_scroll_item_id = ""
	else:
		recipe_scroll_dialog.dialog_text = (
			"이 두루마리("
			+ ItemData.get_item_name(item_id)
			+ ")를 사용해서 레시피를 배우시겠습니까?\n"
			+ "두루마리 1개가 사라집니다."
		)
		recipe_scroll_dialog.ok_button_text = "배우기"

	recipe_scroll_dialog.popup_centered()


func _on_recipe_scroll_confirmed() -> void:
	if pending_scroll_item_id.is_empty():
		return

	var item_id: String = pending_scroll_item_id
	pending_scroll_item_id = ""

	var recipe_id: String = (
		RecipeUnlockData.get_recipe_id_for_scroll(
			item_id
		)
	)

	if GameState.remove_item(item_id, 1) < 1:
		return

	PlayerProgress.learn_recipe(recipe_id)

	DebugLog.write(
		"[레시피] 습득: ",
		recipe_id
	)

	refresh_inventory()


func clear_item_grid() -> void:
	for child in item_grid.get_children():
		item_grid.remove_child(
			child
		)

		child.queue_free()

func _on_furniture_inventory_changed(
	_furniture_id: String,
	_count: int
) -> void:
	if (
		selected_inventory_group
		!= ItemData.INVENTORY_GROUP_FURNITURE
	):
		return

	refresh_inventory()
