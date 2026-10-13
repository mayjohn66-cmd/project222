extends PanelContainer



const SHELF_SLOT_SCENE: PackedScene = preload(
	"res://scenes/shop/ui/components/shelf_slot_card.tscn"
)

const TRANSFER_SLOT_SCENE: PackedScene = preload(
	"res://scenes/shared/ui/inventory/transfer_inventory_slot.tscn"
)

const WAREHOUSE_BASE_SLOT_COUNT: int = 12
const WAREHOUSE_GRID_COLUMNS: int = 4

const PLAYER_BASE_SLOT_COUNT: int = 12
const PLAYER_GRID_COLUMNS: int = 4

const WAREHOUSE_ACTION_NONE: String = ""
const WAREHOUSE_ACTION_MOVE: String = "move"

const ACTION_MENU_SIZE: Vector2 = Vector2(140, 170)
const ACTION_MENU_MOUSE_OFFSET: Vector2 = Vector2(15, 15)


var warehouse_amount_action: String = (
	WAREHOUSE_ACTION_NONE
)

var warehouse_move_source_slot_index: int = -1
var warehouse_move_selected_amount: int = 0
var warehouse_waiting_for_target: bool = false

# 메인 진열대 UI
@onready var window_title: Label = (
	$WindowBg/TitleBar/TitleLabel
)

@onready var close_button: Button = (
	$WindowBg/TitleBar/CloseButton
)

@onready var shelf_slot_grid: GridContainer = (
	$WindowBg/ContentHBox/ShelfArea/ShelfCenter/ShelfSlotGrid
)

@onready var inventory_grid: GridContainer = (
	$WindowBg/ContentHBox/InventoryArea/InventoryScroll/InventoryGrid
)


# 슬롯 액션 메뉴
@onready var slot_action_panel: PanelContainer = (
	$"../SlotActionPanel"
)

@onready var info_button: Button = (
	$"../SlotActionPanel/VBoxContainer/InfoButton"
)

@onready var restock_button: Button = (
	$"../SlotActionPanel/VBoxContainer/RestockButton"
)

@onready var clear_button: Button = (
	$"../SlotActionPanel/VBoxContainer/ClearButton"
)

@onready var action_close_button: Button = (
	$"../SlotActionPanel/VBoxContainer/ActionCloseButton"
)

@onready var food_tab_button: Button = (
	$WindowBg/ContentHBox/InventoryArea/CategoryTabs/FoodTabButton
)

@onready var consumable_tab_button: Button = (
	$WindowBg/ContentHBox/InventoryArea/CategoryTabs/ConsumableTabButton
)

@onready var material_tab_button: Button = (
	$WindowBg/ContentHBox/InventoryArea/CategoryTabs/MaterialTabButton
)

@onready var tool_tab_button: Button = (
	$WindowBg/ContentHBox/InventoryArea/CategoryTabs/ToolTabButton
)

@onready var etc_tab_button: Button = (
	$WindowBg/ContentHBox/InventoryArea/CategoryTabs/EtcTabButton
)

@onready var restock_panel: PanelContainer = (
	$"../RestockPanel"
)

@onready var restock_info_label: Label = (
	$"../RestockPanel/VBoxContainer/RestockInfoLabel"
)

@onready var minus_button: Button = (
	$"../RestockPanel/VBoxContainer/AmountHBox/MinusButton"
)

@onready var amount_label: Label = (
	$"../RestockPanel/VBoxContainer/AmountHBox/AmountLabel"
)

@onready var plus_button: Button = (
	$"../RestockPanel/VBoxContainer/AmountHBox/PlusButton"
)

@onready var restock_confirm_button: Button = (
	$"../RestockPanel/VBoxContainer/ButtonHBox/ConfirmButton"
)

@onready var restock_cancel_button: Button = (
	$"../RestockPanel/VBoxContainer/ButtonHBox/CancelButton"
)

@onready var restock_close_button: Button = (
	$"../RestockPanel/VBoxContainer/TitleBar/RestockCloseButton"
)

@onready var min_button: Button = (
	$"../RestockPanel/VBoxContainer/AmountHBox/MinButton"
)

@onready var max_button: Button = (
	$"../RestockPanel/VBoxContainer/AmountHBox/MaxButton"
)

@onready var item_info_dialog: AcceptDialog = (
	$"../ItemInfoDialog"
)

enum PanelMode {
	SHELF,
	WAREHOUSE
}

# =========================================================
# 현재 상태
# =========================================================

var current_shelf = null
var current_player = null

var current_mode: PanelMode = (
	PanelMode.SHELF
)

var current_warehouse_storage: Node = null

var restock_slot_index: int = -1
var restock_amount: int = 1
var restock_max_amount: int = 0

# 빈 슬롯을 선택했을 때 사용
var selected_slot_index: int = -1

# 상품이 들어있는 슬롯의 액션 메뉴용
var action_slot_index: int = -1
var selected_category: String = "food"

# 창고 아이템 이동 수량 선택용
var pending_transfer_data: Dictionary = {}
var pending_transfer_target_side: String = ""
var pending_transfer_target_slot_index: int = -1

# =========================================================
# 시작
# =========================================================

