class_name ExpeditionDifficultyData
extends RefCounted


# 원정 난이도 레벨별 규칙(방 개수, 몬스터 배율, 보상 배율)을 CSV에서 읽는다.
# 방 개수에는 보스 방이 포함되며 시작 지점은 포함하지 않는다.
# 난이도는 지역(던전)과 별개다. 어떤 지역이든 같은 난이도 규칙을 쓴다.

const CSV_PATH: String = (
	"res://data/expedition/expedition_difficulty.csv"
)

const MIN_LEVEL: int = 1
const DEFAULT_ROOM_COUNT: int = 6

static var levels: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	_load_csv()


static func reload() -> void:
	levels.clear()
	_loaded = false
	ensure_loaded()


static func get_max_level() -> int:
	ensure_loaded()

	var max_level: int = MIN_LEVEL

	for level in levels.keys():
		max_level = maxi(max_level, int(level))

	return max_level


static func clamp_level(level: int) -> int:
	return clampi(level, MIN_LEVEL, get_max_level())


static func get_room_count(level: int) -> int:
	return int(_get_value(level, "room_count", DEFAULT_ROOM_COUNT))


static func get_monster_hp_mult(level: int) -> float:
	return float(_get_value(level, "monster_hp_mult", 1.0))


static func get_monster_atk_mult(level: int) -> float:
	return float(_get_value(level, "monster_atk_mult", 1.0))


static func get_reward_amount_mult(level: int) -> float:
	return float(_get_value(level, "reward_amount_mult", 1.0))


static func get_rare_chance_mult(level: int) -> float:
	return float(_get_value(level, "rare_chance_mult", 1.0))


static func _get_value(
	level: int,
	key: String,
	fallback
):
	ensure_loaded()

	if not levels.has(level):
		return fallback

	return levels[level].get(key, fallback)


static func _load_csv() -> void:
	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[원정 난이도] CSV 열기 실패: " + CSV_PATH
		)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	if not indexes.has("difficulty") or not indexes.has("room_count"):
		push_error(
			"[원정 난이도] CSV 열 없음: difficulty, room_count"
		)
		file.close()
		return

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()

		var level_text: String = CsvReader.get_cell(
			row, indexes, "difficulty"
		)

		if level_text.is_empty():
			continue

		var room_count_text: String = CsvReader.get_cell(
			row, indexes, "room_count"
		)

		if not level_text.is_valid_int() or not room_count_text.is_valid_int():
			push_error(
				"[원정 난이도] 값 오류: " + level_text
			)
			continue

		levels[int(level_text)] = {
			"room_count": maxi(int(room_count_text), 2),
			"monster_hp_mult": _get_float(
				row, indexes, "monster_hp_mult", 1.0
			),
			"monster_atk_mult": _get_float(
				row, indexes, "monster_atk_mult", 1.0
			),
			"reward_amount_mult": _get_float(
				row, indexes, "reward_amount_mult", 1.0
			),
			"rare_chance_mult": _get_float(
				row, indexes, "rare_chance_mult", 1.0
			)
		}

	file.close()

	DebugLog.write(
		"[ExpeditionDifficultyData] 로드 완료 / 난이도 수: ",
		levels.size()
	)


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
