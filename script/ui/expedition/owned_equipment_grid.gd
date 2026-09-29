class_name OwnedEquipmentGrid
extends "res://script/ui/common/inventory/grid_inventory_view.gd"


const GRID_WIDTH: int = 6
const GRID_HEIGHT: int = 5
const CELL_SIZE: int = 46

const GRID_MODEL_SCRIPT = preload(
	"res://script/inventory/grid_placement_model.gd"
)


var model = GRID_MODEL_SCRIPT.new(
	GRID_WIDTH,
	GRID_HEIGHT
)


# =========================
# 초기 설정
# =========================

func setup_owned(
	new_controller: Node
) -> void:
	setup(
		"owned",
		model,
		new_controller,
		GRID_WIDTH,
		GRID_HEIGHT,
		CELL_SIZE
	)

	refresh_from_inventory()


func get_grid_model():
	return model


# =========================
# GameState → 보유 장비 동기화
# =========================

func refresh_from_inventory() -> void:
	# 기존 저장 데이터나 기존 상점 구매 데이터를
	# 개별 장비 인스턴스로 전환한다.
	GameState.migrate_legacy_equipment_inventory()

	_sync_model_with_instances()
	refresh()


func _sync_model_with_instances() -> void:
	var instances: Array[Dictionary] = (
		GameState.get_owned_equipment_instances()
	)

	var target_instances: Dictionary = {}

	for instance_data in instances:
		var instance_id: int = int(
			instance_data.get(
				"instance_id",
				-1
			)
		)

		if instance_id <= 0:
			continue

		target_instances[instance_id] = (
			instance_data
		)

	# =========================
	# 존재하지 않는 배치 제거
	# =========================

	for index in range(
		model.placements.size() - 1,
		-1,
		-1
	):
		var placement: Dictionary = (
			model.placements[index]
		)

		var instance_id: int = int(
			placement.get(
				"instance_id",
				-1
			)
		)

		if (
			instance_id > 0
			and target_instances.has(
				instance_id
			)
		):
			continue

		var uid: int = int(
			placement.get(
				"uid",
				-1
			)
		)

		model.remove_item(uid)

	# =========================
	# 현재 배치 갱신
	# =========================

	var placed_instance_ids: Dictionary = {}

	for placement in model.placements:
		var instance_id: int = int(
			placement.get(
				"instance_id",
				-1
			)
		)

		if not target_instances.has(
			instance_id
		):
			continue

		var instance_data: Dictionary = (
			target_instances[instance_id]
		)

		placement["enhancement_level"] = int(
			instance_data.get(
				"enhancement_level",
				0
			)
		)

		placed_instance_ids[instance_id] = true

	# =========================
	# 새 장비 배치
	# =========================

	for instance_data in instances:
		var instance_id: int = int(
			instance_data.get(
				"instance_id",
				-1
			)
		)

		if instance_id <= 0:
			continue

		if placed_instance_ids.has(
			instance_id
		):
			continue

		var item_id: String = str(
			instance_data.get(
				"item_id",
				""
			)
		)

		if not ExpeditionEquipmentData.has_equipment(
			item_id
		):
			continue

		var cell: Vector2i = (
			model.find_free_position(
				item_id,
				false
			)
		)

		if cell == Vector2i(-1, -1):
			push_warning(
				"[보유 장비] 공간 부족: "
				+ item_id
			)
			continue

		var uid: int = model.add_item(
			item_id,
			cell,
			1,
			false,
			{
				"instance_id": instance_id,
				"enhancement_level": int(
					instance_data.get(
						"enhancement_level",
						0
					)
				)
			}
		)

		if uid < 0:
			push_warning(
				"[보유 장비] 배치 실패: "
				+ item_id
			)


# =========================
# 배치 조작
# =========================

func add_placement(
	item_id: String,
	cell: Vector2i,
	rotated: bool = false,
	extra_data: Dictionary = {}
) -> int:
	var uid: int = model.add_item(
		item_id,
		cell,
		1,
		rotated,
		extra_data
	)

	if uid != -1:
		refresh()

	return uid