func _ready():
	visible = false
	slot_action_panel.visible = false
	add_child(ShelfWindowPriority.new())

	close_button.pressed.connect(close)

	info_button.pressed.connect(show_item_info)
	restock_button.pressed.connect(open_restock_panel)
	clear_button.pressed.connect(clear_action_slot)
	action_close_button.pressed.connect(close_action_menu)

	food_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_FOOD
		)
	)

	consumable_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_CONSUMABLE
		)
	)

	material_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_MATERIAL
		)
	)

	tool_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_TOOL
		)
	)

	etc_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_ETC
		)
	)

	restock_panel.visible = false

	minus_button.pressed.connect(
		decrease_restock_amount
	)

	plus_button.pressed.connect(
		increase_restock_amount
	)

	restock_confirm_button.pressed.connect(
		confirm_restock
	)

	restock_cancel_button.pressed.connect(
		close_restock_panel
	)

	min_button.pressed.connect(
		set_restock_min
	)

	max_button.pressed.connect(
		set_restock_max
	)

	if not restock_close_button.pressed.is_connected(
		close_restock_panel
	):
		restock_close_button.pressed.connect(
			close_restock_panel
		)


func select_category(category: String):
	selected_category = category

	DebugLog.write(
		"상품 카테고리 선택: ",
		selected_category
	)

	refresh_inventory_slots()

# =========================================================
# 창 열기 / 닫기
# =========================================================

func open(shelf, player):
	if not is_instance_valid(shelf):
		return

	if not is_instance_valid(player):
		return

	current_mode = PanelMode.SHELF
	current_warehouse_storage = null

	# 이전 진열대의 메뉴와 보충 상태 정리
	close_action_menu()
	close_restock_panel()

	selected_slot_index = -1

	current_shelf = shelf
	current_player = player

	visible = true
	refresh_ui()

func open_warehouse(
	storage: Node,
	player: Node
) -> void:
	if not is_instance_valid(storage):
		return

	if storage.is_queued_for_deletion():
		return

	if not is_instance_valid(player):
		return

	close_action_menu()
	close_restock_panel()

	selected_slot_index = -1
	action_slot_index = -1

	current_mode = PanelMode.WAREHOUSE
	current_shelf = null
	current_warehouse_storage = storage
	current_player = player

	window_title.text = "창고 선반"

	# 창고 좌측 슬롯은 다음 단계에서 생성한다.
	clear_container(
		shelf_slot_grid
	)

	visible = true

	refresh_ui()

func close():
	close_action_menu()
	close_restock_panel()

	visible = false

	current_shelf = null
	current_warehouse_storage = null
	current_player = null

	current_mode = PanelMode.SHELF

	selected_slot_index = -1
	action_slot_index = -1


# =========================================================
# 전체 UI 갱신
# =========================================================

func refresh_ui() -> void:
	match current_mode:
		PanelMode.SHELF:
			refresh_shelf_slots()

		PanelMode.WAREHOUSE:
			refresh_warehouse_slots()

	refresh_inventory_slots()


func refresh_warehouse_slots() -> void:
	clear_container(
		shelf_slot_grid
	)

	if not is_instance_valid(
		current_warehouse_storage
	):
		return

	shelf_slot_grid.columns = (
		WAREHOUSE_GRID_COLUMNS
	)

	var storage_slots: Array[Dictionary] = (
		current_warehouse_storage.get_storage_slots()
	)

	var visible_slot_count: int = maxi(
		WAREHOUSE_BASE_SLOT_COUNT,
		storage_slots.size()
	)

	for slot_index in range(
		visible_slot_count
	):
		var item_id: String = ""
		var amount: int = 0

		if slot_index < storage_slots.size():
			var slot_data: Dictionary = (
				storage_slots[
					slot_index
				]
			)

			item_id = str(
				slot_data.get(
					"item_id",
					""
				)
			)

			amount = maxi(
				int(
					slot_data.get(
						"amount",
						0
					)
				),
				0
			)

		_create_transfer_slot(
			shelf_slot_grid,
			slot_index,
			"container",
			item_id,
			amount,
			true
		)

	refresh_warehouse_title()

func _on_warehouse_slot_pressed(
	slot_index: int
) -> void:
	if current_mode != PanelMode.WAREHOUSE:
		return

	if restock_panel.visible:
		return

	if not is_instance_valid(
		current_warehouse_storage
	):
		return

	if warehouse_waiting_for_target:
		complete_warehouse_manual_move(
			slot_index
		)
		return

	var item_id: String = (
		current_warehouse_storage
		.get_slot_item_id(
			slot_index
		)
	)
	var amount: int = (
		current_warehouse_storage
		.get_slot_item_count(
			slot_index
		)
	)

	# 빈 슬롯을 단순 클릭했을 때는 아무것도 열지 않는다.
	if (
		item_id.is_empty()
		or amount <= 0
	):
		return

	open_warehouse_action_menu(
		slot_index
	)

