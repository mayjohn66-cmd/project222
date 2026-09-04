extends Node


# =========================
# 게임 진행 상태
# =========================

var current_day: int = 1


# =========================
# 플레이어 상태
# =========================

var player_state: Dictionary = {}


# =========================
# 편의점 상태
# =========================

var store_layout: Array[Dictionary] = []


func save_player_state(
	data: Dictionary
):
	player_state = data.duplicate(true)

	print(
		"[GameState] 플레이어 상태 저장"
	)

var inventory: Dictionary = {}

func _ready():
	initialize_new_game()


func initialize_new_game():
	inventory.clear()

	for raw_item_id in GameConfig.STARTING_INVENTORY.keys():
		var item_id: String = str(raw_item_id)
		var amount: int = int(
			GameConfig.STARTING_INVENTORY[item_id]
		)

		if not ItemData.has_item(item_id):
			push_warning(
				"[GameState] 등록되지 않은 시작 아이템: "
				+ item_id
			)
			continue

		if amount <= 0:
			push_warning(
				"[GameState] 잘못된 시작 수량: "
				+ item_id
				+ " / "
				+ str(amount)
			)
			continue

		inventory[item_id] = amount

	print(
		"[GameState] 초기 인벤토리 생성: ",
		inventory
	)

func get_player_state() -> Dictionary:
	return player_state.duplicate(true)


func has_player_state() -> bool:
	return not player_state.is_empty()


func save_store_layout(
	layout: Array[Dictionary]
):
	store_layout = layout.duplicate(true)

	print(
		"[GameState] 편의점 배치 저장 / ",
		store_layout.size(),
		"개"
	)


func get_store_layout() -> Array[Dictionary]:
	return store_layout.duplicate(true)


func has_store_layout() -> bool:
	return not store_layout.is_empty()

func get_item_count(
	item_id: String
) -> int:
	return int(
		inventory.get(
			item_id,
			0
		)
	)


func add_item(
	item_id: String,
	amount: int
) -> void:
	if not ItemData.has_item(item_id):
		push_warning(
			"[GameState] 등록되지 않은 아이템 추가 시도: "
			+ item_id
		)
		return

	if amount <= 0:
		return

	inventory[item_id] = (
		get_item_count(item_id)
		+ amount
	)


func remove_item(
	item_id: String,
	amount: int
) -> int:
	if amount <= 0:
		return 0

	var current_count: int = (
		get_item_count(item_id)
	)

	var removed_amount: int = min(
		amount,
		current_count
	)

	inventory[item_id] = (
		current_count - removed_amount
	)

	return removed_amount


func get_inventory_data() -> Dictionary:
	return inventory.duplicate(true)
