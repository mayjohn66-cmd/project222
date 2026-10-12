class_name FurnitureObjectCatalog
extends RefCounted
## 새로 만드는 집기의 재질·발전 조건·창고 규격. 이미 소유한 집기의 설치는 제한하지 않는다.

const PATH := "res://data/shop/catalogs/furniture/furniture_progression.csv"
const PREFIX := "furniture_craft:"
const PRODUCT_STORY_PREFIX := "crafting_path:"
static var _rows: Dictionary = {}
static var _loaded := false

static func get_object(id: String) -> Dictionary:
	if not _loaded: _load()
	return (_rows.get(id, {}) as Dictionary).duplicate(true)

static func all_ids() -> Array:
	if not _loaded: _load()
	return _rows.keys()

static func _load() -> void:
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("[가구 카탈로그] 파일 없음: " + PATH)
		return
	var header := file.get_csv_line()
	for field in ["id", "family", "stage", "requires_stage", "requires_story", "unlock_hint", "storage_capacity", "storage_slots", "material"]:
		if not header.has(field):
			push_error("[가구 카탈로그] 필수 열 없음: " + field)
			return
	var loaded: Dictionary = {}
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() == 1 and cells[0].strip_edges().is_empty(): continue
		if cells.size() != header.size():
			push_error("[가구 카탈로그] 열 수 오류")
			return
		var row: Dictionary = {}
		for i in range(header.size()): row[header[i]] = cells[i].strip_edges()
		var id := str(row.get("id", ""))
		if id.is_empty() or loaded.has(id) or not FurnitureData.has_furniture(id) or not BuildObjectData.has_build_object(id):
			push_error("[가구 카탈로그] 중복 또는 미등록 가구: " + id)
			return
		if not ["wood", "reinforced", "modern"].has(row["stage"]) or not ["", "wood", "reinforced"].has(row["requires_stage"]):
			push_error("[가구 카탈로그] 발전 단계 오류: " + id)
			return
		if str(row["family"]) != BuildObjectData.get_build_type(id) or FurnitureRecipeData.get_recipe(id).is_empty():
			push_error("[가구 카탈로그] 기능 분류 또는 제작법 오류: " + id)
			return
		if (not str(row["requires_stage"]).is_empty() or not str(row["requires_story"]).is_empty()) and str(row["unlock_hint"]).is_empty():
			push_error("[가구 카탈로그] 해금 안내 없음: " + id)
			return
		for field in ["storage_capacity", "storage_slots"]:
			if not str(row[field]).is_valid_int() or int(row[field]) < 0:
				push_error("[가구 카탈로그] 창고 규격 오류: " + id)
				return
			row[field] = int(row[field])
		if (int(row["storage_capacity"]) > 0) != (int(row["storage_slots"]) > 0):
			push_error("[가구 카탈로그] 창고 용량/칸 수 조합 오류: " + id)
			return
		loaded[id] = row
	_rows = loaded

static func locked_reason(id: String) -> String:
	if not ShopSpaceProgression.furniture_visible(id): return "가게의 다음 공간을 마련한 뒤 만들 수 있습니다."
	var row := get_object(id)
	if row.is_empty(): return ""
	var stage := str(row["requires_stage"])
	var story := str(row["requires_story"])
	if (not stage.is_empty() and not PlayerProgress.story_beat_days.has(PREFIX + stage)) or (not story.is_empty() and not PlayerProgress.story_beat_days.has(PRODUCT_STORY_PREFIX + story + ":done")):
		return str(row["unlock_hint"])
	return ""

static func craft(id: String) -> bool:
	if not locked_reason(id).is_empty(): return false
	if not FurnitureData.has_furniture(id) or not BuildObjectData.has_build_object(id): return false
	var recipe := FurnitureRecipeData.get_recipe(id)
	if recipe.is_empty() or not ProductionRecipeService.consume_ingredients(recipe, 1): return false
	GameState.add_furniture(id, 1)
	ActFourRecords.record_furniture(id,1)
	var row := get_object(id)
	if not row.is_empty(): PlayerProgress.record_story_beat(PREFIX + str(row["stage"]), GameState.total_day)
	else: PlayerProgress.record_story_beat(PREFIX + id, GameState.total_day)  # 발전 단계에 없는 집기(간이 진열대 등)도 처음 제작을 기록한다
	return true

static func detail(id: String) -> String:
	var row := get_object(id)
	if row.is_empty(): return ""
	var data := BuildObjectData.get_build_object(id)
	var size: Vector2i = data["grid_size"]
	var lines: Array[String] = ["", "[집기 정보]", "재질: %s · 설치 크기: %d×%d칸" % [row["material"], size.x, size.y]]
	var shelf := ShelfData.get_shelf_data(id)
	if not shelf.is_empty():
		lines.append("한 층 %d칸 · 칸마다 %d개 · 최대 %d층" % [shelf["slots_per_level"], shelf["slot_capacity"], shelf["max_stack_level"]])
	if int(row["storage_capacity"]) > 0:
		lines.append("총 보관량 %d개 · 보관 슬롯 %d칸" % [row["storage_capacity"], row["storage_slots"]])
	var reason := locked_reason(id)
	lines.append("제작 가능" if reason.is_empty() else "해금 조건: " + reason)
	return "\n".join(lines)

static func configure_storage(storage: Node, id: String) -> void:
	var row := get_object(id)
	if row.is_empty() or int(row["storage_capacity"]) <= 0: return
	storage.set("storage_capacity", int(row["storage_capacity"]))
	storage.set("storage_slot_count", int(row["storage_slots"]))
