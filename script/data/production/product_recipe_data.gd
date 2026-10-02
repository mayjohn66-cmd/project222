class_name ProductRecipeData
extends RefCounted


const RECIPE_PATH := (
	"res://data/production/product_recipes.csv"
)

const INGREDIENT_PATH := (
	"res://data/production/product_recipe_ingredients.csv"
)


static var recipes: Dictionary = {}

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	load_data()


static func load_data() -> void:
	recipes.clear()

	_load_recipes()
	_load_ingredients()

	_loaded = true

	DebugLog.write(
		"[ProductRecipeData] 로드 완료 / 레시피 수: ",
		recipes.size()
	)


static func _load_recipes() -> void:
	if not FileAccess.file_exists(RECIPE_PATH):
		push_error(
			"[ProductRecipeData] 파일 없음: "
			+ RECIPE_PATH
		)
		return

	var file := FileAccess.open(
		RECIPE_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[ProductRecipeData] 열기 실패: "
			+ RECIPE_PATH
		)
		return

	# 헤더 건너뛰기
	if not file.eof_reached():
		file.get_csv_line()

	while not file.eof_reached():
		var row := file.get_csv_line()

		if row.is_empty():
			continue

		if row.size() < 5:
			continue

		var recipe_id := str(
			row[0]
		).strip_edges()

		if recipe_id.is_empty():
			continue

		recipes[recipe_id] = {
			"recipe_id": recipe_id,
			"result_item_id": str(
				row[1]
			).strip_edges(),
			"result_amount": int(
				row[2]
			),
			"facility_id": str(
				row[3]
			).strip_edges(),
			"craft_time": int(
				row[4]
			),
			"ingredients": []
		}


static func _load_ingredients() -> void:
	if not FileAccess.file_exists(
		INGREDIENT_PATH
	):
		push_error(
			"[ProductRecipeData] 파일 없음: "
			+ INGREDIENT_PATH
		)
		return

	var file := FileAccess.open(
		INGREDIENT_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[ProductRecipeData] 열기 실패: "
			+ INGREDIENT_PATH
		)
		return

	# 헤더 건너뛰기
	if not file.eof_reached():
		file.get_csv_line()

	while not file.eof_reached():
		var row := file.get_csv_line()

		if row.is_empty():
			continue

		if row.size() < 3:
			continue

		var recipe_id := str(
			row[0]
		).strip_edges()

		if not recipes.has(recipe_id):
			push_warning(
				"[ProductRecipeData] 없는 레시피의 재료: "
				+ recipe_id
			)
			continue

		var ingredient := {
			"item_id": str(
				row[1]
			).strip_edges(),
			"amount": int(
				row[2]
			)
		}

		recipes[recipe_id][
			"ingredients"
		].append(
			ingredient
		)


static func get_recipe(
	recipe_id: String
) -> Dictionary:
	ensure_loaded()

	if not recipes.has(recipe_id):
		return {}

	return recipes[
		recipe_id
	].duplicate(true)


static func get_all_recipes() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for recipe in recipes.values():
		result.append(
			recipe.duplicate(true)
		)

	return result

# 배운 레시피(또는 잠금 대상이 아닌 레시피)만 돌려준다.
static func get_learned_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for recipe in get_all_recipes():
		if RecipeUnlockData.is_recipe_available(
			str(recipe.get("recipe_id", ""))
		):
			result.append(recipe)

	return result