func complete_warehouse_manual_move(
	target_slot_index: int
) -> void:
	if not warehouse_waiting_for_target:
		return

	if not is_instance_valid(
		current_warehouse_storage
	):
		cancel_warehouse_move_selection()
		return

	var source_slot_index: int = (
		warehouse_move_source_slot_index
	)

	if target_slot_index == source_slot_index:
		DebugLog.write(
			"[창고 옮기기] 원본과 같은 슬롯입니다."
		)
		return

	var source_item_id: String = (
		current_warehouse_storage
		.get_slot_item_id(
			source_slot_index
		)
	)

	var target_item_id: String = (
		current_warehouse_storage
		.get_slot_item_id(
			target_slot_index
		)
	)

	if source_item_id.is_empty():
		cancel_warehouse_move_selection()
		return

	# 일부 수량 옮기기에서는 빈 슬롯이나
	# 같은 아이템 슬롯만 선택할 수 있다.
	if (
		not target_item_id.is_empty()
		and target_item_id != source_item_id
	):
		DebugLog.write(
			"[창고 옮기기] 다른 아이템 슬롯에는 일부 수량을 옮길 수 없습니다."
		)
		return

	var moved_amount: int = (
		current_warehouse_storage
		.move_item_between_slots(
			source_slot_index,
			target_slot_index,
			warehouse_move_selected_amount
		)
	)

	if moved_amount <= 0:
		DebugLog.write(
			"[창고 옮기기] 이동하지 못했습니다."
		)
		return

	DebugLog.write(
		"[창고 옮기기] 완료 / ",
		source_slot_index,
		" → ",
		target_slot_index,
		" / ",
		source_item_id,
		" ×",
		moved_amount
	)

	cancel_warehouse_move_selection()
	refresh_ui()

func cancel_warehouse_move_selection() -> void:
	warehouse_amount_action = (
		WAREHOUSE_ACTION_NONE
	)

	warehouse_move_source_slot_index = -1
	warehouse_move_selected_amount = 0
	warehouse_waiting_for_target = false

	if (
		current_mode == PanelMode.WAREHOUSE
		and is_instance_valid(
			current_warehouse_storage
		)
	):
		refresh_warehouse_title()

func open_warehouse_action_menu(
	slot_index: int
) -> void:
	if current_mode != PanelMode.WAREHOUSE:
		return

	if not is_instance_valid(
		current_warehouse_storage
	):
		return

	var item_id: String = (
		current_warehouse_storage
		.get_slot_item_id(
			slot_index
		)
	)

	if item_id.is_empty():
		return

	action_slot_index = slot_index
	selected_slot_index = -1

	_show_action_menu(
		"정보보기",
		"옮기기",
		"빼기",
		ShelfWindowPriority.ACTION_Z
	)

func refresh_warehouse_title() -> void:
	if not is_instance_valid(
		current_warehouse_storage
	):
		window_title.text = "창고 선반"
		return

	var stored_amount: int = 0
	var capacity: int = int(
		current_warehouse_storage.get(
			"storage_capacity"
		)
	)

	if current_warehouse_storage.has_method(
		"get_total_stored_amount"
	):
		stored_amount = int(
			current_warehouse_storage.call(
				"get_total_stored_amount"
			)
		)

	window_title.text = (
		"창고 선반 · %d / %d"
		% [
			stored_amount,
			capacity
		]
	)

# =========================================================
# 진열대 슬롯
# =========================================================

func refresh_shelf_slots():
	clear_container(shelf_slot_grid)

	if current_shelf == null:
		return

	shelf_slot_grid.columns = max(
		1,
		int(current_shelf.slots_per_level)
	)

	window_title.text = (
		"진열대 "
		+ str(current_shelf.stack_level)
		+ "단"
)

	for slot_index in range(current_shelf.slots.size()):
		create_shelf_slot(slot_index)

func create_shelf_slot(
	slot_index: int
):
	var card: ShelfSlotCard = (
		SHELF_SLOT_SCENE.instantiate()
		as ShelfSlotCard
	)

	if card == null:
		push_error("[진열대 UI] 슬롯 카드 생성 실패")
		return

	shelf_slot_grid.add_child(card)
	card.setup(
		slot_index,
		current_shelf.slots[slot_index],
		selected_slot_index == slot_index
	)
	card.slot_selected.connect(
		_on_shelf_slot_pressed
	)


func _on_shelf_slot_pressed(slot_index: int):
	if current_shelf == null:
		return

	if restock_panel.visible:
		return

	if slot_index < 0:
		return

	if slot_index >= current_shelf.slots.size():
		return

	var slot: Dictionary = current_shelf.slots[
		slot_index
	]

	var item_id: String = str(
		slot.get("item_id", "")
	)

	# 상품이 들어있는 슬롯
	if not item_id.is_empty():
		open_action_menu(slot_index)
		return

	# 이미 선택한 빈 슬롯을 다시 클릭
	# → 선택 취소
	if selected_slot_index == slot_index:
		selected_slot_index = -1

		DebugLog.write("진열 슬롯 선택 취소")

		refresh_shelf_slots()
		return

	# 다른 빈 슬롯 선택
	close_action_menu()

	selected_slot_index = slot_index

	DebugLog.write(
		"빈 슬롯 선택: ",
		selected_slot_index
	)

	refresh_shelf_slots()


# =========================================================
# 플레이어 보유 상품
# =========================================================

func refresh_inventory_slots():
	clear_container(inventory_grid)

	if current_player == null:
		return

	if current_mode == PanelMode.WAREHOUSE:
		refresh_warehouse_player_slots()
		return

	inventory_grid.columns = 3

	var item_ids: Array[String] = (
		ItemData.get_items_by_category(
			selected_category
		)
	)

	for item_id in item_ids:
		var count: int = current_player.get_item_count(
			item_id
		)

		if count <= 0:
			continue

		create_inventory_slot(
			item_id,
			count
		)

