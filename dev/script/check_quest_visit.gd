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

func _ready() -> void: call_deferred("run")

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
	check(QuestVisitDirector.ids().has("neighbor_bread") and str(request.get("id", "")) == "neighbor_bread", "first resident request is the pilot")
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
	check(ResidentRequestFlow.accepted("neighbor_bread"), "finishing the talk accepts the request")
	check(visit.stage == "checkout" and visit.guide.carried_amount == 1, "then he buys one real shelf item")
	# 계산
	player.global_position = world.get_node("BuildManager").get_cell_world_position(visit.guide_cell)
	var cashier = world.get_node("ManualCheckoutController")
	var money_before: int = GameState.get_money()
	check(cashier.try_interact(), "player checks him out at the register")
	cashier._process(2.0)
	check(visit.guide.purchase_completed and GameState.get_money() > money_before, "actual payment is received")
	check(visit.stage == "finished" and visit.dialogue.open, "he tells what to bring after paying")
	var hint := "\n".join(visit.dialogue.lines)
	check(hint.contains(ItemData.get_item_name(str(request["item"]))), "the hint names the requested goods")
	drain(visit.dialogue)
	check(visit.stage.is_empty() and not is_instance_valid(visit.guide) or visit.guide.force_exit_requested, "he leaves and the visit ends")
	check(QuestVisitDirector.pending_request().is_empty(), "an accepted request is not offered again")
	check(not world.has_meta("checkout_tutorial_dialogue"), "interaction state is restored")
	# 수락된 부탁의 전달은 기존 방식(서 있는 NPC)으로 그대로 된다
	residents.refresh()
	check(ResidentRequestFlow.accepted("neighbor_bread") and ResidentRequestFlow.current().get("id", "") == "neighbor_bread", "delivery still goes through the existing request flow")
	print("CHECK_QUEST_VISIT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
