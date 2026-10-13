extends Node
## 시험판: 첫 주민 부탁(neighbor_bread)이 NPC의 '손님 입장'으로 건네지는지 확인한다.
var failures := 0
var checks := 0
var world
var manager
var player
var visit: QuestVisitDirector
var residents

func check(ok: bool, caption: String) -> void:
	checks += 1
	if ok: print("PASS: ", caption)
	else:
		failures += 1
		push_error(caption)

func drain(panel: StoryDialoguePanel) -> void:
	for i in range(60):
		if not panel.open: return
		panel._advance()
	check(false, "dialogue must terminate")

func frames(count: int = 3) -> void:
	for i in range(count): await get_tree().process_frame

func _ready() -> void:
	CheckoutOptions.force_for_test(true)  # 시험은 스캔 없이 시간 결제(스캔은 check_manual_checkout)
	call_deferred("run")

func run() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # 튜토리얼 이후 상태에서 시험한다
	add_child(world)
	await frames(4)
	manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	world.get_node("CustomerSpawner").set_process(false)
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	visit = world.get_node("QuestVisitDirector")
	residents = world.get_node("ResidentRequestDirector")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	var layout: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(0,4), "rotation_index":3},
		{"build_id":"register", "anchor":Vector2i(4,3), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0,
		"shelf_slots":[{"item_id":"water", "stock":3, "capacity":5}]}]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	await frames(2)
	var request := ResidentRequestFlow.current()
	check(QuestVisitDirector.covers_request("neighbor_bread") and str(request.get("id", "")) == "neighbor_bread", "first resident request is the pilot")
	check(not QuestVisitDirector.pending_request().is_empty(), "pilot request is waiting to be delivered by a visit")
	# 영업 전: 기존 서 있는 NPC가 대신한다(손님 입장은 열리지 않는다)
	residents.refresh()
	check(not QuestVisitDirector.replaces_standing_npc(world) and is_instance_valid(residents.npc), "before opening the standing NPC still covers the request")
	visit.try_start()
	check(not is_instance_valid(visit.guide), "no visit while the shop is closed")
	# 영업 중: 서 있는 NPC는 사라지고 손님으로 입장한다
	manager.open_shop()
	await frames(2)
	residents.refresh()
	check(QuestVisitDirector.replaces_standing_npc(world), "while open the visit replaces the standing NPC")
	check(not is_instance_valid(residents.npc) or residents.npc.is_queued_for_deletion() or not residents.npc.visible, "standing NPC steps away while open")
	visit.try_start()
	check(is_instance_valid(visit.guide) and visit.stage == "intro", "the neighbor walks in as a customer and speaks")
	check(visit.dialogue.open and visit.dialogue._speaker == str(request["npc"]), "the quest giver speaks as himself")
	check(not ResidentRequestFlow.accepted("neighbor_bread"), "request is not accepted before the talk is finished")
	check(manager.hour_timer.paused and not player.is_physics_processing(), "dialogue pauses the clock and the player")
	drain(visit.dialogue)
	check(not ResidentRequestFlow.accepted("neighbor_bread") and visit.stage == "offer", "finishing the talk opens an explicit offer without accepting")
	var progress_before := PlayerProgress.to_save_data().duplicate(true)
	visit.request_offer.decline_button.pressed.emit()
	check(not ResidentRequestFlow.accepted("neighbor_bread") and PlayerProgress.to_save_data() == progress_before, "visitor decline records no acceptance or reward")
	check(visit.stage == "checkout" and visit.guide.carried_amount == 1, "then he buys one real shelf item")
	# 계산
	player.global_position = world.get_node("BuildManager").get_cell_world_position(visit.guide_cell)
	var cashier = world.get_node("ManualCheckoutController")
	var money_before: int = GameState.get_money()
	check(cashier.try_interact(), "player checks him out at the register")
	cashier._process(2.0)
	check(GameState.get_money() > money_before, "actual payment is received")
	check(visit.stage.is_empty() and not visit.dialogue.open and visit.guide == null, "he leaves after paying without a repeated instruction dialogue")
	check(not world.has_meta("checkout_tutorial_dialogue"), "interaction state is restored")
	check(not QuestVisitDirector.pending_request().is_empty() and not QuestVisitDirector.replaces_standing_npc(world), "declined visit can be retried with the standing resident")
	residents.refresh()
	player.global_position = residents.npc.global_position
	check(residents.try_interact(), "declined resident remains available for a later conversation")
	drain(residents.dialogue)
	check(residents.request_offer.root.visible, "retry still requires an explicit response")
	residents.request_offer.accept_button.pressed.emit()
	check(ResidentRequestFlow.accepted("neighbor_bread") and QuestVisitDirector.pending_request().is_empty(), "later accept records the request without a repeated visit")
	# 수락된 부탁의 전달은 기존 방식(서 있는 NPC)으로 그대로 된다
	residents.refresh()
	check(ResidentRequestFlow.accepted("neighbor_bread") and ResidentRequestFlow.current().get("id", "") == "neighbor_bread", "delivery still goes through the existing request flow")
	var provider_names: Array[String] = []
	for node in visit._providers():
		var target: Dictionary = node.visit_target() if node.has_method("visit_target") else {"missing": true}
		check(node.has_method("visit_target") and node.has_method("begin_visit") and node.has_method("visit_busy") and not target.has("missing"), "provider API present: " + str(node.name))
		provider_names.append(str(node.name))
	check(provider_names.has("VillageLifeDirector") and provider_names.has("LanternWayfarerDirector") and provider_names.has("ActFourDirector") and provider_names.has("VillageExpansionDirector") and provider_names.count("RegularCustomerDirector") >= 1, "every story director is registered as a visit provider")
	await life_visit_test()
	print("CHECK_QUEST_VISIT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func unlock_village() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 90)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 90)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", 90)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	for request in ResidentRequestFlow.SETTINGS.requests: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(request["id"]) + ":done", 90)
	for request in ResidentStoryFlow.SETTINGS.settlement_requests: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(request["id"]) + ":done", 90)
	PlayerProgress.record_story_beat(VillageMarketFlow.PREFIX + "done", 91)
	PlayerProgress.record_story_beat(VillageRestFlow.PREFIX + "done", 93)
	for id in VillageGoodwillFlow.SETTINGS.after_requests:
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + id + ":done", 94)
		PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX + id + ":heard", 95)