func refresh_warehouse_player_slots() -> void:
	inventory_grid.columns = (
		PLAYER_GRID_COLUMNS
	)

	var category_item_ids: Array[String] = (
		ItemData.get_items_by_category(
			selected_category
		)
	)

	var owned_item_ids: Array[String] = []

	for item_id in category_item_ids:
		var count: int = (
			current_player.get_item_count(
				item_id
			)
		)

		if count <= 0:
			continue

		owned_item_ids.append(
			item_id
		)

	owned_item_ids.sort()

	var displayed_slot_count: int = maxi(
		PLAYER_BASE_SLOT_COUNT,
		owned_item_ids.size()
	)

	for slot_index in range(
		displayed_slot_count
	):
		if slot_index < owned_item_ids.size():
			var item_id: String = (
				owned_item_ids[slot_index]
			)

			var count: int = (
				current_player.get_item_count(
					item_id
				)
			)

			_create_transfer_slot(
				inventory_grid,
				slot_index,
				"player",
				item_id,
				count
			)
		else:
			_create_transfer_slot(
				inventory_grid,
				slot_index,
				"player"
			)


func _create_transfer_slot(
	parent: Container,
	slot_index: int,
	side: String,
	item_id: String = "",
	amount: int = 0,
	clickable: bool = false
) -> TransferInventorySlot:
	var slot: TransferInventorySlot = (
		TRANSFER_SLOT_SCENE.instantiate()
		as TransferInventorySlot
	)

	if slot == null:
		push_error("[창고 UI] 이동 슬롯 생성 실패")
		return null

	parent.add_child(slot)
	slot.configure_slot(
		slot_index,
		side,
		item_id,
		amount
	)
	slot.item_drop_received.connect(
		_on_transfer_slot_drop
	)

	if clickable:
		slot.pressed.connect(
			_on_warehouse_slot_pressed.bind(slot_index)
		)

	return slot

func _on_transfer_slot_drop(
	drag_data: Dictionary,
	target_side: String,
	target_slot_index: int
) -> void:
	if current_mode != PanelMode.WAREHOUSE:
		return

	if restock_panel.visible:
		return

	if not is_instance_valid(
		current_warehouse_storage
	):
		return

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

	var item_id: String = str(
		drag_data.get(
			"item_id",
			""
		)
	)

	var amount: int = maxi(
		int(
			drag_data.get(
				"amount",
				0
			)
		),
		0
	)

	if item_id.is_empty():
		return

	if amount <= 0:
		return

	# 플레이어 인벤토리 내부 재배치는 지원하지 않는다.
	if (
		source_side == "player"
		and target_side == "player"
	):
		return

	# ========================================
	# 창고 내부 드래그
	# 전체 묶음을 즉시 정리한다.
	# ========================================

	if (
		source_side == "container"
		and target_side == "container"
	):
		if source_slot_index == target_slot_index:
			return

		var moved_amount: int = (
			current_warehouse_storage
			.move_item_between_slots(
				source_slot_index,
				target_slot_index,
				amount
			)
		)

		if moved_amount <= 0:
			DebugLog.write(
				"[창고 정리] 이동 실패 / ",
				source_slot_index,
				" → ",
				target_slot_index
			)
			return

		DebugLog.write(
			"[창고 정리] 전체 묶음 이동 / ",
			item_id,
			" ×",
			amount,
			" / ",
			source_slot_index,
			" → ",
			target_slot_index
		)

		refresh_ui()
		return

	# ========================================
	# 플레이어 ↔ 창고
	# 수량을 선택한 후 이동한다.
	# ========================================

	open_warehouse_transfer_amount_panel(
		drag_data,
		target_side,
		target_slot_index
	)

func open_warehouse_transfer_amount_panel(
	drag_data: Dictionary,
	target_side: String,
	target_slot_index: int
) -> void:
	if not is_instance_valid(
		current_warehouse_storage
	):
		return

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

	var item_id: String = str(
		drag_data.get(
			"item_id",
			""
		)
	)

	var source_amount: int = maxi(
		int(
			drag_data.get(
				"amount",
				0
			)
		),
		0
	)

	if item_id.is_empty():
		return

	if source_amount <= 0:
		return

	var maximum_amount: int = 0

	# 플레이어 → 창고
	if (
		source_side == "player"
		and target_side == "container"
	):
		maximum_amount = (
			current_warehouse_storage
			.get_max_deposit_amount_for_slot(
				target_slot_index,
				item_id
			)
		)

	# 창고 → 플레이어
	elif (
		source_side == "container"
		and target_side == "player"
	):
		maximum_amount = mini(
			source_amount,
			current_warehouse_storage
			.get_slot_item_count(
				source_slot_index
			)
		)

	# 창고 슬롯 → 다른 창고 슬롯
	elif (
		source_side == "container"
		and target_side == "container"
	):
		maximum_amount = (
			current_warehouse_storage
			.get_max_move_amount_between_slots(
				source_slot_index,
				target_slot_index
			)
		)

	else:
		return

	if maximum_amount <= 0:
		DebugLog.write(
			"[창고 이동] 이동 가능한 수량이 없습니다: ",
			item_id
		)
		return

	pending_transfer_data = (
		drag_data.duplicate(true)
	)

	pending_transfer_target_side = (
		target_side
	)

	pending_transfer_target_slot_index = (
		target_slot_index
	)

	restock_amount = 1
	restock_max_amount = maximum_amount

	var direction_text: String = ""

	if (
		source_side == "container"
		and target_side == "container"
	):
		var target_item_id: String = (
			current_warehouse_storage
			.get_slot_item_id(
				target_slot_index
			)
		)

		if target_item_id == item_id:
			direction_text = "같은 아이템 합치기"
		else:
			direction_text = "창고 슬롯 위치 변경"

	elif target_side == "container":
		direction_text = "창고에 보관"

	else:
		direction_text = (
			"플레이어 인벤토리로 꺼내기"
		)

	restock_info_label.text = (
		ItemData.get_item_name(
			item_id
		)
		+ "\n"
		+ direction_text
		+ "\n몇 개를 이동하시겠습니까?"
	)

	restock_panel.visible = true
	restock_panel.z_index = ShelfWindowPriority.AMOUNT_Z

	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	restock_panel.position = (
		viewport_size * 0.5
		- restock_panel.size * 0.5
	)

	update_restock_amount_ui()

