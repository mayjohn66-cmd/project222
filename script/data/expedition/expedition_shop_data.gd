class_name ExpeditionShopData
extends RefCounted


const CATEGORY_WEAPON := "weapon"
const CATEGORY_ARMOR := "armor"
const CATEGORY_TOOL := "tool"
const CATEGORY_ETC := "etc"

const CSV_PATH := "res://data/expedition/expedition_shop.csv"


static var ENTRIES: Dictionary = _load_csv()


static func _load_csv() -> Dictionary:
	var result: Dictionary = {}

	if not FileAccess.file_exists(CSV_PATH):
		push_error("원정 상점 CSV 파일을 찾을 수 없음: " + CSV_PATH)
		return result

	var file := FileAccess.open(CSV_PATH, FileAccess.READ)

	if file == null:
		push_error("원정 상점 CSV 열기 실패: " + CSV_PATH)
		return result

	# 첫 줄 헤더 건너뛰기
	file.get_csv_line()

	while not file.eof_reached():
		var row := file.get_csv_line()

		if row.is_empty():
			continue

		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue

		if row.size() < 4:
			push_warning("원정 상점 CSV 열 부족: " + str(row))
			continue

		var item_id := row[0].strip_edges()

		if item_id.is_empty():
			continue

		result[item_id] = {
			"item_id": item_id,
			"shop_category": row[1].strip_edges(),
			"price": int(row[2]),
			"available": _csv_to_bool(row[3])
		}

	return result


static func _csv_to_bool(value: String) -> bool:
	return value.strip_edges().to_lower() == "true"


static func has_item(item_id: String) -> bool:
	return ENTRIES.has(item_id)


static func get_entry(item_id: String) -> Dictionary:
	return ENTRIES.get(item_id, {})


static func get_price(item_id: String) -> int:
	var entry := get_entry(item_id)

	if entry.is_empty():
		return 0

	return int(entry.get("price", 0))


static func get_items_by_category(category: String) -> Array[String]:
	var result: Array[String] = []

	for item_id in ENTRIES:
		var entry: Dictionary = ENTRIES[item_id]

		if not bool(entry.get("available", false)):
			continue

		if entry.get("shop_category", "") != category:
			continue

		result.append(item_id)

	return result
