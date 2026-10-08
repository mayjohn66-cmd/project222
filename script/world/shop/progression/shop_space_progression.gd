class_name ShopSpaceProgression
extends RefCounted

# 공간은 기존 씬을 사용하며, 새 게임에서 실제 문을 설치해야 사용할 수 있다.
const PREFIX := "shop_space:"
const VERSION := PREFIX + "v1"
# 관리 책의 탭(생산·건설·직원)과 설계도 분류 탭을 초반부터 모두 연다(2026-10-08 결정).
# 되돌리려면 false. 가구 하나하나의 공개(furniture_visible)와 공간 단계(생산실·창고 마련)는 이 값과 상관없이 그대로다.
const UNLOCK_ALL_TABS := true

static func active() -> bool:
	return PlayerProgress.story_beat_days.has(VERSION)

static func marked(key: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + key)

static func mark(key: String) -> void:
	if active(): PlayerProgress.record_story_beat(PREFIX + key, GameState.total_day)

static func adopt_tutorial_save(world: Node) -> void:
	if active() or not PlayerProgress.story_beat_days.has(OpeningJourneyFlow.VERSION): return
	# 이미 제작/공간 사용을 시작한 저장에는 새 잠금을 소급하지 않는다.
	if PlayerProgress.story_beat_days.has("tutorial_step:production:intro") or GameState.get_store_expansion_level() > 1 \
		or GameState.get_production_room_expansion_level() > 1 or GameState.get_warehouse_expansion_level() > 1: return
	for entry in GameState.get_store_layout():
		if str(entry.get("room_id", "store")) != "store" or str(entry.get("build_id", "")) in ["production_door", "warehouse_door"]: return
	for path in ["ProductionRoom/Objects", "WarehouseRoom/Objects"]:
		var objects := world.get_node_or_null(path)
		if objects != null and objects.get_child_count() > 0: return
	for object in world.get_node("Objects").get_children():
		if str(object.get_meta("build_id", "")) in ["production_door", "warehouse_door"]: return
	PlayerProgress.record_story_beat(VERSION, GameState.total_day)

static func production_offered() -> bool:
	return not active() or OpeningJourneyFlow.optional_available({"id":"production", "after_request":"settle_naru"})

static func production_introduced() -> bool:
	return not active() or PlayerProgress.story_beat_days.has("tutorial_step:production:intro")

static func room_ready(room: String) -> bool:
	return not active() or marked(room)

static func first_product() -> bool:
	return not active() or (room_ready("production") and PlayerProgress.story_beat_days.has("tutorial_event:produced_bread"))

static func expansion_ready() -> bool:
	return not active() or (room_ready("warehouse") and marked("stored"))

static func category_visible(category: String) -> bool:
	if not active() or UNLOCK_ALL_TABS: return true
	match category:
		"production": return production_introduced()
		"interior": return first_product()
		"construction": return production_introduced()
	return true

static func furniture_visible(id: String) -> bool:
	if not active(): return true
	match BuildObjectData.get_build_type(id):
		"production_door": return production_introduced()
		"warehouse_door": return first_product()
		"warehouse_storage": return room_ready("warehouse")
		"production_facility": return production_introduced() and (id == "magic_oven" or first_product())
		"decoration": return first_product()
	return true

static func placed(id: String, objects: Node) -> void:
	# 미리보기·실패·다른 방에 설치한 문은 공간 생성으로 기록하지 않는다.
	if not active() or objects.get_parent().get_node_or_null("DayManager") == null: return
	if id == "production_door" and production_introduced(): mark("production")
	if id == "warehouse_door" and first_product(): mark("warehouse")

static func can_install(id: String, objects: Node) -> bool:
	if not furniture_visible(id): return false
	if not active(): return true
	match BuildObjectData.get_build_type(id):
		"production_facility": return objects.get_parent().name == "ProductionRoom" and room_ready("production")
		"warehouse_storage": return objects.get_parent().name == "WarehouseRoom" and room_ready("warehouse")
		"production_door", "warehouse_door": return objects.get_parent().get_node_or_null("DayManager") != null
	return true