func create_inventory_slot(
	item_id: String,
	count: int
):
	if count <= 0:
		return

	var card := (
		GameConfig.ITEM_CARD_SCENE.instantiate()
		as ItemCard
	)

	if card == null:
		return

	inventory_grid.add_child(
		card
	)

	card.setup(
		item_id,
		count
	)

	card.item_selected.connect(
		_on_inventory_item_pressed
	)


func _on_inventory_item_pressed(
	item_id: String
) -> void:
	if restock_panel.visible:
		return

	if not is_instance_valid(current_shelf):
		return

	if not is_instance_valid(current_player):
		return

	if selected_slot_index < 0:
		DebugLog.write("먼저 빈 진열 슬롯을 선택하세요.")
		return

	if selected_slot_index >= current_shelf.slots.size():
		return

	if not ItemData.has_item(item_id):
		return


	# 상품 데이터에서 진열을 허용한 아이템만 지정
	if not ItemData.is_shelf_allowed(item_id):
		DebugLog.write(
			"[진열대] 진열할 수 없는 아이템: ",
			item_id
		)
		return

	if current_player.get_item_count(item_id) <= 0:
		return

	var slot: Dictionary = (
		current_shelf.slots[selected_slot_index]
	)

	if not str(slot.get("item_id", "")).is_empty():
		return

	# 상품 종류만 지정하고 실제 수량은 보충할 때 이동
	slot["item_id"] = item_id
	slot["stock"] = 0

	current_shelf.slots[selected_slot_index] = slot
	current_shelf.update_stock_label()

	DebugLog.write(
		"상품 지정: 슬롯 ",
		selected_slot_index,
		" → ",
		item_id
	)

	selected_slot_index = -1
	refresh_ui()


# =========================================================
# 슬롯 액션 메뉴
# =========================================================

func open_action_menu(slot_index: int):
	if current_shelf == null:
		return

	if slot_index < 0:
		return

	if slot_index >= current_shelf.slots.size():
		return

	var slot: Dictionary = current_shelf.slots[
		slot_index
	]

	var item_id: String = str(
		slot.get("item_id", "")
	)

	if item_id.is_empty():
		return

	action_slot_index = slot_index

	selected_slot_index = -1
	refresh_shelf_slots()

	_show_action_menu(
		"정보보기",
		"보충하기",
		"비우기",
		ShelfWindowPriority.ACTION_Z
	)


func _show_action_menu(
	info_text: String,
	primary_text: String,
	secondary_text: String,
	menu_z_index: int
) -> void:
	info_button.text = info_text
	restock_button.text = primary_text
	clear_button.text = secondary_text
	action_close_button.text = "닫기"

	slot_action_panel.custom_minimum_size = ACTION_MENU_SIZE
	slot_action_panel.size = ACTION_MENU_SIZE
	slot_action_panel.z_index = menu_z_index

	var popup_position: Vector2 = (
		get_viewport().get_mouse_position()
		+ ACTION_MENU_MOUSE_OFFSET
	)
	var viewport_size: Vector2 = get_viewport_rect().size

	popup_position.x = clampf(
		popup_position.x,
		0.0,
		viewport_size.x - ACTION_MENU_SIZE.x
	)
	popup_position.y = clampf(
		popup_position.y,
		0.0,
		viewport_size.y - ACTION_MENU_SIZE.y
	)

	slot_action_panel.global_position = popup_position
	slot_action_panel.visible = true
	ShelfWindowPriority.fit_action_popup.call_deferred(slot_action_panel, ACTION_MENU_SIZE)


func close_action_menu():
	slot_action_panel.visible = false
	action_slot_index = -1


# =========================================================
# 비우기
# =========================================================

