extends Node


const RULES_PATH: String = (
	"res://data/expedition/expedition_equipment_rules.csv"
)

const EQUIPMENT_PATH: String = (
	"res://data/expedition/expedition_equipment.csv"
)

const ENHANCEMENT_COSTS_PATH: String = (
	"res://data/expedition/equipment_enhancement_costs.csv"
)

const MISC_ITEMS_PATH: String = (
	"res://data/expedition/expedition_misc_items.csv"
)


const TYPE_WEAPON: String = "weapon"
const TYPE_ARMOR: String = "armor"
const TYPE_TOOL: String = "tool"
const TYPE_MISC: String = "misc"

const DUPLICATE_ALLOW: String = "allow"
const DUPLICATE_EFFECT_ID: String = "effect_id"


const VALID_EQUIPMENT_TYPES: Array[String] = [
	TYPE_WEAPON,
	TYPE_ARMOR,
	TYPE_TOOL,
	TYPE_MISC
]

const VALID_DUPLICATE_POLICIES: Array[String] = [
	DUPLICATE_ALLOW,
	DUPLICATE_EFFECT_ID
]


var equipment_rules: Dictionary = {}
var equipment: Dictionary = {}
var enhancement_costs: Dictionary = {}
var misc_items: Dictionary = {}

var _loaded: bool = false


func _ready() -> void:
	load_data()


func ensure_loaded() -> void:
	if _loaded:
		return

	load_data()


func load_data() -> void:
	_loaded = false

	equipment_rules.clear()
	equipment.clear()
	enhancement_costs.clear()
	misc_items.clear()

	if not _load_equipment_rules():
		return

	if not _load_equipment():
		return

	if not _load_enhancement_costs():
		return

	if not _load_misc_items():
		return

	if not _validate_cross_references():
		return

	_loaded = true

	print(
		"[ExpeditionEquipmentData] 로드 완료"
		+ " / 장비: ",
		equipment.size(),
		" / 기타: ",
		misc_items.size(),
		" / 강화 그룹: ",
		enhancement_costs.size()
	)


# =========================
# 장비 종류별 규칙
# =========================

func _load_equipment_rules() -> bool:
	var result: Dictionary = _read_csv(
		RULES_PATH,
		[
			"equipment_type",
			"max_equipped",
			"duplicate_policy",
			"enhanceable"
		]
	)

	if not bool(result.get("success", false)):
		return false

	var rows: Array[Dictionary] = result.get(
		"rows",
		[]
	)

	for row in rows:
		var equipment_type: String = str(
			row.get(
				"equipment_type",
				""
			)
		)

		var max_text: String = str(
			row.get(
				"max_equipped",
				""
			)
		)

		var duplicate_policy: String = str(
			row.get(
				"duplicate_policy",
				""
			)
		)

		var enhanceable_text: String = str(
			row.get(
				"enhanceable",
				""
			)
		).to_lower()

		if not VALID_EQUIPMENT_TYPES.has(
			equipment_type
		):
			return _data_error(
				"잘못된 equipment_type: "
				+ equipment_type
			)

		if equipment_rules.has(equipment_type):
			return _data_error(
				"중복 장비 규칙: "
				+ equipment_type
			)

		if not max_text.is_valid_int():
			return _data_error(
				"잘못된 max_equipped: "
				+ equipment_type
			)

		var max_equipped: int = int(max_text)

		if max_equipped < -1:
			return _data_error(
				"max_equipped는 -1 이상이어야 함: "
				+ equipment_type
			)

		if not VALID_DUPLICATE_POLICIES.has(
			duplicate_policy
		):
			return _data_error(
				"잘못된 duplicate_policy: "
				+ equipment_type
			)

		if not _is_valid_bool_text(
			enhanceable_text
		):
			return _data_error(
				"잘못된 enhanceable: "
				+ equipment_type
			)

		equipment_rules[equipment_type] = {
			"equipment_type": equipment_type,
			"max_equipped": max_equipped,
			"duplicate_policy": duplicate_policy,
			"enhanceable": (
				enhanceable_text == "true"
			)
		}

	return true


# =========================
# 무기·방어구·도구
# =========================

