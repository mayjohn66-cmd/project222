class_name EnemyData
extends RefCounted


const CSV_PATH: String = (
	"res://data/expedition/enemies.csv"
)


static var enemies: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_csv()

	_loaded = true

	print(
		"[EnemyData] 로드 완료 / 몬스터: ",
		enemies.size()
	)


static func reload() -> void:
	enemies.clear()
	_loaded = false

	ensure_loaded()


static func has_enemy(
	enemy_id: String
) -> bool:
	ensure_loaded()

	return enemies.has(
		enemy_id
	)


static func get_enemy(
	enemy_id: String
) -> Dictionary:
	ensure_loaded()

	if not enemies.has(
		enemy_id
	):
		push_warning(
			"[EnemyData] 없는 몬스터: "
			+ enemy_id
		)

		return {}

	return enemies[enemy_id].duplicate(
		true
	)


static func get_loot_table(
	enemy_id: String
) -> String:
	var enemy: Dictionary = (
		get_enemy(enemy_id)
	)

	if enemy.is_empty():
		return ""

	return str(
		enemy.get(
			"loot_table",
			""
		)
	)


static func _load_csv() -> void:
	enemies.clear()

	if not FileAccess.file_exists(
		CSV_PATH
	):
		push_error(
			"[EnemyData] CSV 없음: "
			+ CSV_PATH
		)
		return

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[EnemyData] CSV 열기 실패"
		)
		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for i in range(
		header.size()
	):
		indexes[
			header[i].strip_edges()
		] = i

	var required_headers: Array[String] = [
		"id",
		"name",
		"max_hp",
		"attack",
		"defense",
		"loot_table"
	]

	for column_name in required_headers:
		if not indexes.has(
			column_name
		):
			push_error(
				"[EnemyData] CSV 열 없음: "
				+ column_name
			)
			return

	while (
		file.get_position()
		< file.get_length()
	):
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		if row.is_empty():
			continue

		var enemy_id := _get_cell(
			row,
			indexes,
			"id"
		)

		if enemy_id.is_empty():
			continue

		enemies[enemy_id] = {
			"name": _get_cell(
				row,
				indexes,
				"name"
			),

			"max_hp": int(
				_get_cell(
					row,
					indexes,
					"max_hp"
				)
			),

			"attack": int(
				_get_cell(
					row,
					indexes,
					"attack"
				)
			),

			"defense": int(
				_get_cell(
					row,
					indexes,
					"defense"
				)
			),

			"loot_table": _get_cell(
				row,
				indexes,
				"loot_table"
			)
		}


static func _get_cell(
	row: PackedStringArray,
	indexes: Dictionary,
	column_name: String
) -> String:
	if not indexes.has(
		column_name
	):
		return ""

	var index: int = int(
		indexes[column_name]
	)

	if index < 0:
		return ""

	if index >= row.size():
		return ""

	return row[index].strip_edges()