func clear_action_slot():
	FoodShelfLife.settle()
	if current_mode == PanelMode.WAREHOUSE:
		open_warehouse_withdraw_panel()
		return

	if current_shelf == null:
		return

	if current_player == null:
		return

	if action_slot_index < 0:
		return

	if action_slot_index >= current_shelf.slots.size():
		return

	var slot: Dictionary = current_shelf.slots[
		action_slot_index
	]

	var item_id: String = str(
		slot.get("item_id", "")
	)

	if item_id.is_empty():
		return

	if not ItemData.has_item(item_id):
		push_warning(
			"[진열대] 상품 데이터가 없어 비우기 중단: "
			+ item_id
		)
		return


	var stock: int = int(
		slot.get("stock", 0)
	)

	# 남아 있는 상품은 플레이어에게 반환
	if stock > 0:
		if FoodShelfLife.tracked(item_id):
			GameState.add_item(item_id, stock, FoodShelfLife.take(FoodShelfLife.slot_batches(slot), stock))
		else:
			current_player.add_item(item_id, stock)

	# 슬롯 초기화
	slot["item_id"] = ""
	slot["stock"] = 0
	slot.erase("food_batches")

	current_shelf.slots[
		action_slot_index
	] = slot

	DebugLog.write(
		"진열 슬롯 비우기: ",
		item_id,
		" / 반환 ",
		stock
	)

	current_shelf.slots[
		action_slot_index
	] = slot

	current_shelf.update_stock_label()

	selected_slot_index = -1

	refresh_ui()
	close_action_menu()


# =============================
# 창고에서 꺼내기
# =============================

func open_warehouse_withdraw_panel() -> void:
	if current_mode != PanelMode.WAREHOUSE:
		return

	if not is_instance_valid(
		current_warehouse_storage
	):
		return

	if action_slot_index < 0:
		return

	var source_slot_index: int = (
		action_slot_index
	)

	var item_id: String = (
		current_warehouse_storage
		.get_slot_item_id(
			source_slot_index
		)
	)

	var amount: int = (
		current_warehouse_storage
		.get_slot_item_count(
			source_slot_index
		)
	)

	if item_id.is_empty():
		return

	if amount <= 0:
		return

	var drag_data: Dictionary = {
		"type": "item_transfer_slot",
		"source_side": "container",
		"source_slot_index": source_slot_index,
		"item_id": item_id,
		"amount": amount
	}

	# action_slot_index가 초기화되기 전에
	# drag_data에 슬롯 번호를 저장했다.
	close_action_menu()

	open_warehouse_transfer_amount_panel(
		drag_data,
		"player",
		-1
	)

# =========================================================
# 상품 정보
# =========================================================

func show_item_info() -> void:
	if current_mode == PanelMode.WAREHOUSE:
		show_warehouse_item_info()
		return

	if not is_instance_valid(current_shelf):
		return

	if action_slot_index < 0:
		return

	if action_slot_index >= current_shelf.slots.size():
		return

	var slot: Dictionary = (
		current_shelf.slots[action_slot_index]
	)

	var item_id: String = str(
		slot.get(
			"item_id",
			""
		)
	)

	if item_id.is_empty():
		return

	var item_data: Dictionary = (
		ItemData.get_item(
			item_id
		)
	)

	if item_data.is_empty():
		push_warning(
			"[진열대] 상품 정보 없음: "
			+ item_id
		)
		return

	var item_name: String = str(
		item_data.get(
			"name",
			item_id
		)
	)

	var description: String = str(
		item_data.get(
			"description",
			""
		)
	)

	if description.is_empty():
		description = "상품 설명이 없습니다."

	var price: int = int(
		item_data.get(
			"price",
			0
		)
	)

	var stock: int = int(
		slot.get(
			"stock",
			0
		)
	)

	var capacity: int = int(
		slot.get(
			"capacity",
			0
		)
	)

	var dialog_text: String = (
		item_name
		+ "\n\n"
		+ description
		+ "\n\n판매 가격: "
		+ str(price)
		+ "G"
		+ "\n진열 수량: "
		+ str(stock)
		+ " / "
		+ str(capacity)
	)

	close_action_menu()
	_show_item_info_dialog(
		"상품 정보",
		dialog_text,
		Vector2i(420, 280)
	)


# ============================================
# 창고 아이템 정보 함수
# ============================================