static func furniture_purpose(id: String) -> String:
	match BuildObjectData.get_build_type(id):
		"production_door": return "\n[공간 안내]\n가게 벽에 설치하여 생산실을 연결합니다. 설비를 놓고 재료를 상품으로 가공하는 공간입니다."
		"warehouse_door": return "\n[공간 안내]\n가게 벽에 설치하여 창고를 연결합니다. 보관 선반을 놓고 남은 재료를 정리하는 공간입니다."
		"production_facility": return "\n[설비 사용]\n생산실에 배치하고 [E]로 배운 제조법을 선택합니다. 가공 후 완성품을 수령하여 진열하세요."
		"warehouse_storage": return "\n[보관 사용]\n창고에 배치하고 [E]로 재료를 넣고 꺼냅니다. 선반에 보관한 재료는 꺼내야 제작·진열에 사용할 수 있습니다."
		"decoration": return "\n[치장 사용]\n편의점에 배치하여 가게 분위기를 꾸밉니다. 손님·평판에 주는 실제 효과는 아래 효과 안내에서 확인하세요."
	return ""

static func entered(room: String) -> void:
	if room_ready(room): mark(room + "_entered")

static func deposited(storage: Node, amount: int) -> void:
	if amount > 0 and room_ready("warehouse") and marked("warehouse_entered") \
		and storage.get_parent().get_parent().name == "WarehouseRoom": mark("stored")

static func phase() -> String:
	if not active() or expansion_ready(): return "expand"
	if not production_introduced(): return "store"
	if not room_ready("production"): return "make_production"
	if not first_product(): return "produce"
	if not room_ready("warehouse"): return "make_warehouse"
	return "store_materials"

static func preparation() -> Dictionary:
	match phase():
		"store": return {"title":"편의점에서 시작하기", "current":"먼저 직접 진열하고 손님을 계산해 보세요.", "next":"원정 재료를 팔고 이웃과 교류하면 제작을 배울 수 있습니다.", "note":"타블렌의 첫 제작 안내를 들으면 생산실을 마련할 수 있습니다.", "door":""}
		"make_production": return {"title":"생산실 마련", "current":"재료를 가공할 첫 공간을 준비합니다.", "next":"가게 벽에 생산실 문을 설치하세요. 문을 설치하면 기본 생산실이 연결됩니다.", "note":"함께 온 문을 사용합니다. 화덕과 제조법은 타블렌의 제작 안내에서 받습니다.", "door":"production_door"}
		"produce": return {"title":"생산실에서 첫 상품 만들기", "current":"생산실을 마련했습니다.", "next":"문에서 [E]로 들어가 화덕을 설치하고 현지식 빵을 만들어 수령하세요.", "note":"실제 완성품을 수령하면 다음 공간인 창고를 마련할 수 있습니다.", "door":""}
		"make_warehouse": return {"title":"창고 마련", "current":"첫 상품을 만들었습니다. 남은 재료를 정리할 자리를 마련해 봅시다.", "next":"가게 벽에 창고 문을 설치하세요. 문을 설치하면 기본 창고가 연결됩니다.", "note":"일반 소지 재고는 지금도 사용할 수 있습니다. 창고 선반에 넣은 재료는 꺼내서 사용합니다.", "door":"warehouse_door"}
	return {"title":"창고에 재료 정리하기", "current":"창고를 마련했습니다.", "next":"문에서 [E]로 들어가 창고 선반을 설치하고 재료를 한 번 넣어 보세요.", "note":"창고 사용을 익히면 편의점·생산실·창고의 확장 안내가 열립니다.", "door":""}

static func begin_room_build(menu: Node, door: String) -> bool:
	if door not in ["production_door", "warehouse_door"] or not furniture_visible(door) or GameState.get_furniture_count(door) < 1: return false
	var managers := menu.get_tree().get_nodes_in_group("build_manager")
	if managers.is_empty(): return false
	var builder = managers[0]
	if builder.player.in_production_room or builder.player.in_warehouse_room: return false
	menu.close_menu()
	if menu.visible:
		menu.visibility_changed.connect(func():
			if not menu.visible: ShopSpaceProgression._start_room_build.call_deferred(builder, door)
		, CONNECT_ONE_SHOT)
	else: ShopSpaceProgression._start_room_build.call_deferred(builder, door)
	return true

static func _start_room_build(builder: Node, door: String) -> void:
	if not is_instance_valid(builder) or not furniture_visible(door) or GameState.get_furniture_count(door) < 1: return
	builder.start_build_mode()
	if not builder.build_mode: return
	# 기존 퀵슬롯을 덮어쓰지 않고 보유한 문의 배치 미리보기를 선택한다.
	builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(door), 0)
	builder.create_preview()
