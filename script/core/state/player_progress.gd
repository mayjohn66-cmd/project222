class_name PlayerProgress
extends RefCounted


# 플레이어의 진행 기록(배운 레시피, 지역별 난이도 클리어)을 담는다.
# GameState는 새 게임 초기화와 저장·불러오기에서만 이 클래스를 호출한다.

static var learned_recipe_ids: Dictionary = {}
static var cleared_difficulty: Dictionary = {}
static var starter_scroll_granted: bool = false


static func reset() -> void:
	learned_recipe_ids.clear()
	cleared_difficulty.clear()
	starter_scroll_granted = false


# =========================
# 레시피
# =========================

static func is_recipe_learned(
	recipe_id: String
) -> bool:
	return learned_recipe_ids.has(recipe_id)


# 새로 배웠으면 true, 이미 알고 있으면 false.
static func learn_recipe(
	recipe_id: String
) -> bool:
	if recipe_id.is_empty():
		return false

	if learned_recipe_ids.has(recipe_id):
		return false

	learned_recipe_ids[recipe_id] = true

	return true


# =========================
# 첫 원정 두루마리
# =========================

# 아직 첫 두루마리를 받지 않았고 배운 레시피도 없으면 지급 대기 중이다.
static func is_starter_scroll_pending() -> bool:
	return (
		not starter_scroll_granted
		and learned_recipe_ids.is_empty()
	)


static func mark_starter_scroll_granted() -> void:
	starter_scroll_granted = true


# =========================
# 난이도 해금
# =========================

static func get_cleared_difficulty(
	region_id: String
) -> int:
	return int(
		cleared_difficulty.get(
			region_id,
			0
		)
	)


# 난이도 1은 항상 열려 있다. 그 위 난이도는 바로 아래 난이도를 클리어해야 열린다.
static func is_difficulty_unlocked(
	region_id: String,
	difficulty: int
) -> bool:
	if difficulty <= ExpeditionDifficultyData.MIN_LEVEL:
		return true

	return get_cleared_difficulty(region_id) >= difficulty - 1


static func get_highest_unlocked_difficulty(
	region_id: String
) -> int:
	return mini(
		get_cleared_difficulty(region_id) + 1,
		ExpeditionDifficultyData.get_max_level()
	)


static func record_clear(
	region_id: String,
	difficulty: int
) -> void:
	if region_id.is_empty():
		return

	if difficulty > get_cleared_difficulty(region_id):
		cleared_difficulty[region_id] = difficulty


# =========================
# 저장·불러오기
# =========================

static func to_save_data() -> Dictionary:
	return {
		"learned_recipe_ids": learned_recipe_ids.keys(),
		"cleared_difficulty": cleared_difficulty.duplicate(true),
		"starter_scroll_granted": starter_scroll_granted
	}


static func load_save_data(
	data: Dictionary
) -> void:
	reset()

	var saved_recipes: Variant = data.get(
		"learned_recipe_ids",
		[]
	)

	if saved_recipes is Array:
		for recipe_id in saved_recipes:
			learned_recipe_ids[str(recipe_id)] = true

	starter_scroll_granted = bool(
		data.get(
			"starter_scroll_granted",
			false
		)
	)

	var saved_clears: Variant = data.get(
		"cleared_difficulty",
		{}
	)

	if saved_clears is Dictionary:
		for region_id in saved_clears.keys():
			cleared_difficulty[str(region_id)] = int(
				saved_clears[region_id]
			)