func _load_equipment() -> bool:
	var result: Dictionary = _read_csv(
		EQUIPMENT_PATH,
		[
			"item_id",
			"equipment_type",
			"effect_id",
			"base_value",
			"max_enhancement_level",
			"enhancement_group"
		]
	)

	if not bool(result.get("success", false)):
		return false

	var rows: Array[Dictionary] = result.get(
		"rows",
		[]
	)

	for row in rows:
		var item_id: String = str(
			row.get("item_id", "")
		)

		var equipment_type: String = str(
			row.get("equipment_type", "")
		)

		var effect_id: String = str(
			row.get("effect_id", "")
		)

		var base_value_text: String = str(
			row.get("base_value", "")
		)

		var max_level_text: String = str(
			row.get(
				"max_enhancement_level",
				""
			)
		)

		var enhancement_group: String = str(
			row.get(
				"enhancement_group",
				""
			)
		)

		if item_id.is_empty():
			return _data_error(
				"장비 item_id가 비어 있습니다."
			)

		if equipment.has(item_id):
			return _data_error(
				"중복 장비 ID: " + item_id
			)

		if not ItemData.has_item(item_id):
			return _data_error(
				"items.csv에 없는 장비: "
				+ item_id
			)

		if equipment_type == TYPE_MISC:
			return _data_error(
				"misc는 expedition_misc_items.csv에 등록해야 함: "
				+ item_id
			)

		if not equipment_rules.has(
			equipment_type
		):
			return _data_error(
				"규칙이 없는 장비 종류: "
				+ equipment_type
			)

		if effect_id.is_empty():
			return _data_error(
				"effect_id가 비어 있음: "
				+ item_id
			)

		if not base_value_text.is_valid_float():
			return _data_error(
				"잘못된 base_value: "
				+ item_id
			)

		var base_value: float = float(
			base_value_text
		)

		if (
			not is_finite(base_value)
			or base_value < 0.0
		):
			return _data_error(
				"base_value 범위 오류: "
				+ item_id
			)

		if not max_level_text.is_valid_int():
			return _data_error(
				"잘못된 최대 강화 단계: "
				+ item_id
			)

		var max_level: int = int(
			max_level_text
		)

		if max_level < 0:
			return _data_error(
				"최대 강화 단계가 음수임: "
				+ item_id
			)

		if (
			max_level > 0
			and enhancement_group.is_empty()
		):
			return _data_error(
				"강화 그룹이 비어 있음: "
				+ item_id
			)

		if (
			equipment_type == TYPE_WEAPON
			and effect_id != "attack"
		):
			return _data_error(
				"무기의 effect_id는 attack이어야 함: "
				+ item_id
			)

		if (
			equipment_type == TYPE_ARMOR
			and effect_id != "defense"
		):
			return _data_error(
				"방어구의 effect_id는 defense여야 함: "
				+ item_id
			)

		equipment[item_id] = {
			"item_id": item_id,
			"equipment_type": equipment_type,
			"effect_id": effect_id,
			"base_value": base_value,
			"max_enhancement_level": max_level,
			"enhancement_group": enhancement_group
		}

	return true


# =========================
# 강화 비용
# =========================

func _load_enhancement_costs() -> bool:
	var result: Dictionary = _read_csv(
		ENHANCEMENT_COSTS_PATH,
		[
			"enhancement_group",
			"target_level",
			"material_id",
			"amount"
		]
	)

	if not bool(result.get("success", false)):
		return false

	var rows: Array[Dictionary] = result.get(
		"rows",
		[]
	)

	for row in rows:
		var group_id: String = str(
			row.get(
				"enhancement_group",
				""
			)
		)

		var level_text: String = str(
			row.get(
				"target_level",
				""
			)
		)

		var material_id: String = str(
			row.get(
				"material_id",
				""
			)
		)

		var amount_text: String = str(
			row.get(
				"amount",
				""
			)
		)

		if group_id.is_empty():
			return _data_error(
				"강화 그룹이 비어 있습니다."
			)

		if not level_text.is_valid_int():
			return _data_error(
				"잘못된 강화 단계: "
				+ level_text
			)

		var target_level: int = int(
			level_text
		)

		if target_level <= 0:
			return _data_error(
				"강화 단계는 1 이상이어야 함: "
				+ group_id
			)

		if not ItemData.has_item(material_id):
			return _data_error(
				"등록되지 않은 강화 재료: "
				+ material_id
			)

		if not amount_text.is_valid_int():
			return _data_error(
				"잘못된 강화 재료 수량: "
				+ group_id
			)

		var amount: int = int(amount_text)

		if amount <= 0:
			return _data_error(
				"강화 재료 수량은 1 이상이어야 함: "
				+ group_id
			)

		var group_costs: Dictionary = (
			enhancement_costs.get(
				group_id,
				{}
			)
		)

		var level_costs: Dictionary = (
			group_costs.get(
				target_level,
				{}
			)
		)

		if level_costs.has(material_id):
			return _data_error(
				"중복 강화 비용: "
				+ group_id
				+ " / +"
				+ str(target_level)
				+ " / "
				+ material_id
			)

		level_costs[material_id] = amount
		group_costs[target_level] = level_costs
		enhancement_costs[group_id] = group_costs

	return true


