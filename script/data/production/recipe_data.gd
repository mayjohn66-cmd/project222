class_name RecipeData
extends RefCounted

const CSV_PATH: String = "res://data/production/recipes.csv"

static var recipes: Dictionary = {}
static var _loaded: bool = false


# =========================
# 로드
# =========================

static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = _load_csv()

	if _loaded:
		print(
			"[RecipeData] 로드 완료 / 제작법: ",
			recipes.size()
		)


static func reload() -> void:
	recipes.clear()
	_loaded = false
	ensure_loaded()


# =========================
# 제작법 조회
# =========================

static func has_recipe(recipe_id: String) -> bool:
	ensure_loaded()
	return recipes.has(recipe_id)


static func get_recipe(recipe_id: String) -> Dictionary:
	ensure_loaded()

	if not recipes.has(recipe_id):
		return {}

	return recipes[recipe_id].duplicate(true)


static func get_all_recipes() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for recipe in recipes.values():
		result.append(recipe.duplicate(true))

	return result

static func get_recipe_by_result_item(
	item_id: String
) -> Dictionary:
	ensure_loaded()

	if item_id.is_empty():
		return {}

	for recipe_data in recipes.values():
		if not recipe_data is Dictionary:
			continue

		if str(
			recipe_data.get(
				"result_item_id",
				""
			)
		) != item_id:
			continue

		return recipe_data.duplicate(
			true
		)

	return {}

static func get_dismantle_refund(
	item_id: String,
	refund_ratio: float = 0.5
) -> Dictionary:
	var recipe: Dictionary = (
		get_recipe_by_result_item(
			item_id
		)
	)

	if recipe.is_empty():
		return {}

	var result_amount: int = int(
		recipe.get(
			"result_amount",
			1
		)
	)

	if result_amount <= 0:
		return {}

	var materials: Array = recipe.get(
		"materials",
		[]
	)

	if materials.is_empty():
		return {}

	var safe_ratio: float = clampf(
		refund_ratio,
		0.0,
		1.0
	)

	var refund: Dictionary = {}

	var fallback_item_id: String = ""
	var fallback_source_amount: int = 0

	for raw_material_data in materials:
		if not raw_material_data is Dictionary:
			continue

		var material_data: Dictionary = (
			raw_material_data
		)

		var material_id: String = str(
			material_data.get(
				"item_id",
				""
			)
		)

		var source_amount: int = int(
			material_data.get(
				"amount",
				0
			)
		)

		if (
			material_id.is_empty()
			or source_amount <= 0
		):
			continue

		if source_amount > fallback_source_amount:
			fallback_item_id = material_id
			fallback_source_amount = source_amount

		var amount_per_result: float = (
			float(source_amount)
			/ float(result_amount)
		)

		var refund_amount: int = floori(
			amount_per_result
			* safe_ratio
		)

		if refund_amount <= 0:
			continue

		refund[material_id] = refund_amount

	# 모든 재료가 0개가 되는 작은 레시피 보호
	if (
		refund.is_empty()
		and not fallback_item_id.is_empty()
	):
		refund[fallback_item_id] = 1

	return refund

# =========================
# CSV 읽기
# =========================

static func _load_csv() -> bool:
	recipes.clear()

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[RecipeData] CSV 열기 실패: " + CSV_PATH
		)
		return false

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	var required_headers: Array[String] = [
		"recipe_id",
		"result_item_id",
		"result_amount",
		"material_1",
		"amount_1",
		"material_2",
		"amount_2"
	]

	for column_name in required_headers:
		if not indexes.has(column_name):
			push_error(
				"[RecipeData] CSV 열 없음: " + column_name
			)
			file.close()
			return false

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()

		var recipe_id: String = _get_cell(
			row, indexes, "recipe_id"
		)

		if recipe_id.is_empty():
			continue

		if recipes.has(recipe_id):
			push_warning(
				"[RecipeData] 중복 제작법: " + recipe_id
			)
			continue

		var result_item_id: String = _get_cell(
			row, indexes, "result_item_id"
		)

		var result_amount_text: String = _get_cell(
			row, indexes, "result_amount"
		)

		if (
			not ItemData.has_item(result_item_id)
			or not result_amount_text.is_valid_int()
			or int(result_amount_text) <= 0
		):
			push_warning(
				"[RecipeData] 잘못된 완성품 정보: "
				+ recipe_id
			)
			continue

		var materials: Array[Dictionary] = []
		var materials_valid: bool = true

		for material_index in range(1, 3):
			var item_id: String = _get_cell(
				row,
				indexes,
				"material_%d" % material_index
			)

			var amount_text: String = _get_cell(
				row,
				indexes,
				"amount_%d" % material_index
			)

			# 사용하지 않는 재료 칸은 빈 값 또는 0 허용
			if item_id.is_empty():
				if (
					not amount_text.is_empty()
					and amount_text != "0"
				):
					materials_valid = false
					break

				continue

			if not amount_text.is_valid_int():
				materials_valid = false
				break

			if not _add_material(
				materials,
				item_id,
				int(amount_text)
			):
				materials_valid = false
				break

		# 재료 없는 제작법도 등록하지 않음
		if not materials_valid or materials.is_empty():
			push_warning(
				"[RecipeData] 잘못된 재료 정보 / 등록 제외: "
				+ recipe_id
			)
			continue

		recipes[recipe_id] = {
			"recipe_id": recipe_id,
			"result_item_id": result_item_id,
			"result_amount": int(result_amount_text),
			"materials": materials
		}

	file.close()
	return true


