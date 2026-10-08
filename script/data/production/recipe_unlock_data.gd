class_name RecipeUnlockData
extends RefCounted


# 레시피와 그 레시피를 배우는 두루마리 아이템의 연결을 CSV에서 읽는다.
# 여기에 등록된 레시피는 두루마리를 사용해서 배우기 전까지 잠겨 있다.

const CSV_PATH: String = (
	"res://data/production/recipe_unlocks.csv"
)

const KIND_PRODUCT: String = "product"
const KIND_EQUIPMENT: String = "equipment"

# recipe_id -> {"kind": String, "scroll_item_id": String}
static var by_recipe: Dictionary = {}
# scroll_item_id -> recipe_id
static var by_scroll: Dictionary = {}
# 첫 원정에서 반드시 주는 기본 음식 제작 두루마리(starter 열이 true인 행)
static var starter_scroll_item_id: String = ""
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	_load_csv()


static func reload() -> void:
	by_recipe.clear()
	by_scroll.clear()
	starter_scroll_item_id = ""
	_loaded = false
	ensure_loaded()


# 잠금 대상이 아닌 레시피는 항상 사용할 수 있다.
static func is_recipe_available(
	recipe_id: String
) -> bool:
	ensure_loaded()

	if not CraftingPathFlow.recipe_ready(recipe_id) or not VillageExpansionFlow.recipe_ready(recipe_id): return false
	if not FishingRecords.recipe_available(recipe_id): return false
	if not by_recipe.has(recipe_id):
		return true

	return PlayerProgress.is_recipe_learned(recipe_id)


static func get_recipe_id_for_scroll(
	scroll_item_id: String
) -> String:
	ensure_loaded()

	return str(
		by_scroll.get(
			scroll_item_id,
			""
		)
	)


static func is_scroll(
	item_id: String
) -> bool:
	return not get_recipe_id_for_scroll(item_id).is_empty()


# 드롭에서 나올 가치가 있는 두루마리인지. 이미 배운 레시피이거나
# 이미 그 두루마리를 가지고 있으면 더 나올 필요가 없다.
# 두루마리가 아닌 아이템은 항상 true.
static func is_scroll_worth_dropping(
	item_id: String
) -> bool:
	var recipe_id: String = get_recipe_id_for_scroll(item_id)

	if recipe_id.is_empty():
		return true
	if not CraftingPathFlow.recipe_ready(recipe_id): return false

	if PlayerProgress.is_recipe_learned(recipe_id):
		return false

	return GameState.get_item_count(item_id) <= 0


static func get_starter_scroll_item_id() -> String:
	ensure_loaded()

	return starter_scroll_item_id


static func get_all_scroll_item_ids() -> Array[String]:
	ensure_loaded()

	var result: Array[String] = []

	for scroll_item_id in by_scroll.keys():
		result.append(str(scroll_item_id))

	return result


static func _load_csv() -> void:
	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[레시피 해금] CSV 열기 실패: " + CSV_PATH
		)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	for column_name in ["recipe_id", "recipe_kind", "scroll_item_id"]:
		if not indexes.has(column_name):
			push_error(
				"[레시피 해금] CSV 열 없음: " + column_name
			)
			file.close()
			return

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()

		var recipe_id: String = CsvReader.get_cell(
			row, indexes, "recipe_id"
		)

		if recipe_id.is_empty():
			continue

		var scroll_item_id: String = CsvReader.get_cell(
			row, indexes, "scroll_item_id"
		)

		if scroll_item_id.is_empty():
			push_error(
				"[레시피 해금] 두루마리 아이템이 비어 있음: " + recipe_id
			)
			continue

		by_recipe[recipe_id] = {
			"kind": CsvReader.get_cell(row, indexes, "recipe_kind"),
			"scroll_item_id": scroll_item_id
		}
		by_scroll[scroll_item_id] = recipe_id

		if CsvReader.get_cell(row, indexes, "starter").to_lower() == "true":
			starter_scroll_item_id = scroll_item_id

	file.close()