# =========================
# 기타 원정 아이템
# =========================

func _load_misc_items() -> bool:
	var result: Dictionary = _read_csv(
		MISC_ITEMS_PATH,
		[
			"item_id",
			"effect_id",
			"effect_value",
			"shelf_life_days",
			"consume_on_use"
		]
	)

	if not bool(result.get("success", false)):
		return false

	var rows: Array[Dictionary] = result.get(
		"rows",
		[]
	)

	for row in rows:
		var item_id: String = str(
			row.get("item_id", "")
		)

		var effect_id: String = str(
			row.get("effect_id", "")
		)

		var effect_value_text: String = str(
			row.get("effect_value", "")
		)

		var shelf_life_text: String = str(
			row.get("shelf_life_days", "")
		)

		var consume_text: String = str(
			row.get(
				"consume_on_use",
				""
			)
		).to_lower()

		if item_id.is_empty():
			return _data_error(
				"기타 아이템 ID가 비어 있습니다."
			)

		if misc_items.has(item_id):
			return _data_error(
				"중복 기타 아이템: "
				+ item_id
			)

		if equipment.has(item_id):
			return _data_error(
				"장비와 기타에 중복 등록됨: "
				+ item_id
			)

		if not ItemData.has_item(item_id):
			return _data_error(
				"items.csv에 없는 기타 아이템: "
				+ item_id
			)

		if effect_id.is_empty():
			return _data_error(
				"기타 아이템 effect_id가 비어 있음: "
				+ item_id
			)

		if not effect_value_text.is_valid_float():
			return _data_error(
				"잘못된 effect_value: "
				+ item_id
			)

		var effect_value: float = float(
			effect_value_text
		)

		if not is_finite(effect_value):
			return _data_error(
				"effect_value가 유효하지 않음: "
				+ item_id
			)

		if not shelf_life_text.is_valid_int():
			return _data_error(
				"잘못된 shelf_life_days: "
				+ item_id
			)

		var shelf_life_days: int = int(
			shelf_life_text
		)

		if shelf_life_days <= 0:
			return _data_error(
				"유통기한은 1일 이상이어야 함: "
				+ item_id
			)

		if not _is_valid_bool_text(
			consume_text
		):
			return _data_error(
				"잘못된 consume_on_use: "
				+ item_id
			)

		misc_items[item_id] = {
			"item_id": item_id,
			"equipment_type": TYPE_MISC,
			"effect_id": effect_id,
			"effect_value": effect_value,
			"shelf_life_days": shelf_life_days,
			"consume_on_use": (
				consume_text == "true"
			)
		}

	return true


# =========================
# 데이터 연결 검사
# =========================

func _validate_cross_references() -> bool:
	for equipment_type in VALID_EQUIPMENT_TYPES:
		if not equipment_rules.has(
			equipment_type
		):
			return _data_error(
				"장비 규칙 누락: "
				+ equipment_type
			)

	for raw_item_id in equipment.keys():
		var item_id: String = str(
			raw_item_id
		)

		var data: Dictionary = equipment[
			item_id
		]

		var max_level: int = int(
			data.get(
				"max_enhancement_level",
				0
			)
		)

		if max_level <= 0:
			continue

		var group_id: String = str(
			data.get(
				"enhancement_group",
				""
			)
		)

		if not enhancement_costs.has(
			group_id
		):
			return _data_error(
				"강화 비용 그룹 없음: "
				+ item_id
				+ " / "
				+ group_id
			)

		var group_costs: Dictionary = (
			enhancement_costs[group_id]
		)

		for target_level in range(
			1,
			max_level + 1
		):
			if group_costs.has(target_level):
				continue

			return _data_error(
				"강화 단계 비용 누락: "
				+ item_id
				+ " / +"
				+ str(target_level)
			)

	return true


# =========================
# 장비 조회
# =========================

func has_equipment(
	item_id: String
) -> bool:
	ensure_loaded()
	return equipment.has(item_id)


func get_equipment_data(
	item_id: String
) -> Dictionary:
	ensure_loaded()

	if not equipment.has(item_id):
		return {}

	return equipment[item_id].duplicate(true)


func get_all_equipment() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for data in equipment.values():
		result.append(
			data.duplicate(true)
		)

	return result


func get_equipment_type(
	item_id: String
) -> String:
	return str(
		get_equipment_data(
			item_id
		).get(
			"equipment_type",
			""
		)
	)


func get_effect_id(
	item_id: String
) -> String:
	return str(
		get_equipment_data(
			item_id
		).get(
			"effect_id",
			""
		)
	)


