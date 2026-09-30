class_name ItemCatalog
extends RefCounted

static var ITEMS: Dictionary = load_items_from_csv()


static func load_items_from_csv() -> Dictionary:
	var result: Dictionary = {}
	var path := "res://data/core/items.csv"

	if not FileAccess.file_exists(path):
		push_error("아이템 CSV 파일을 찾을 수 없음: " + path)
		return result

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_error("아이템 CSV 열기 실패: " + path)
		return result

	# 첫 줄 헤더
	var headers := file.get_csv_line()

	for i in range(headers.size()):
		headers[i] = headers[i].strip_edges()

	var storage_column: int = headers.find(
		"expedition_storage"
	)

	var inventory_group_column: int = headers.find(
		"inventory_group"
	)

	var rarity_column: int = headers.find(
		"rarity"
	)

	while not file.eof_reached():
		var row := file.get_csv_line()

		if row.is_empty():
			continue

		# 빈 줄 방지
		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue

		if row.size() < 13:
			push_warning("CSV 열 개수가 부족한 행 발견: " + str(row))
			continue

		var item_id := row[0].strip_edges()

		if item_id.is_empty():
			continue

		var icon_path := row[9].strip_edges()
		var icon: Texture2D = null

		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			icon = load(icon_path)

		var expedition_storage: String = "bag"

		if storage_column >= 0 and storage_column < row.size():
			var storage_value: String = (
				row[storage_column].strip_edges().to_lower()
			)

			if not storage_value.is_empty():
				expedition_storage = storage_value

		var item_type: String = (
			row[2].strip_edges()
		)

		var inventory_group: String = (
			_get_default_inventory_group(
				item_type
			)
		)

		if (
			inventory_group_column >= 0
			and inventory_group_column < row.size()
		):
			var group_value: String = (
				row[inventory_group_column]
				.strip_edges()
				.to_lower()
			)

			if not group_value.is_empty():
				inventory_group = group_value


		# 희귀도(재료 1~3, 그 외 0). 열이 없거나 비어 있으면 0.
		var rarity: int = 0

		if rarity_column >= 0 and rarity_column < row.size():
			var rarity_text: String = row[rarity_column].strip_edges()

			if rarity_text.is_valid_int():
				rarity = int(rarity_text)

		result[item_id] = {
			"name": row[1].strip_edges(),
			"item_type": row[2].strip_edges(),
			"category": row[3].strip_edges(),
			"price": int(row[4]),
			"bag_size": Vector2i(
				int(row[5]),
				int(row[6])
			),
			"shelf_allowed": _csv_to_bool(row[7]),
			"sellable": _csv_to_bool(row[8]),
			"icon": icon,
			"description": row[10].strip_edges(),
			"attack": int(row[11]),
			"defense": int(row[12]),
			"expedition_storage": expedition_storage,
			"inventory_group": inventory_group,
			"rarity": rarity
		}

	return result

static func _get_default_inventory_group(
	item_type: String
) -> String:
	match item_type:
		"equipment", \
		"expedition_consumable", \
		"special":
			return "expedition"

		_:
			return "shelf"

static func _csv_to_bool(value: String) -> bool:
	return value.strip_edges().to_lower() == "true"
