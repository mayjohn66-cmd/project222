extends PanelContainer


const EXPEDITION_BAG_SCRIPT = preload(
	"res://script/expedition/expedition_bag.gd"
)

const GRID_DRAG_HELPER = preload(
	"res://script/inventory/grid_drag_helper.gd"
)

const GRID_TRANSFER_HELPER = preload(
	"res://script/inventory/grid_transfer_helper.gd"
)


@onready var owned_grid_area: Control = (
	$MainVBox/BagBody/OwnedPanel/OwnedVBox/OwnedGridArea
)


@onready var bag_grid_view: Control = (
	$MainVBox/BagBody/BagGridPanel/BagGridVBox/BagGridView
)

const BAG_WIDTH: int = 6
const BAG_HEIGHT: int = 5
const CELL_SIZE: int = 46


var bag_model = EXPEDITION_BAG_SCRIPT.new()
var selected_source: String = ""
var selected_uid: int = -1


func _ready() -> void:
	owned_grid_area.set("cell_color", Color("eadfc5"))
	bag_grid_view.set("cell_color", Color("eadfc5"))
	if owned_grid_area.has_method(
		"setup_owned"
	):
		owned_grid_area.call(
			"setup_owned",
			self
		)

	bag_grid_view.call(
		"setup",
		"bag",
		bag_model,
		self,
		BAG_WIDTH,
		BAG_HEIGHT,
		CELL_SIZE
	)

	if not bag_model.placements.is_empty():
		var test_placement: Dictionary = (
			bag_model.placements[0]
		)

		DebugLog.write(
			"[장비 강화 검사] ",
			EquipmentEnhancementService
			.get_enhancement_check(
				test_placement
			)
		)

	refresh_owned_items()
	_refresh_bag_visual()


# =========================
# 보유 장비
# =========================

func refresh_owned_items() -> void:
	if owned_grid_area.has_method(
		"refresh_from_inventory"
	):
		owned_grid_area.call(
			"refresh_from_inventory"
		)

	DebugLog.write(
		"[원정 준비 가방] 보유 장비 격자 갱신"
	)

# =========================
# 보유 장비 → 가방 드롭 판정
# =========================

func _transfer_owned_to_bag(
	uid: int,
	target_cell: Vector2i
) -> bool:
	var owned_model = _get_owned_model()

	if owned_model == null or bag_model == null:
		return false

	var placement: Dictionary = (
		owned_model.get_placement(uid)
	)

	if placement.is_empty():
		return false

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var instance_id: int = int(
		placement.get(
			"instance_id",
			-1
		)
	)

	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		return false

	if instance_id <= 0:
		push_warning(
			"[원정 준비] 장비 instance_id 없음: "
				+ item_id
		)
		return false

	if not GameState.has_owned_equipment_instance(
		instance_id
	):
		return false

	if not GRID_TRANSFER_HELPER.can_move_or_transfer(
		owned_model,
		bag_model,
		uid,
		target_cell
	):
		return false

	var origin_cell: Vector2i = (
		placement.get(
			"cell",
			Vector2i(-1, -1)
		)
	)

	var origin_rotated: bool = bool(
		placement.get(
			"rotated",
			false
		)
	)

	# GameState 보관함에서 먼저 꺼낸다.
	var instance_data: Dictionary = (
		GameState.take_owned_equipment_instance(
			instance_id
		)
	)

	if instance_data.is_empty():
		return false

	var result: Dictionary = (
		GRID_TRANSFER_HELPER.move_or_transfer(
			owned_model,
			bag_model,
			uid,
			target_cell,
			{
				"instance_id": instance_id,
				"enhancement_level": int(
					instance_data.get(
						"enhancement_level",
						0
					)
				),
				"owned_origin_cell": origin_cell,
				"owned_origin_rotated": origin_rotated
			}
		)
	)

	if not bool(
		result.get(
			"success",
			false
		)
	):
		GameState.return_owned_equipment_instance(
			instance_data
		)

		push_warning(
			"[원정 준비] 가방 이동 실패 / 장비 반환"
		)
		return false

	_set_selection(
		"bag",
		int(
			result.get(
				"new_uid",
				-1
			)
		)
	)

	return true

