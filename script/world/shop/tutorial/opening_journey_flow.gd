class_name OpeningJourneyFlow
extends RefCounted

# 진행 키는 기존 저장 구조를 사용한다. 새 게임의 물품과 기존 저장을 섞지 않는다.
const SETTINGS = preload("res://scenes/shop/tutorial/default_tutorial.tres")
const VERSION := "tutorial_event:arrival_v2"
const TRADE := "tutorial_event:arrival_barter"
const RAW_SALE := "tutorial_event:raw_material_sale"

static func legacy_finished() -> bool:
	if PlayerProgress.story_beat_days.has(VERSION): return false
	# 이전판에서 제작에 도달했다면 새 도입부를 다시 강제하지 않는다.
	return PlayerProgress.story_beat_days.has("tutorial_step:production:intro") \
		or PlayerProgress.story_beat_days.has("tutorial_step:production:done")

static func core_finished() -> bool:
	if legacy_finished(): return true
	for step in SETTINGS.steps:
		if not bool(step.get("optional", false)) \
				and not PlayerProgress.story_beat_days.has("tutorial_step:" + str(step["id"]) + ":done"):
			return false
	return true

static func optional_available(step: Dictionary) -> bool:
	return PlayerProgress.story_beat_days.has("tutorial_step:" + str(step["id"]) + ":intro") \
		or (core_finished() and ResidentRequestFlow.done(str(step.get("after_request", ""))))

static func initialize(world: Node) -> void:
	# 저장된 배치나 이전 도입부 기록이 있으면 아무것도 재배치/지급하지 않는다.
	if PlayerProgress.story_beat_days.has(VERSION) or GameState.has_store_layout() or GameState.has_player_state(): return
	for key in PlayerProgress.story_beat_days:
		if str(key).begins_with("tutorial_step:"): return
	if GameState.total_day != 1 or world.get_node("Objects").get_child_count() != 0: return
	for entry in SETTINGS.opening_layout:
		if GameState.get_furniture_count(str(entry["build_id"])) < 1: return
	world.get_node("BuildManager")._restore_current_area_layout(SETTINGS.opening_layout)
	for entry in SETTINGS.opening_layout:
		GameState.remove_furniture(str(entry["build_id"]), 1)
	GameState.save_store_layout(SETTINGS.opening_layout.duplicate(true))
	PlayerProgress.record_story_beat(VERSION, GameState.total_day)
	# 부트스트랩은 제작/주민 흐름의 클래스 의존 순환을 만들지 않는다.
	PlayerProgress.record_story_beat("tutorial_event:crafting_path_v1", GameState.total_day)

static func traded() -> bool:
	return PlayerProgress.story_beat_days.has(TRADE)

static func can_trade() -> bool:
	if traded(): return false
	if not PlayerProgress.story_beat_days.has("tutorial_step:barter:intro"): return false
	if not PlayerProgress.story_beat_days.has("tutorial_step:checkout:done") \
			or PlayerProgress.story_beat_days.has("tutorial_step:barter:done"): return false
	for item in SETTINGS.barter_requirements:
		if not ItemData.has_item(str(item["id"])) or int(item["amount"]) <= 0: return false
		if GameState.get_item_count(str(item["id"])) < int(item["amount"]): return false
	for gift in SETTINGS.barter_gifts:
		if not ItemData.has_item(str(gift["id"])) or int(gift["amount"]) <= 0: return false
	return true

static func trade() -> bool:
	if not can_trade(): return false
	# 검증이 모두 끝난 뒤 창고 식품만 소비한다. 거래는 재입력/재로드해도 한 번이다.
	for item in SETTINGS.barter_requirements:
		GameState.remove_item(str(item["id"]), int(item["amount"]))
	for gift in SETTINGS.barter_gifts:
		var id := str(gift["id"])
		var amount := int(gift["amount"])
		if bool(gift.get("missing_only", false)): amount = maxi(0, amount - GameState.get_item_count(id))
		if amount > 0: GameState.add_item(id, amount)
	PlayerProgress.record_story_beat(TRADE, GameState.total_day)
	return true

static func is_raw_material(id: String) -> bool:
	return str(ItemData.get_item(id).get("item_type", "")) == ItemData.ITEM_TYPE_MATERIAL \
		and ItemData.get_sellable_items().has(id) and ItemData.get_item_price(id) > 0