# =========================
# 제작 가능 여부
# =========================

static func can_craft(recipe_id: String) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)

	if recipe.is_empty():
		return false

	var result_item_id: String = str(
		recipe.get("result_item_id", "")
	)

	var result_amount: int = int(
		recipe.get("result_amount", 0)
	)

	if not ItemData.has_item(result_item_id):
		return false

	if result_amount <= 0:
		return false

	var materials: Array = recipe.get("materials", [])

	if materials.is_empty():
		return false

	for material in materials:
		var item_id: String = str(material["item_id"])
		var required_amount: int = int(material["amount"])

		if not ItemData.has_item(item_id):
			return false

		if required_amount <= 0:
			return false

		if GameState.get_item_count(item_id) < required_amount:
			return false

	return true


static func get_missing_materials(
	recipe_id: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var recipe: Dictionary = get_recipe(recipe_id)

	if recipe.is_empty():
		return result

	var materials: Array = recipe.get("materials", [])

	for material in materials:
		var item_id: String = str(material["item_id"])
		var required_amount: int = int(material["amount"])
		var owned_amount: int = GameState.get_item_count(item_id)

		if owned_amount >= required_amount:
			continue

		result.append({
			"item_id": item_id,
			"required": required_amount,
			"owned": owned_amount,
			"missing": required_amount - owned_amount
		})

	return result


# =========================
# 실제 제작
# =========================

static func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		print(
			"[제작] 제작 불가 / 재료 또는 데이터 확인: ",
			recipe_id
		)
		return false

	var recipe: Dictionary = get_recipe(recipe_id)
	var materials: Array = recipe["materials"]
	var consumed: Dictionary = {}

	for material in materials:
		var item_id: String = str(material["item_id"])
		var amount: int = int(material["amount"])

		var removed_amount: int = GameState.remove_item(
			item_id,
			amount
		)

		consumed[item_id] = (
			int(consumed.get(item_id, 0))
			+ removed_amount
		)

		if removed_amount != amount:
			# 이번 제작에서 실제 차감한 수량만 반환
			for consumed_item_id in consumed:
				var refund_amount: int = int(
					consumed[consumed_item_id]
				)

				if refund_amount > 0:
					GameState.add_item(
						consumed_item_id,
						refund_amount
					)

			push_error(
				"[제작] 재료 차감 실패 / 차감분 반환: "
				+ recipe_id
			)
			return false

	var result_item_id: String = str(
		recipe["result_item_id"]
	)

	var result_amount: int = int(
		recipe["result_amount"]
	)

	GameState.add_item(
		result_item_id,
		result_amount
	)

	print(
		"[제작 성공] ",
		ItemData.get_item_name(result_item_id),
		" ×",
		result_amount
	)

	return true


# =========================
# 재료 검사 및 합산
# =========================

static func _add_material(
	materials: Array[Dictionary],
	item_id: String,
	amount: int
) -> bool:
	if not ItemData.has_item(item_id):
		return false

	if amount <= 0:
		return false

	# 같은 재료는 한 항목으로 합산
	for material in materials:
		if str(material["item_id"]) == item_id:
			material["amount"] = (
				int(material["amount"]) + amount
			)
			return true

	materials.append({
		"item_id": item_id,
		"amount": amount
	})

	return true


static func _get_cell(
	row: PackedStringArray,
	indexes: Dictionary,
	column_name: String
) -> String:
	if not indexes.has(column_name):
		return ""

	var index: int = int(indexes[column_name])

	if index < 0 or index >= row.size():
		return ""

	return row[index].strip_edges()