func show_warehouse_item_info() -> void:
	if current_mode != PanelMode.WAREHOUSE:
		return

	if not is_instance_valid(
		current_warehouse_storage
	):
		return

	if action_slot_index < 0:
		return

	var item_id: String = (
		current_warehouse_storage
		.get_slot_item_id(
			action_slot_index
		)
	)

	var amount: int = (
		current_warehouse_storage
		.get_slot_item_count(
			action_slot_index
		)
	)

	if item_id.is_empty():
		return

	if amount <= 0:
		return

	var item_data: Dictionary = (
		ItemData.get_item(
			item_id
		)
	)

	if item_data.is_empty():
		push_warning(
			"[창고 정보] 아이템 데이터 없음: "
			+ item_id
		)
		return

	var item_name: String = (
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

	if description.is_empty():
		description = (
			"등록된 설명이 없습니다."
		)

	var price: int = int(
		item_data.get(
			"price",
			0
		)
	)

	var sellable: bool = bool(
		item_data.get(
			"sellable",
			false
		)
	)

	var sell_text: String = "판매 불가"

	if sellable:
		sell_text = (
			"판매 가격: "
			+ str(price)
			+ "G"
		)

	var dialog_text: String = (
		item_name
		+ "\n\n"
		+ description
		+ "\n\n창고 수량: "
		+ str(amount)
		+ "\n슬롯 번호: "
		+ str(action_slot_index + 1)
		+ "\n"
		+ sell_text
	)

	close_action_menu()
	_show_item_info_dialog(
		"아이템 정보",
		dialog_text,
		Vector2i(420, 300)
	)


func _show_item_info_dialog(
	title_text: String,
	dialog_text: String,
	dialog_size: Vector2i
) -> void:
	item_info_dialog.title = title_text
	item_info_dialog.dialog_text = dialog_text
	item_info_dialog.popup_centered(dialog_size)

# =========================================================
# Container 내부 동적 UI 삭제
# =========================================================

func clear_container(container: Container):
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# =========================================================
# ESC
# =========================================================

func _input(event):
	if not visible:
		return
	# 진열대 조작 중에는 수첩을 겹쳐 열지 않는다.
	if event.is_action_pressed("management_menu"):
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		# 액션 메뉴가 열려 있으면 액션 메뉴만 닫기

		if warehouse_waiting_for_target:
			cancel_warehouse_move_selection()
			get_viewport().set_input_as_handled()
			return

		if restock_panel.visible:
			close_restock_panel()
			get_viewport().set_input_as_handled()
			return
		
		if slot_action_panel.visible:
			close_action_menu()
			get_viewport().set_input_as_handled()
			return

		# 액션 메뉴가 없으면 진열대 창 전체 닫기
		close()
		get_viewport().set_input_as_handled()


func open_warehouse_move_amount_panel() -> void:
	if current_mode != PanelMode.WAREHOUSE:
		return

	if not is_instance_valid(
		current_warehouse_storage
	):
		return

	if action_slot_index < 0:
		return

	var source_slot_index: int = (
		action_slot_index
	)

	var item_id: String = (
		current_warehouse_storage
		.get_slot_item_id(
			source_slot_index
		)
	)

	var amount: int = (
		current_warehouse_storage
		.get_slot_item_count(
			source_slot_index
		)
	)

	if item_id.is_empty():
		return

	if amount <= 0:
		return

	warehouse_amount_action = (
		WAREHOUSE_ACTION_MOVE
	)

	warehouse_move_source_slot_index = (
		source_slot_index
	)

	warehouse_move_selected_amount = 0
	warehouse_waiting_for_target = false

	restock_amount = 1
	restock_max_amount = amount

	restock_info_label.text = (
		ItemData.get_item_name(
			item_id
		)
		+ "\n옮길 수량을 선택해주세요."
	)

	# 원본 슬롯 번호를 저장한 뒤 메뉴를 닫는다.
	close_action_menu()

	restock_panel.visible = true
	restock_panel.z_index = ShelfWindowPriority.AMOUNT_Z

	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	restock_panel.position = (
		viewport_size * 0.5
		- restock_panel.size * 0.5
	)

	update_restock_amount_ui()

func open_restock_panel():
	if current_mode == PanelMode.WAREHOUSE:
		open_warehouse_move_amount_panel()
		return

	if current_shelf == null:
		return

	if current_player == null:
		return

	if action_slot_index < 0:
		return

	if action_slot_index >= current_shelf.slots.size():
		return

	var slot: Dictionary = (
		current_shelf.slots[action_slot_index]
	)

	var item_id: String = str(
		slot.get("item_id", "")
	)

	if item_id.is_empty():
		return

	var stock: int = int(
		slot.get("stock", 0)
	)

	var capacity: int = int(
		slot.get("capacity", 0)
	)

	var player_count: int = (
		current_player.get_item_count(
			item_id
		)
	)

	var empty_space: int = (
		capacity - stock
	)

	restock_max_amount = min(
		empty_space,
		player_count
	)

	if restock_max_amount <= 0:
		DebugLog.write("보충 가능한 상품이 없습니다.")
		return

	# 액션 메뉴의 슬롯 번호를 따로 보관
	restock_slot_index = action_slot_index

	restock_amount = 1

	restock_info_label.text = (
		"몇 개를 보충하시겠습니까?"
	)

	restock_panel.visible = true
	restock_panel.z_index = ShelfWindowPriority.AMOUNT_Z

	# 화면 중앙 근처에 표시
	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	restock_panel.position = (
		viewport_size * 0.5
		- Vector2(90, 80)
	)

	update_restock_amount_ui()

	# 이것은 action_slot_index를 -1로 만들기 때문에
	# restock_slot_index에 먼저 저장한 뒤 호출
	close_action_menu()

func decrease_restock_amount():
	restock_amount = max(
		1,
		restock_amount - 1
	)

	update_restock_amount_ui()


func increase_restock_amount():
	restock_amount = min(
		restock_max_amount,
		restock_amount + 1
	)

	update_restock_amount_ui()


func update_restock_amount_ui():
	amount_label.text = str(
		restock_amount
	)

	minus_button.disabled = (
		restock_amount <= 1
	)

	plus_button.disabled = (
		restock_amount >= restock_max_amount
	)

	min_button.disabled = (
		restock_amount <= 1
	)

	max_button.disabled = (
		restock_amount >= restock_max_amount
	)

func confirm_restock():
	FoodShelfLife.settle()
	if current_mode == PanelMode.WAREHOUSE:
		confirm_warehouse_transfer()
		return

	if current_shelf == null:
		return

	if current_player == null:
		return

	if restock_slot_index < 0:
		return

	if (
		restock_slot_index
		>= current_shelf.slots.size()
	):
		return

	var slot: Dictionary = (
		current_shelf.slots[
			restock_slot_index
		]
	)

	var item_id: String = str(
		slot.get("item_id", "")
	)

	if item_id.is_empty():
		return

	var available: int = (
		current_player.get_item_count(
			item_id
		)
	)

	var stock: int = int(
		slot.get("stock", 0)
	)

	var capacity: int = int(
		slot.get("capacity", 0)
	)

	var empty_space: int = (
		capacity - stock
	)

	var amount: int = min(
		restock_amount,
		available,
		empty_space
	)

	if amount <= 0:
		close_restock_panel()
		return

	var food_batches := FoodShelfLife.peek_inventory(item_id, amount) if FoodShelfLife.tracked(item_id) else []
	var removed: int = (
		current_player.remove_item(
			item_id,
			amount
		)
	)

	if removed <= 0:
		return

	var added: int = (
		current_shelf.add_stock_to_slot(
			restock_slot_index,
			removed,
			food_batches
		)
	)

	# 예상보다 적게 들어간 경우 반환
	if added < removed:
		if FoodShelfLife.tracked(item_id):
			FoodShelfLife.take(food_batches, added)
			GameState.add_item(item_id, removed - added, food_batches)
		else:
			current_player.add_item(item_id, removed - added)

	DebugLog.write(
		"수동 보충 완료: ",
		item_id,
		" +",
		added
	)

	refresh_ui()
	close_restock_panel()

func confirm_warehouse_transfer() -> void:
	if not is_instance_valid(
		current_warehouse_storage
	):
		close_restock_panel()
		return

	# 창고 메뉴의 '옮기기' 수량 확인
	if (
		warehouse_amount_action
		== WAREHOUSE_ACTION_MOVE
	):
		confirm_warehouse_move_amount()
		return

	if pending_transfer_data.is_empty():
		close_restock_panel()
		return

	var source_side: String = str(
		pending_transfer_data.get(
			"source_side",
			""
		)
	)

	var source_slot_index: int = int(
		pending_transfer_data.get(
			"source_slot_index",
			-1
		)
	)

	var item_id: String = str(
		pending_transfer_data.get(
			"item_id",
			""
		)
	)

	var requested_amount: int = clampi(
		restock_amount,
		1,
		restock_max_amount
	)

	var moved_amount: int = 0

	# 플레이어 → 창고
	if (
		source_side == "player"
		and pending_transfer_target_side == "container"
	):
		moved_amount = (
			current_warehouse_storage
			.deposit_from_inventory_to_slot(
				pending_transfer_target_slot_index,
				item_id,
				requested_amount
			)
		)

	# 창고 → 플레이어
	elif (
		source_side == "container"
		and pending_transfer_target_side == "player"
	):
		moved_amount = (
			current_warehouse_storage
			.withdraw_slot_to_inventory(
				source_slot_index,
				requested_amount
			)
		)

	# 창고 슬롯 → 다른 창고 슬롯
	elif (
		source_side == "container"
		and pending_transfer_target_side == "container"
	):
		moved_amount = (
			current_warehouse_storage
			.move_item_between_slots(
				source_slot_index,
				pending_transfer_target_slot_index,
				requested_amount
			)
		)

	if moved_amount > 0:
		DebugLog.write(
			"[창고 이동] ",
			item_id,
			" ×",
			moved_amount,
			" / ",
			source_side,
			" → ",
			pending_transfer_target_side,
			" / 대상 슬롯: ",
			pending_transfer_target_slot_index
		)
	else:
		DebugLog.write(
			"[창고 이동] 이동 실패 / ",
			item_id
		)

	close_restock_panel()
	refresh_ui()

func confirm_warehouse_move_amount() -> void:
	if not is_instance_valid(
		current_warehouse_storage
	):
		close_restock_panel()
		return

	if warehouse_move_source_slot_index < 0:
		close_restock_panel()
		return

	var source_amount: int = (
		current_warehouse_storage
		.get_slot_item_count(
			warehouse_move_source_slot_index
		)
	)

	if source_amount <= 0:
		close_restock_panel()
		return

	var selected_amount: int = clampi(
		restock_amount,
		1,
		source_amount
	)

	warehouse_move_selected_amount = (
		selected_amount
	)

	warehouse_waiting_for_target = true
	warehouse_amount_action = (
		WAREHOUSE_ACTION_NONE
	)

	# close_restock_panel()을 호출하면 이동 상태까지
	# 초기화될 수 있으므로 창만 직접 닫는다.
	restock_panel.visible = false

	restock_amount = 1
	restock_max_amount = 0

	pending_transfer_data.clear()
	pending_transfer_target_side = ""
	pending_transfer_target_slot_index = -1

	window_title.text = (
		"이동할 슬롯을 선택하세요 · "
		+ str(selected_amount)
		+ "개"
	)

	DebugLog.write(
		"[창고 옮기기] 대상 슬롯 선택 대기 / 원본: ",
		warehouse_move_source_slot_index,
		" / 수량: ",
		selected_amount
	)

func close_restock_panel():
	restock_panel.visible = false

	restock_slot_index = -1
	restock_amount = 1
	restock_max_amount = 0

	pending_transfer_data.clear()
	pending_transfer_target_side = ""
	pending_transfer_target_slot_index = -1

func set_restock_min():
	if restock_max_amount <= 0:
		return

	restock_amount = 1

	update_restock_amount_ui()


func set_restock_max():
	if restock_max_amount <= 0:
		return

	restock_amount = restock_max_amount

	update_restock_amount_ui()
