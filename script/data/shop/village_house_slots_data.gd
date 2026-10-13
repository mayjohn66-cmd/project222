class_name VillageHouseSlotsData
extends RefCounted
## 주민 집터 슬롯을 CSV에서 읽는다(`data/shop/catalogs/village/house_slots.csv`). 좌표는 지도 편집기에서 보며 고친다.

const PATH: String = "res://data/shop/catalogs/village/house_slots.csv"

static var slots: Array[Dictionary] = []   # {id, cell, ring}, 가까운 고리·파일 순서
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	slots.clear()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("[VillageHouseSlotsData] 파일 없음: " + PATH)
		return
	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}
	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		var id: String = CsvReader.get_cell(row, indexes, "slot_id")
		if id.is_empty() or id.begins_with("#"):
			continue
		slots.append({
			"id": id,
			"cell": Vector2i(int(CsvReader.get_cell(row, indexes, "cell_x")), int(CsvReader.get_cell(row, indexes, "cell_y"))),
			"ring": int(CsvReader.get_cell(row, indexes, "ring")),
		})
	# 안쪽 고리부터. 같은 고리는 파일 순서를 유지한다(안정 정렬).
	var ordered: Array[Dictionary] = []
	for ring in range(1, 10):
		for slot in slots:
			if int(slot["ring"]) == ring:
				ordered.append(slot)
	slots = ordered


static func reload_data() -> void:
	_loaded = false
	ensure_loaded()


static func find(slot_id: String) -> Dictionary:
	ensure_loaded()
	for slot in slots:
		if slot["id"] == slot_id:
			return slot
	return {}
