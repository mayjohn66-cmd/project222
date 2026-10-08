class_name FurnitureUnlockNotice
extends RefCounted

# 진행 단계 때문에 가려져 있던 가구가 열리는 순간을 알려 준다.
# 숨겨진 상태를 본 가구만 기록해 두고, 나중에 보이게 되면 한 번만 "새로 열림"으로 돌려준다
# (처음부터 보이던 가구에는 알림이 뜨지 않는다). 기록은 저장되는 PlayerProgress.story_beat_days 에 둔다.

const HIDDEN_PREFIX := "furniture_hidden:"
const ANNOUNCED_PREFIX := "furniture_announced:"


# 지금 가진 가구(퀵슬롯 + 가방) 번호들. 중복 없이.
static func owned_ids() -> Array[String]:
	var ids: Array[String] = []

	for i in range(GameState.BUILD_QUICK_SLOT_COUNT):
		var slot_id: String = GameState.get_build_quick_slot(i)

		if not slot_id.is_empty() and not ids.has(slot_id):
			ids.append(slot_id)

	for raw_id in GameState.get_furniture_inventory_ids():
		var id: String = str(raw_id)

		if GameState.get_furniture_count(id) > 0 and not ids.has(id):
			ids.append(id)

	return ids


# 가려진 가구를 기록한다.
static func observe() -> void:
	for id in owned_ids():
		if not ShopSpaceProgression.furniture_visible(id):
			var key: String = HIDDEN_PREFIX + id

			if not PlayerProgress.story_beat_days.has(key):
				PlayerProgress.record_story_beat(key, GameState.total_day)


# 기록해 둔 가려진 가구 중 이제 보이는데 아직 알리지 않은 것. 알림 처리를 마친 것으로 기록한다.
static func collect_new() -> Array[String]:
	var found: Array[String] = []

	for id in owned_ids():
		var hidden_key: String = HIDDEN_PREFIX + id
		var announced_key: String = ANNOUNCED_PREFIX + id

		if (
			PlayerProgress.story_beat_days.has(hidden_key)
			and not PlayerProgress.story_beat_days.has(announced_key)
			and ShopSpaceProgression.furniture_visible(id)
		):
			PlayerProgress.record_story_beat(announced_key, GameState.total_day)
			found.append(id)

	return found
