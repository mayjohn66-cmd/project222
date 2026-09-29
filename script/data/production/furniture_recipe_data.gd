class_name FurnitureRecipeData
extends RefCounted

const DATA_PATH: String = "res://data/production/furniture_recipes.csv"

static var recipes: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_error("[가구 레시피] 파일 열기 실패: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()

	if (
		header.size() != 3
		or header[0].strip_edges() != "furniture_id"
		or header[1].strip_edges() != "item_id"
		or header[2].strip_edges() != "amount"
	):
		file.close()
		push_error("[가구 레시피] CSV 헤더를 확인해주세요.")
		return

	var loaded_recipes: Dictionary = {}
	var line_number: int = 1

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		line_number += 1

		if row.is_empty():
			continue

		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue

		if row.size() != 3:
			file.close()
			push_error(
				"[가구 레시피] 열 수 오류 / 줄: " + str(line_number)
			)
			return

		var furniture_id: String = row[0].strip_edges()
		var item_id: String = row[1].strip_edges()
		var amount_text: String = row[2].strip_edges()

		if furniture_id.is_empty():
			file.close()
			push_error(
				"[가구 레시피] furniture_id가 비어 있음 / 줄: "
				+ str(line_number)
			)
			return

		if not FurnitureData.has_furniture(furniture_id):
			file.close()
			push_error(
				"[가구 레시피] FurnitureData에 없는 가구 / 줄: %d / ID: %s"
				% [line_number, furniture_id]
			)
			return

		if not BuildObjectData.has_build_object(furniture_id):
			file.close()
			push_error(
				"[가구 레시피] BuildObjectData에 없는 가구 / 줄: %d / ID: %s"
				% [line_number, furniture_id]
			)
			return

		if not ItemData.has_item(item_id):
			file.close()
			push_error(
				"[가구 레시피] ItemData에 없는 재료 / 줄: %d / ID: %s"
				% [line_number, item_id]
			)
			return

		if not amount_text.is_valid_int():
			file.close()
			push_error(
				"[가구 레시피] 수량이 정수가 아님 / 줄: %d / 값: %s"
				% [line_number, amount_text]
			)
			return

		var amount: int = int(amount_text)

		if amount <= 0:
			file.close()
			push_error(
				"[가구 레시피] 수량은 1 이상이어야 합니다 / 줄: "
				+ str(line_number)
			)
			return

		if not loaded_recipes.has(furniture_id):
			loaded_recipes[furniture_id] = {
				"furniture_id": furniture_id,
				"ingredients": []
			}

		var recipe: Dictionary = loaded_recipes[furniture_id]
		var ingredients: Array = recipe["ingredients"]

		ingredients.append({
			"item_id": item_id,
			"amount": amount
		})

	file.close()

	# 파일 전체 검사가 끝난 뒤 적용
	recipes = loaded_recipes
	_loaded = true


static func get_recipe(furniture_id: String) -> Dictionary:
	ensure_loaded()

	if not recipes.has(furniture_id):
		return {}

	return recipes[furniture_id].duplicate(true)


static func get_all_furniture_ids() -> Array[String]:
	ensure_loaded()

	var result: Array[String] = []

	for raw_id in recipes:
		result.append(str(raw_id))

	return result
