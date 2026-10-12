class_name ShelfData
extends RefCounted


const DATA_PATH: String = (
	"res://data/shop/catalogs/furniture/shelf_data.csv"
)


static var shelves: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	load_data()


static func load_data() -> void:
	shelves.clear()

	if not FileAccess.file_exists(DATA_PATH):
		push_error(
			"[ShelfData] 파일 없음: "
			+ DATA_PATH
		)
		return

	var file := FileAccess.open(
		DATA_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[ShelfData] 파일 열기 실패: "
			+ DATA_PATH
		)
		return

	# 헤더 건너뛰기
	if not file.eof_reached():
		file.get_csv_line()

	while not file.eof_reached():
		var row := file.get_csv_line()

		if row.is_empty():
			continue

		if row.size() < 4:
			push_warning(
				"[ShelfData] 잘못된 행: "
				+ str(row)
			)
			continue

		var shelf_id: String = str(
			row[0]
		).strip_edges()

		if shelf_id.is_empty():
			continue

		var slots_per_level: int = int(
			row[1]
		)

		var slot_capacity: int = int(
			row[2]
		)

		var max_stack_level: int = int(
			row[3]
		)

		if slots_per_level <= 0:
			push_error(
				"[ShelfData] 잘못된 slots_per_level: "
				+ shelf_id
			)
			continue

		if slot_capacity <= 0:
			push_error(
				"[ShelfData] 잘못된 slot_capacity: "
				+ shelf_id
			)
			continue

		if max_stack_level <= 0:
			push_error(
				"[ShelfData] 잘못된 max_stack_level: "
				+ shelf_id
			)
			continue

		shelves[shelf_id] = {
			"id": shelf_id,
			"slots_per_level": slots_per_level,
			"slot_capacity": slot_capacity,
			"max_stack_level": max_stack_level
		}

	_loaded = true

	DebugLog.write(
		"[ShelfData] 로드 완료 / 진열대 수: ",
		shelves.size()
	)


static func has_shelf(
	shelf_id: String
) -> bool:
	ensure_loaded()

	return shelves.has(
		shelf_id
	)


static func get_shelf_data(
	shelf_id: String
) -> Dictionary:
	ensure_loaded()

	if not shelves.has(
		shelf_id
	):
		return {}

	return shelves[
		shelf_id
	].duplicate(true)


static func get_slots_per_level(
	shelf_id: String
) -> int:
	var data := get_shelf_data(
		shelf_id
	)

	return int(
		data.get(
			"slots_per_level",
			0
		)
	)


static func get_max_stack_level(
	shelf_id: String
) -> int:
	var data := get_shelf_data(
		shelf_id
	)

	return int(
		data.get(
			"max_stack_level",
			1
		)
	)
