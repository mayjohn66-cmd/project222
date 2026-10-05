class_name PlayerProgress
extends RefCounted


# 플레이어의 진행 기록(배운 레시피, 지역별 난이도 클리어)을 담는다.
# GameState는 새 게임 초기화와 저장·불러오기에서만 이 클래스를 호출한다.

static var learned_recipe_ids: Dictionary = {}
static var cleared_difficulty: Dictionary = {}
static var starter_scroll_granted: bool = false
static var expeditions_completed: int = 0
# 스토리 장면(비트)이 마지막으로 발생한 날. 없으면 아직 발생하지 않음.
static var story_beat_days: Dictionary = {}
# 새 게임을 시작하기 전에 짓는 플레이어(점장) 이름. 관리 창 표지 등에 표시한다. 비어 있으면 기본 호칭을 쓴다.
static var player_name: String = ""
const PLAYER_NAME_MAX := 8
const DEFAULT_PLAYER_NAME := "점장"


static func reset() -> void:
	learned_recipe_ids.clear()
	cleared_difficulty.clear()
	starter_scroll_granted = false
	expeditions_completed = 0
	story_beat_days.clear()
	player_name = ""


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
# 원정 완료와 스토리 장면
# =========================

static func record_expedition_completed() -> void:
	expeditions_completed += 1


static func has_completed_expedition() -> bool:
	return expeditions_completed > 0


# repeat_days가 0이면 한 번만, 그 외에는 마지막 발생 후 그 일수가 지나야 다시 가능하다.
static func can_play_story_beat(
	beat_id: String,
	repeat_days: int,
	today: int
) -> bool:
	if not story_beat_days.has(beat_id):
		return true

	if repeat_days <= 0:
		return false

	return today - int(story_beat_days[beat_id]) >= repeat_days


static func record_story_beat(
	beat_id: String,
	today: int
) -> void:
	story_beat_days[beat_id] = today


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
		"starter_scroll_granted": starter_scroll_granted,
		"expeditions_completed": expeditions_completed,
		"story_beat_days": story_beat_days.duplicate(true),
		"player_name": player_name
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

	expeditions_completed = maxi(
		int(
			data.get(
				"expeditions_completed",
				0
			)
		),
		0
	)

	player_name = clean_player_name(str(data.get("player_name","")))

	var saved_beats: Variant = data.get(
		"story_beat_days",
		{}
	)

	if saved_beats is Dictionary:
		for beat_id in saved_beats.keys():
			story_beat_days[str(beat_id)] = int(
				saved_beats[beat_id]
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


# 이름에서 앞뒤 공백을 걷고 최대 글자 수로 자른다.
static func clean_player_name(raw: String) -> String:
	return raw.strip_edges().substr(0,PLAYER_NAME_MAX)


# 화면에 보여 줄 이름(짓지 않았으면 기본 호칭).
static func display_player_name() -> String:
	return player_name if not player_name.is_empty() else DEFAULT_PLAYER_NAME
