class_name ExpeditionTierData
extends RefCounted


# 지역별 티어 정보(방 개수, 몬스터·재료 배율)를 CSV에서 읽는다.
# 방 개수에는 보스 방이 포함되며 시작 지점은 포함하지 않는다.

const CSV_PATH: String = (
	"res://data/expedition/expedition_tiers.csv"
)

const DEFAULT_ROOM_COUNT: int = 6

static var tiers: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	_load_csv()


static func reload() -> void:
	tiers.clear()
	_loaded = false
	ensure_loaded()


static func get_room_count(region_id: String) -> int:
	ensure_loaded()

	if not tiers.has(region_id):
		return DEFAULT_ROOM_COUNT

	return int(tiers[region_id].get("room_count", DEFAULT_ROOM_COUNT))


static func get_tier(region_id: String) -> int:
	ensure_loaded()

	if not tiers.has(region_id):
		return 1

	return int(tiers[region_id].get("tier", 1))


static func get_monster_hp_mult(region_id: String) -> float:
	ensure_loaded()

	if not tiers.has(region_id):
		return 1.0

	return float(tiers[region_id].get("monster_hp_mult", 1.0))


static func get_monster_atk_mult(region_id: String) -> float:
	ensure_loaded()

	if not tiers.has(region_id):
		return 1.0

	return float(tiers[region_id].get("monster_atk_mult", 1.0))


static func _load_csv() -> void:
	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[원정 티어] CSV 열기 실패: " + CSV_PATH
		)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	if not indexes.has("region_id") or not indexes.has("room_count"):
		push_error(
			"[원정 티어] CSV 열 없음: region_id, room_count"
		)
		file.close()
		return

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()

		var region_id: String = CsvReader.get_cell(
			row, indexes, "region_id"
		)

		if region_id.is_empty():
			continue

		var room_count_text: String = CsvReader.get_cell(
			row, indexes, "room_count"
		)

		if not room_count_text.is_valid_int():
			push_error(
				"[원정 티어] room_count 값 오류: " + region_id
			)
			continue

		tiers[region_id] = {
			"tier": _get_int(row, indexes, "tier", 1),
			"room_count": maxi(int(room_count_text), 2),
			"monster_hp_mult": _get_float(
				row, indexes, "monster_hp_mult", 1.0
			),
			"monster_atk_mult": _get_float(
				row, indexes, "monster_atk_mult", 1.0
			)
		}

	file.close()

	DebugLog.write(
		"[ExpeditionTierData] 로드 완료 / 지역: ",
		tiers.size()
	)


static func _get_int(
	row: PackedStringArray,
	indexes: Dictionary,
	column_name: String,
	fallback: int
) -> int:
	var text: String = CsvReader.get_cell(row, indexes, column_name)

	if not text.is_valid_int():
		return fallback

	return int(text)


static func _get_float(
	row: PackedStringArray,
	indexes: Dictionary,
	column_name: String,
	fallback: float
) -> float:
	var text: String = CsvReader.get_cell(row, indexes, column_name)

	if not text.is_valid_float():
		return fallback

	return float(text)