func get_base_value(
	item_id: String
) -> float:
	return float(
		get_equipment_data(
			item_id
		).get(
			"base_value",
			0.0
		)
	)


func get_max_enhancement_level(
	item_id: String
) -> int:
	return int(
		get_equipment_data(
			item_id
		).get(
			"max_enhancement_level",
			0
		)
	)


func get_enhancement_cost(
	item_id: String,
	target_level: int
) -> Dictionary:
	var data: Dictionary = (
		get_equipment_data(
			item_id
		)
	)

	if data.is_empty():
		return {}

	var group_id: String = str(
		data.get(
			"enhancement_group",
			""
		)
	)

	if not enhancement_costs.has(group_id):
		return {}

	var group_costs: Dictionary = (
		enhancement_costs[group_id]
	)

	if not group_costs.has(target_level):
		return {}

	return group_costs[
		target_level
	].duplicate(true)


# =========================
# 장착 규칙 조회
# =========================

func get_equipment_rule(
	equipment_type: String
) -> Dictionary:
	ensure_loaded()

	if not equipment_rules.has(
		equipment_type
	):
		return {}

	return equipment_rules[
		equipment_type
	].duplicate(true)


func get_max_equipped(
	equipment_type: String
) -> int:
	return int(
		get_equipment_rule(
			equipment_type
		).get(
			"max_equipped",
			-1
		)
	)


func get_duplicate_policy(
	equipment_type: String
) -> String:
	return str(
		get_equipment_rule(
			equipment_type
		).get(
			"duplicate_policy",
			DUPLICATE_ALLOW
		)
	)


func is_enhanceable(
	item_id: String
) -> bool:
	var equipment_type: String = (
		get_equipment_type(
			item_id
		)
	)

	if equipment_type.is_empty():
		return false

	return bool(
		get_equipment_rule(
			equipment_type
		).get(
			"enhanceable",
			false
		)
	)


# =========================
# 기타 아이템 조회
# =========================

func has_misc_item(
	item_id: String
) -> bool:
	ensure_loaded()
	return misc_items.has(item_id)


func get_misc_item_data(
	item_id: String
) -> Dictionary:
	ensure_loaded()

	if not misc_items.has(item_id):
		return {}

	return misc_items[item_id].duplicate(true)


# =========================
# CSV 공통 처리
# =========================

func _read_csv(
	path: String,
	required_headers: Array[String]
) -> Dictionary:
	if not FileAccess.file_exists(path):
		_data_error(
			"파일 없음: " + path
		)

		return {
			"success": false,
			"rows": []
		}

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		_data_error(
			"파일 열기 실패: " + path
		)

		return {
			"success": false,
			"rows": []
		}

	if file.eof_reached():
		file.close()

		_data_error(
			"CSV가 비어 있음: " + path
		)

		return {
			"success": false,
			"rows": []
		}

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for index in range(header.size()):
		var column_name: String = str(
			header[index]
		).strip_edges()

		if column_name.is_empty():
			continue

		if indexes.has(column_name):
			file.close()

			_data_error(
				"중복 CSV 열: "
				+ path
				+ " / "
				+ column_name
			)

			return {
				"success": false,
				"rows": []
			}

		indexes[column_name] = index

	for column in required_headers:
		if indexes.has(column):
			continue

		file.close()

		_data_error(
			"필수 CSV 열 없음: "
				+ path
				+ " / "
				+ column
		)

		return {
			"success": false,
			"rows": []
		}

	var rows: Array[Dictionary] = []
	var line_number: int = 1

	while file.get_position() < file.get_length():
		var raw_row: PackedStringArray = (
			file.get_csv_line()
		)

		line_number += 1

		if _is_empty_row(raw_row):
			continue

		var row: Dictionary = {}

		for column in required_headers:
			var column_index: int = int(
				indexes[column]
			)

			if column_index >= raw_row.size():
				file.close()

				_data_error(
					"CSV 열 수 부족: "
						+ path
						+ " / 줄 "
						+ str(line_number)
				)

				return {
					"success": false,
					"rows": []
				}

			row[column] = str(
				raw_row[column_index]
			).strip_edges()

		rows.append(row)

	file.close()

	return {
		"success": true,
		"rows": rows
	}


func _is_empty_row(
	row: PackedStringArray
) -> bool:
	if row.is_empty():
		return true

	if row.size() != 1:
		return false

	return row[0].strip_edges().is_empty()


func _is_valid_bool_text(
	value: String
) -> bool:
	return (
		value == "true"
		or value == "false"
	)


func _data_error(
	message: String
) -> bool:
	push_error(
		"[ExpeditionEquipmentData] "
		+ message
	)

	return false
