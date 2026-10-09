class_name ProductNextStepGuidance
extends RefCounted
# The book describes the next real action; reading never learns, builds or collects.
const ENABLED := true
const FIRST_RECIPE := "camp_bread"

static func opening() -> String:
	if not ShopSpaceProgression.active() or ShopSpaceProgression.production_introduced(): return ""
	if not OpeningJourneyFlow.core_finished():
		return "먼저 현재 가게 안내를 따라 진열과 직접 계산을 익혀 보세요. 원정에서 가져온 재료는 가공하지 않고 그대로 팔아도 됩니다."
	if not ShopSpaceProgression.production_offered():
		return "지금은 원정 재료를 그대로 진열하고 이웃의 부탁을 들어 보세요. 타블렌이 노점을 마련하면 첫 제작을 배울 수 있습니다."
	return "타블렌에게 [E]로 첫 제작 안내를 들어 보세요. 화덕과 현지식 빵 제조법 두루마리를 받은 뒤 생산실을 마련합니다."

static func first_steps() -> bool:
	return not opening().is_empty() or owned_first_scroll()

static func empty_title() -> String:
	if owned_first_scroll(): return "받은 제조법부터 배워 보세요."
	if first_steps(): return "가게를 돌보며 첫 제작을 준비해 보세요."
	return "오늘 필요한 것을 천천히 준비해 보세요."

static func first_scroll() -> String:
	RecipeUnlockData.ensure_loaded()
	return str(RecipeUnlockData.by_recipe.get(FIRST_RECIPE,{}).get("scroll_item_id",""))

static func owned_first_scroll() -> bool:
	var id := first_scroll()
	return (ShopSpaceProgression.active() and ShopSpaceProgression.production_introduced()
		and not PlayerProgress.is_recipe_learned(FIRST_RECIPE)
		and not id.is_empty() and GameState.get_item_count(id) > 0)

static func empty_message(mode: String, filtered: bool) -> String:
	var start := opening()
	if not start.is_empty(): return start
	if owned_first_scroll():
		return "받은 현지식 빵 제조법 두루마리를 인벤토리에서 선택하고 ‘배우기’를 누르세요. 배우면 이 책에 필요한 재료와 설비가 나타납니다."
	if mode == "today" and filtered:
		return "지금 바로 만들 수 있는 상품이 없습니다. ‘지금 만들 수 있는 상품만’을 해제해 부족한 재료와 설비 상태를 확인하세요."
	if mode == "facilities" and not ProductRecipeData.get_learned_recipes().is_empty():
		return "아직 사용할 설비가 없습니다. 먼저 생산실 화덕에서 현지식 빵을 만들어 수령하면 다음 설비를 준비할 수 있습니다."
	return "아직 배운 제조법이 없습니다. 이웃과 교류하거나 얻은 제조법 두루마리를 인벤토리에서 사용해 보세요. 원정 재료는 그대로 진열할 수 있습니다."

static func facility_action(world: Node, entry: Dictionary) -> String:
	var node = entry["node"]
	if is_instance_valid(node):
		match node.production_state:
			ProductionFacility.ProductionState.PROCESSING:
				return "책을 닫고 가공이 끝나길 기다리세요. 책을 열어 둔 동안 가공도 멈춥니다. 완료 후 같은 설비에서 [E]로 수령합니다."
			ProductionFacility.ProductionState.READY:
				return "책을 닫고 완성된 설비에서 [E]로 완성품을 수령하세요."
		return "책을 닫고 설치한 설비에서 [E]로 배운 제조법을 선택하세요."
	var start := opening()
	if not start.is_empty(): return start
	if ShopSpaceProgression.active() and not ShopSpaceProgression.room_ready("production"):
		return "건설 탭에서 생산실 문을 준비해 가게 벽에 배치하세요. 설비는 생산실을 마련한 뒤 그 안에 설치합니다."
	if ShopSpaceProgression.active() and not ShopSpaceProgression.marked("production_entered"):
		return "책을 닫고 생산실 문에서 [E]로 들어가세요. 방 안에 필요한 설비를 설치합니다."
	var id := str(entry["facility_id"])
	if GameState.get_furniture_count(id) > 0:
		return "보유한 설비가 있습니다. 책을 닫고 생산실에서 건축 모드 [B]로 설치하세요."
	return "설계도에서 필요한 설비의 제작 조건을 확인하세요. 준비한 설비는 생산실에서 건축 모드 [B]로 설치합니다."
