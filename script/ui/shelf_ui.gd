extends PanelContainer

const ITEM_CARD_SCENE: PackedScene = preload(
	"res://scenes/ui/item_card.tscn"
)

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

@onready var potion_tab_button: Button = (
	$WindowBg/ContentHBox/InventoryArea/CategoryTabs/PotionTabButton
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


# =========================================================
# 현재 상태
# =========================================================

var current_shelf = null
var current_player = null

var restock_slot_index: int = -1
var restock_amount: int = 1
var restock_max_amount: int = 0

# 빈 슬롯을 선택했을 때 사용
var selected_slot_index: int = -1

# 상품이 들어있는 슬롯의 액션 메뉴용
var action_slot_index: int = -1

var selected_category: String = "food"


# =========================================================
# 시작
# =========================================================

func _ready():
	visible = false
	slot_action_panel.visible = false

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

	potion_tab_button.pressed.connect(
		select_category.bind(
			ItemData.CATEGORY_POTION
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

func select_category(category: String):
	selected_category = category

	print(
		"상품 카테고리 선택: ",
		selected_category
	)

	refresh_inventory_slots()

# =========================================================
# 창 열기 / 닫기
# =========================================================

func open(shelf, player):
	current_shelf = shelf
	current_player = player

	selected_slot_index = -1
	action_slot_index = -1

	slot_action_panel.visible = false
	visible = true

	refresh_ui()


func close():
	close_action_menu()
	close_restock_panel()

	visible = false

	current_shelf = null
	current_player = null
	selected_slot_index = -1


# =========================================================
# 전체 UI 갱신
# =========================================================

func refresh_ui():
	refresh_shelf_slots()
	refresh_inventory_slots()


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
	var slot: Dictionary = current_shelf.slots[
		slot_index
	]

	var item_id: String = str(
		slot.get(
			"item_id",
			""
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
			5
		)
	)

	var button: Button


	# =============================
	# 빈 슬롯
	# =============================
	if item_id.is_empty():
		button = Button.new()

		button.custom_minimum_size = Vector2(
			100,
			125
		)

		if selected_slot_index == slot_index:
			button.text = (
				"선택됨"
				+ "\n"
				+ str(stock)
				+ " / "
				+ str(capacity)
			)
		else:
			button.text = (
				"빈 슬롯"
				+ "\n"
				+ str(stock)
				+ " / "
				+ str(capacity)
			)


	# =============================
	# 상품 슬롯
	# =============================
	else:
		var item_data: Dictionary = ItemData.get_item(
			item_id
		)

		var price: int = int(
			item_data.get(
				"price",
				0
			)
		)

		button = create_item_card(
			item_id,
			str(stock),
			str(price) + "G"
		)


	button.pressed.connect(
		_on_shelf_slot_pressed.bind(
			slot_index
		)
	)

	shelf_slot_grid.add_child(
		button
	)


func _on_shelf_slot_pressed(slot_index: int):
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

	# 상품이 들어있는 슬롯
	if not item_id.is_empty():
		open_action_menu(slot_index)
		return

	# 이미 선택한 빈 슬롯을 다시 클릭
	# → 선택 취소
	if selected_slot_index == slot_index:
		selected_slot_index = -1

		print("진열 슬롯 선택 취소")

		refresh_shelf_slots()
		return

	# 다른 빈 슬롯 선택
	close_action_menu()

	selected_slot_index = slot_index

	print(
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


func create_inventory_slot(
	item_id: String,
	count: int
):
	if count <= 0:
		return

	var card := (
		ITEM_CARD_SCENE.instantiate()
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


func _on_inventory_item_pressed(item_id: String):
	if current_shelf == null:
		return

	if current_player == null:
		return

	if selected_slot_index < 0:
		print("먼저 빈 진열 슬롯을 선택하세요.")
		return

	if selected_slot_index >= current_shelf.slots.size():
		return

	if current_player.get_item_count(item_id) <= 0:
		return

	var slot: Dictionary = current_shelf.slots[
		selected_slot_index
	]

	# 이미 다른 상품이 들어가 있으면 중단
	if not str(slot.get("item_id", "")).is_empty():
		return

	# 상품 종류만 지정
	# 아직 실제 상품 수량은 이동하지 않는다.
	slot["item_id"] = item_id
	slot["stock"] = 0

	current_shelf.slots[selected_slot_index] = slot

	print(
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

	# 액션 메뉴 표시
	slot_action_panel.visible = true
	slot_action_panel.z_index = 100

	# 팝업 크기 강제 지정
	slot_action_panel.custom_minimum_size = Vector2(
		140,
		170
	)

	slot_action_panel.size = Vector2(
		140,
		170
	)

	# 현재 마우스로 클릭한 위치
	var mouse_pos: Vector2 = (
		get_viewport().get_mouse_position()
	)

	var popup_size := Vector2(
	140,
	170
	)

	# 마우스 바로 위가 아니라 살짝 오른쪽 아래에 표시
	var popup_pos := (
		mouse_pos
		+ Vector2(15, 15)
	)

	# 화면 밖으로 나가지 않도록 제한
	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	popup_pos.x = clampf(
		popup_pos.x,
		0.0,
		viewport_size.x - popup_size.x
	)

	popup_pos.y = clampf(
		popup_pos.y,
		0.0,
		viewport_size.y - popup_size.y
	)

	slot_action_panel.global_position = popup_pos


func close_action_menu():
	slot_action_panel.visible = false
	action_slot_index = -1


# =========================================================
# 보충
# =========================================================

func restock_action_slot():
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
		slot.get(
			"item_id",
			""
		)
	)

	if item_id.is_empty():
		return

	var stock: int = int(
		slot.get(
			"stock",
			0
		)
	)

	var capacity: int = int(
		slot.get(
			"capacity",
			5
		)
	)

	# 이미 가득 찬 슬롯
	if stock >= capacity:
		print("이미 가득 찬 슬롯")
		return

	# 플레이어 보유량 확인
	var player_count: int = (
		current_player.get_item_count(
			item_id
		)
	)

	if player_count <= 0:
		print(
			"보유 상품 없음: ",
			item_id
		)
		return

	# =========================
	# 이번에는 1개만 꺼냄
	# =========================
	var removed: int = (
		current_player.remove_item(
			item_id,
			1
		)
	)

	if removed <= 0:
		return

	# =========================
	# 진열대에 실제 추가
	# =========================
	var added: int = (
		current_shelf.add_stock_to_slot(
			action_slot_index,
			removed
		)
	)

	# 만약 어떤 이유로 진열대에 못 넣었으면
	# 플레이어에게 다시 반환
	if added < removed:
		current_player.add_item(
			item_id,
			removed - added
		)

	if added <= 0:
		return

	print(
		"수동 보충: ",
		item_id,
		" +",
		added
	)

	# 수량 표시 갱신
	refresh_ui()

	# 액션 메뉴는 닫지 않음.
	# 보충 버튼을 연속으로 눌러 테스트 가능


# =========================================================
# 비우기
# =========================================================

func clear_action_slot():
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

	var stock: int = int(
		slot.get("stock", 0)
	)

	# 남아 있는 상품은 플레이어에게 반환
	if stock > 0:
		current_player.add_item(
			item_id,
			stock
		)

	# 슬롯 초기화
	slot["item_id"] = ""
	slot["stock"] = 0

	current_shelf.slots[
		action_slot_index
	] = slot

	print(
		"진열 슬롯 비우기: ",
		item_id,
		" / 반환 ",
		stock
	)

	selected_slot_index = -1

	refresh_ui()
	close_action_menu()


# =========================================================
# 상품 정보
# =========================================================

func show_item_info():
	if current_shelf == null:
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

	var item_data: Dictionary = ItemData.get_item(
		item_id
	)

	# 현재는 임시 출력
	print(
		"상품 정보: ",
		item_data
	)


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

	if event.is_action_pressed("ui_cancel"):
		# 액션 메뉴가 열려 있으면 액션 메뉴만 닫기
		
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


func create_item_card(
	item_id: String,
	count_text: String,
	bottom_text: String = ""
) -> Button:
	var item_data: Dictionary = ItemData.get_item(
		item_id
	)

	var button := Button.new()

	button.custom_minimum_size = Vector2(
		100,
		125
	)

	button.text = ""

	var root := Control.new()

	root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	root.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	button.add_child(root)


	# 상품 아이콘
	var icon_rect := TextureRect.new()

	icon_rect.texture = item_data.get(
		"icon",
		null
	)

	icon_rect.position = Vector2(
		15,
		20
	)

	icon_rect.size = Vector2(
		70,
		70
	)

	icon_rect.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)

	icon_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	icon_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	root.add_child(icon_rect)


	# 우측 상단 수량
	var count_label := Label.new()

	count_label.text = count_text

	count_label.position = Vector2(
		66,
		3
	)

	count_label.size = Vector2(
		30,
		25
	)

	count_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)

	count_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	root.add_child(count_label)


	# 하단 가격
	if not bottom_text.is_empty():
		var bottom_label := Label.new()

		bottom_label.text = bottom_text

		bottom_label.position = Vector2(
			5,
			96
		)

		bottom_label.size = Vector2(
			90,
			25
		)

		bottom_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER
		)

		bottom_label.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
		)

		root.add_child(bottom_label)


	return button

func open_restock_panel():
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
		print("보충 가능한 상품이 없습니다.")
		return

	# 액션 메뉴의 슬롯 번호를 따로 보관
	restock_slot_index = action_slot_index

	restock_amount = 1

	restock_info_label.text = (
		"몇 개를 보충하시겠습니까?"
	)

	restock_panel.visible = true
	restock_panel.z_index = 110

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
			removed
		)
	)

	# 예상보다 적게 들어간 경우 반환
	if added < removed:
		current_player.add_item(
			item_id,
			removed - added
		)

	print(
		"수동 보충 완료: ",
		item_id,
		" +",
		added
	)

	refresh_ui()
	close_restock_panel()

func close_restock_panel():
	restock_panel.visible = false

	restock_slot_index = -1
	restock_amount = 1
	restock_max_amount = 0

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