func _transfer_bag_to_owned(
	uid: int,
	target_cell: Vector2i
) -> bool:
	var owned_model = _get_owned_model()

	if owned_model == null or bag_model == null:
		return false

	var placement: Dictionary = (
		bag_model.get_placement(uid)
	)

	if placement.is_empty():
		return false

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var instance_id: int = int(
		placement.get(
			"instance_id",
			-1
		)
	)

	var enhancement_level: int = int(
		placement.get(
			"enhancement_level",
			0
		)
	)

	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		push_warning(
			"[원정 준비] 장비가 아닌 아이템 반환은 아직 지원하지 않음: "
				+ item_id
		)
		return false

	if instance_id <= 0:
		push_warning(
			"[원정 준비] 반환 장비 instance_id 없음: "
				+ item_id
		)
		return false

	if GameState.has_owned_equipment_instance(
		instance_id
	):
		push_warning(
			"[원정 준비] 이미 보관 중인 장비 ID: "
				+ str(instance_id)
		)
		return false

	if not GRID_TRANSFER_HELPER.can_move_or_transfer(
		bag_model,
		owned_model,
		uid,
		target_cell
	):
		return false

	var instance_data: Dictionary = {
		"instance_id": instance_id,
		"item_id": item_id,
		"enhancement_level": enhancement_level
	}

	# 먼저 GameState에 반환한다.
	if not GameState.return_owned_equipment_instance(
		instance_data
	):
		return false

	var result: Dictionary = (
		GRID_TRANSFER_HELPER.move_or_transfer(
			bag_model,
			owned_model,
			uid,
			target_cell
		)
	)

	if not bool(
		result.get(
			"success",
			false
		)
	):
		# 격자 이동 실패 시 GameState 반환도 취소한다.
		GameState.take_owned_equipment_instance(
			instance_id
		)

		return false

	_set_selection(
		"owned",
		int(
			result.get(
				"new_uid",
				-1
			)
		)
	)

	return true



# =========================
# 실제 가방 배치
# =========================


# =========================
# 가방 화면 갱신
# =========================

func _refresh_bag_visual() -> void:
	if (
		bag_grid_view != null
		and bag_grid_view.has_method(
			"refresh"
		)
	):
		bag_grid_view.call(
			"refresh"
		)

func _refresh_grid_selection_visuals() -> void:
	if (
		owned_grid_area != null
		and owned_grid_area.has_method(
			"refresh_selection_visuals"
		)
	):
		owned_grid_area.call(
			"refresh_selection_visuals"
		)

	if (
		bag_grid_view != null
		and bag_grid_view.has_method(
			"refresh_selection_visuals"
		)
	):
		bag_grid_view.call(
			"refresh_selection_visuals"
		)


func _get_owned_model():
	if owned_grid_area == null:
		return null

	if not owned_grid_area.has_method(
		"get_grid_model"
	):
		return null

	return owned_grid_area.call(
		"get_grid_model"
	)

func _get_grid_model_by_source(
	source: String
):
	if source == "owned":
		return _get_owned_model()

	if source == "bag":
		return bag_model

	return null

func _refresh_grid_views() -> void:
	if (
		owned_grid_area != null
		and owned_grid_area.has_method("refresh")
	):
		owned_grid_area.call("refresh")

	if (
		bag_grid_view != null
		and bag_grid_view.has_method("refresh")
	):
		bag_grid_view.call("refresh")


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if event.is_action_pressed("bag_rotate"):
		_rotate_selected_item()


func _rotate_selected_item() -> void:
	if selected_uid == -1:
		return

	if (
		selected_source != "owned"
		and selected_source != "bag"
	):
		return

	var model = (
		_get_grid_model_by_source(
			selected_source
		)
	)

	if model == null:
		return

	var rotated_ok: bool = (
		model.rotate_item(
			selected_uid
		)
	)

	if not rotated_ok:
		return

	_refresh_grid_views()

	DebugLog.write(
		"[공통 회전] ",
		selected_source,
		" / UID: ",
		selected_uid
	)

func select_grid_item(
	source: String,
	uid: int
) -> void:
	if (
		source != "owned"
		and source != "bag"
	):
		return

	if uid == -1:
		return

	_set_selection(
		source,
		uid
	)

	_refresh_grid_selection_visuals()

func get_prepared_bag_model():
	return bag_model

func refresh_all() -> void:
	refresh_owned_items()
	_refresh_bag_visual()

func restore_returned_item_placement(
	placement: Dictionary
) -> bool:
	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	if item_id.is_empty():
		return false

	var origin_cell: Vector2i = (
		placement.get(
			"owned_origin_cell",
			Vector2i(-1, -1)
		)
	)

	# 원래 위치가 없음 = 원정 중 새로 획득한 전리품
	if (
		origin_cell.x < 0
		or origin_cell.y < 0
	):
		return false

	var origin_rotated: bool = bool(
		placement.get(
			"owned_origin_rotated",
			false
		)
	)

	if not owned_grid_area.has_method(
		"add_placement"
	):
		return false

	var new_uid: int = int(
		owned_grid_area.call(
			"add_placement",
			item_id,
			origin_cell,
			origin_rotated
		)
	)

	if new_uid == -1:
		push_warning(
			"[원정 준비 가방] 원래 위치 복원 실패: "
			+ item_id
		)

		return false

	DebugLog.write(
		"[원정 준비 가방] 원래 위치 복원 / ",
		item_id,
		" / 위치: ",
		origin_cell
	)

	return true


func toggle_grid_item(
	source: String,
	uid: int
) -> void:
	if (
		source != "owned"
		and source != "bag"
	):
		return

	if uid == -1:
		return

	if (
		selected_source == source
		and selected_uid == uid
	):
		_clear_selection()
	else:
		_set_selection(
			source,
			uid
		)

	_refresh_grid_selection_visuals()


func is_grid_item_selected(
	source: String,
	uid: int
) -> bool:
	return (
		selected_source == source
		and selected_uid == uid
	)


func clear_grid_selection(
	source: String
) -> void:
	if selected_source != source:
		return

	_clear_selection()

	_refresh_grid_selection_visuals()


