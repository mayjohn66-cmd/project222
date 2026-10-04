class_name CraftingPathFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_crafting_path.tres")
const PREFIX := "crafting_path:"
const JOURNAL_PREFIX := "crafting:"
const NEW_GAME := "tutorial_event:crafting_path_v1"

static func stage(id: String) -> Dictionary:
	for entry in SETTINGS.stages:
		if entry["id"] == id: return entry
	return {}
static func key(id: String, suffix: String) -> String: return PREFIX + id + ":" + suffix
static func accepted(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"accepted"))
static func done(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"done"))
static func title(id: String) -> String: return RequestTextData.text("service_text",id + "_intro","title","이웃과 제품 만들기")
static func current() -> Dictionary:
	for entry in SETTINGS.stages:
		if not done(str(entry["id"])): return entry
	return {}

static func recipe_ready(recipe_id: String) -> bool:
	# 이전 저장은 기존 제조법 접근을 유지한다. 새 게임에서만 현대 상품 재현을 뒤에 둔다.
	if not PlayerProgress.story_beat_days.has(NEW_GAME) or not SETTINGS.gated_recipes.has(recipe_id): return true
	for entry in SETTINGS.stages:
		if entry.get("modern_products", false): return accepted(str(entry["id"])) or done(str(entry["id"]))
	return false

static func locked_reason(entry: Dictionary) -> String:
	if entry.is_empty(): return "함께 만들 제품을 찾을 수 없습니다."
	if not ResidentRequestFlow.tutorial_finished(): return "첫 거래와 원정 재료 판매를 마친 뒤 이어집니다."
	var giver := str(entry["giver"])
	if not VillageLifeFlow.available(VillageLifeFlow.resident(giver)): return "이웃의 정착을 먼저 도와 주세요."
	if accepted(str(entry["id"])) or done(str(entry["id"])): return ""
	if current().get("id", "") != entry["id"]: return "앞선 제품 이야기를 먼저 마쳐 주세요."
	if not PlayerProgress.story_beat_days.has("tutorial_step:production:done"): return "현지식 빵을 처음 구워 수령한 뒤 타블렌을 만나세요."
	if VillageLifeFlow.friendship(giver) < int(entry["friendship"]): return "%s와 안부를 조금 더 나눠 주세요. [%d/%d일]" % [VillageLifeFlow.resident(giver)["name"],VillageLifeFlow.friendship(giver),entry["friendship"]]
	var after := str(entry.get("after", ""))
	if not after.is_empty():
		if not done(after): return "앞선 제품 이야기를 먼저 마쳐 주세요."
		if GameState.total_day < int(PlayerProgress.story_beat_days[key(after,"done")]) + int(entry.get("days_after",1)):
			return "앞선 시제품을 나눈 뒤 조금 쉬었다가 다시 만나요."
	return ""

static func accept(id: String) -> bool:
	var entry := stage(id)
	if accepted(id) or done(id) or not locked_reason(entry).is_empty(): return false
	# 잘못된 설정이면 일부 제조법만 주지 않는다.
	for recipe in entry["recipes"]:
		if ProductRecipeData.get_recipe(str(recipe)).is_empty(): return false
	for item in entry["requirements"]:
		if not ItemData.has_item(str(item["item"])) or int(item["amount"]) <= 0: return false
	PlayerProgress.record_story_beat(key(id,"accepted"),GameState.total_day)
	for recipe in entry["recipes"]: PlayerProgress.learn_recipe(str(recipe))
	return true

static func crafted(id: String, item: String) -> int:
	return maxi(0,int(PlayerProgress.story_beat_days.get(key(id,"crafted:" + item),0)))

static func record_output(item: String, amount: int) -> void:
	if amount <= 0: return
	var entry := current()
	if entry.is_empty() or not accepted(str(entry["id"])) or not locked_reason(entry).is_empty(): return
	for requirement in entry["requirements"]:
		if str(requirement["item"]) != item: continue
		var id := str(entry["id"])
		PlayerProgress.story_beat_days[key(id,"crafted:" + item)] = mini(int(requirement["amount"]),crafted(id,item) + amount)

static func ready(id: String) -> bool:
	var entry := stage(id)
	if entry.is_empty() or not accepted(id) or done(id) or not locked_reason(entry).is_empty(): return false
	for item in entry["requirements"]:
		var name := str(item["item"])
		if not ItemData.has_item(name) or int(item["amount"]) <= 0: return false
		if crafted(id,name) < int(item["amount"]) or GameState.get_item_count(name) < int(item["amount"]): return false
	return not entry["requirements"].is_empty()

static func finish(id: String) -> bool:
	if not ready(id): return false
	var entry := stage(id)
	for item in entry["requirements"]: GameState.remove_item(str(item["item"]),int(item["amount"]))
	PlayerProgress.record_story_beat(key(id,"done"),GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:crafting/" + id] = maxi(0,int(entry["reputation"]))
	return true

static func action(giver: String) -> Dictionary:
	var entry := current()
	if entry.is_empty() or entry["giver"] != giver or not locked_reason(entry).is_empty(): return {}
	var id := str(entry["id"])
	var moment := "intro" if not accepted(id) else ("finish" if ready(id) else "preparing")
	return {"flow":"crafting_path","event":id,"resident":giver,"stage":moment,"id":id + "_" + moment}

static func complete_action(entry: Dictionary) -> bool:
	if entry.is_empty() or entry != action(str(entry.get("resident",""))): return false
	match str(entry["stage"]):
		"intro": return accept(str(entry["event"]))
		"finish": return finish(str(entry["event"]))
	return false

static func description(id: String) -> String:
	var entry := stage(id)
	if entry.is_empty(): return ""
	var result := "배운 제조법: " if accepted(id) else "함께 배울 제조법: "
	var products: Array[String] = []
	for recipe in entry["recipes"]:
		products.append(ItemData.get_item_name(str(ProductRecipeData.get_recipe(str(recipe)).get("result_item_id",""))))
	result += " · ".join(products) + "\n"
	if not accepted(id): return result + "이웃과 소개 대화를 끝까지 읽으면 제조법을 배웁니다. [E]"
	for item in entry["requirements"]:
		var name := str(item["item"])
		result += "%s · 소개 후 제작 수령 %d/%d · 창고 %d/%d\n" % [ItemData.get_item_name(name),crafted(id,name),item["amount"],GameState.get_item_count(name),item["amount"]]
	return result + "제작한 시제품을 창고에 준비하고 이웃에게 다시 이야기하세요. [E]"

static func information(id: String) -> String:
	if stage(id).is_empty(): return ""
	if done(id): return "함께 만든 날: %d일차\n%s" % [PlayerProgress.story_beat_days[key(id,"done")],RequestTextData.text("service_text",id + "_finish","completion")]
	var reason := locked_reason(stage(id))
	return reason if not reason.is_empty() else description(id)