# 마을 주민 이야기(호감 부탁 소개)를 주민이 손님으로 와서 건네는 흐름
func life_visit_test() -> void:
	var life: VillageLifeDirector = world.get_node("VillageLifeDirector")
	life.crafting_path_enabled = false
	manager.close_shop_manually()
	GameState.total_day = 100
	PlayerProgress.reset()
	unlock_village()
	await frames(3)
	var giver := str(VillageGoodwillFlow.SETTINGS.giver)
	var action := life.visit_action(giver)
	check(not action.is_empty() and str(action.get("flow", "")) == "goodwill", "the goodwill giver has a story to hand over")
	check(QuestVisitDirector.covers_life(giver) and QuestVisitDirector.pending_request().is_empty(), "village life visits are enabled and no resident request is pending")
	manager.open_shop()
	await frames(2)
	visit.try_start()
	check(is_instance_valid(visit.guide) and visit.kind == "provider" and str(visit.pick.get("id", "")) == giver, "the resident walks in as a customer")
	check(life.talking, "the village director holds the conversation with that resident")
	check(manager.hour_timer.paused and not player.is_physics_processing(), "the conversation pauses the clock")
	var before := VillageGoodwillFlow.accepted()
	for i in range(100):
		if not life.dialogue.open: break
		life.dialogue._advance()
	check(life.request_offer.root.visible and not VillageGoodwillFlow.accepted(), "provider introduction waits for a response")
	life.request_offer.accept_button.pressed.emit()
	await frames(2)
	check(not life.talking and life.visit_resident.is_empty(), "the conversation ends and the visit target is released")
	check(VillageGoodwillFlow.accepted() and not before, "the native story effect is applied (request accepted)")
	check(visit.stage == "checkout" and visit.guide.carried_amount == 1, "then he buys one real shelf item")
	player.global_position = world.get_node("BuildManager").get_cell_world_position(visit.guide_cell)
	var cashier = world.get_node("ManualCheckoutController")
	check(cashier.try_interact(), "player checks him out")
	cashier._process(2.0)
	check(visit.guide == null or visit.guide.purchase_completed, "payment completes and the visit ends")
	check(visit.stage.is_empty() and not world.has_meta("village_life_dialogue"), "state is restored after the visit")
	visit._process(0.0)
	var again := visit._provider_pick()
	check(str(again.get("id", "")) != giver, "the same resident does not come twice in one day")