func can_drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> bool:
	var source: String = str(
		data.get(
			"source",
			""
		)
	)

	if (
		source != "owned"
		and source != "bag"
	):
		return false

	if (
		target_source != "owned"
		and target_source != "bag"
	):
		return false

	var uid: int = int(
		data.get(
			"uid",
			-1
		)
	)

	if uid == -1:
		return false

	var source_model = (
		_get_grid_model_by_source(
			source
		)
	)

	var target_model = (
		_get_grid_model_by_source(
			target_source
		)
	)

	if source_model == null:
		return false

	if target_model == null:
		return false

	var placement: Dictionary = (
		source_model.get_placement(
			uid
		)
	)

	if placement.is_empty():
		return false

	# 보유 장비 → 원정 가방
	# 일반 인벤토리 수량 대신 개별 장비 인스턴스를 검사한다.
	if (
		source == "owned"
		and target_source == "bag"
	):
		var instance_id: int = int(
			placement.get(
				"instance_id",
				-1
			)
		)

		if instance_id <= 0:
			return false

		if not GameState.has_owned_equipment_instance(
			instance_id
		):
			return false

		var loadout_result: Dictionary = (
			ExpeditionLoadoutService.can_add_equipment(
				bag_model,
				placement
			)
		)

		if not bool(
			loadout_result.get(
				"success",
				false
			)
		):
			return false

	var target_cell: Vector2i = (
		GRID_DRAG_HELPER.get_target_start_cell(
			cursor_cell,
			data
		)
	)

	return GRID_TRANSFER_HELPER.can_move_or_transfer(
		source_model,
		target_model,
		uid,
		target_cell
	)

func drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> void:
	if not can_drop_grid_data(
		target_source,
		data,
		cursor_cell
	):
		return

	var source: String = str(
		data.get(
			"source",
			""
		)
	)

	var uid: int = int(
		data.get(
			"uid",
			-1
		)
	)

	if uid == -1:
		return

	var target_cell: Vector2i = (
		GRID_DRAG_HELPER.get_target_start_cell(
			cursor_cell,
			data
		)
	)


	# =========================
	# 같은 격자 내부 이동
	# =========================

	if source == target_source:
		var model = (
			_get_grid_model_by_source(
				source
			)
		)

		if model == null:
			return

		var result: Dictionary = (
			GRID_TRANSFER_HELPER.move_or_transfer(
				model,
				model,
				uid,
				target_cell
			)
		)

		if not bool(
			result.get(
				"success",
				false
			)
		):
			return

		_set_selection(
			source,
			uid
		)

		_refresh_grid_views()
		return


	# =========================
	# 보유 장비 → 원정 가방
	# =========================

	if (
		source == "owned"
		and target_source == "bag"
	):
		if _transfer_owned_to_bag(
			uid,
			target_cell
		):
			_refresh_grid_views()

		return


	# =========================
	# 원정 가방 → 보유 장비
	# =========================

	if (
		source == "bag"
		and target_source == "owned"
	):
		if _transfer_bag_to_owned(
			uid,
			target_cell
		):
			_refresh_grid_views()

		return

func _set_selection(
	source: String,
	uid: int
) -> void:
	selected_source = source
	selected_uid = uid


func _clear_selection() -> void:
	selected_source = ""
	selected_uid = -1

func prepare_for_departure() -> void:
	_clear_selection()
	_refresh_grid_selection_visuals()

	DebugLog.write(
		"[원정 준비] 출발 전 선택 상태 초기화"
	)

# =========================
# 정비 화면용 장비 조회
# =========================

func get_equipment_entries_for_maintenance() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	_append_maintenance_entries(
		result,
		_get_grid_model_by_source("owned"),
		"보관함"
	)

	_append_maintenance_entries(
		result,
		_get_grid_model_by_source("bag"),
		"원정 가방"
	)

	return result


func _append_maintenance_entries(
	result: Array[Dictionary],
	model,
	source_name: String
) -> void:
	if model == null:
		return

	for placement in model.placements:
		var item_id: String = str(
			placement.get("item_id", "")
		)

		if not ExpeditionEquipmentData.has_equipment(item_id):
			continue

		var instance_id: int = int(
			placement.get("instance_id", -1)
		)

		if instance_id < 0:
			continue

		result.append(
			{
				"instance_id": instance_id,
				"item_id": item_id,
				"enhancement_level": int(
					placement.get(
						"enhancement_level",
						0
					)
				),
				"source_name": source_name
			}
		)


func get_equipment_placement_for_maintenance(
	instance_id: int
) -> Dictionary:
	if instance_id < 0:
		return {}

	for source in ["owned", "bag"]:
		var model = _get_grid_model_by_source(
			source
		)

		if model == null:
			continue

		for placement in model.placements:
			if int(
				placement.get(
					"instance_id",
					-1
				)
			) == instance_id:
				# 복사본이 아니라 실제 배치 Dictionary 반환
				return placement

	return {}


func refresh_after_equipment_enhancement() -> void:
	refresh_owned_items()
	_refresh_grid_views()
