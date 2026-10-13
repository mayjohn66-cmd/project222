class_name VillageMarketDirector
extends Node

var dialogue: StoryDialoguePanel
var panel: VillageMarketPanel
var talking := false
var stage := ""
var previous_paused := false
var previous_physics := true
var label_visibility: Dictionary = {}
var world: Node
var player
var manager
var life: VillageLifeDirector
var request_offer: RequestOfferPanel

func _ready() -> void:
	life = get_parent()
	world = life.get_parent()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
	request_offer = RequestOfferPanel.new()
	add_child(request_offer)
	request_offer.answered.connect(_answer_offer)
	panel = VillageMarketPanel.new()
	add_child(panel)
	panel.closed.connect(_end_talk)
	panel.action_requested.connect(_prepare)

func target_stage() -> String:
	if talking or life._blocked() or VillageMarketFlow.completed() or not VillageMarketFlow.locked_reason().is_empty(): return ""
	if VillageMarketFlow.active(manager.current_hour):
		var site := VillageMarketFlow.site(world)
		if site != null and player.global_position.distance_to(site.global_position) <= VillageMarketFlow.SETTINGS.interaction_distance: return "event"
	var npc = life.residents.get(VillageMarketFlow.SETTINGS.giver)
	if not is_instance_valid(npc) or not npc.visible or npc.is_queued_for_deletion() or player.global_position.distance_to(npc.global_position) > VillageLifeFlow.SETTINGS.interaction_distance: return ""
	return "intro" if not VillageMarketFlow.accepted() else ("prepare" if not VillageMarketFlow.prepared() else "wait")

func interaction_hint() -> String:
	match target_stage():
		"intro": return "[E] 타블렌 · 첫 장터 이야기"
		"prepare": return "[E] 타블렌 · 장터 준비 물품"
		"wait": return "[E] 타블렌 · 장터 날짜 확인"
		"event": return "[E] " + VillageMarketFlow.title() if VillageMarketFlow.all_present(world) else "이웃들이 노점으로 오고 있어요."
	return ""

func try_interact() -> bool:
	var next := target_stage()
	if next.is_empty(): return false
	if next == "event" and not VillageMarketFlow.all_present(world):
		world.get_node("WorldInteractions").show_message("이웃들이 노점에 도착하면 첫 장터를 함께 열 수 있어요.")
		return true
	stage = next
	talking = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	world.set_meta("village_market_open", true)
	world.get_node("ResidentRequestDirector").refresh()
	if stage == "prepare": panel.display()
	else:
		var lines: Array[String]
		if stage == "event":
			for npc in life.residents.values():
				if not is_instance_valid(npc): continue
				label_visibility[npc.title] = npc.title.visible
				npc.title.hide()
			lines = VillageMarketFlow.lines()
			lines.append("장터 답례: " + VillageMarketFlow.reward_description())
		else:
			lines = RequestTextData.lines("service_text", "first_market_intro" if stage == "intro" else "first_market_wait")
			if stage == "wait": lines.append(VillageMarketFlow.information())
		dialogue.start(VillageMarketFlow.title() if stage == "event" else str(VillageLifeFlow.resident(VillageMarketFlow.SETTINGS.giver)["name"]), null, lines)
	return true

func _prepare(id: String) -> void:
	if id != "prepare" or not talking or stage != "prepare" or not panel.root.visible: return
	if not VillageMarketFlow.prepare():
		panel.refresh()
		panel.message.text = "창고 물품이 부족합니다. 다시 준비해 주세요."
		return
	panel.close()
	world.get_node("WorldInteractions").show_message("준비 물품을 전달했습니다. " + VillageMarketFlow.information())

func _end_talk() -> void:
	if not talking: return
	if dialogue.line_index >= dialogue.lines.size():
		if stage == "intro":
			request_offer.display({"title": VillageMarketFlow.title(), "requirements": VillageMarketFlow.SETTINGS.requirements, "reward_text": VillageMarketFlow.reward_description()})
			return
		elif stage == "event" and VillageMarketFlow.finish(manager.current_hour, world): manager.customer_spawner.refresh_spawn_interval()
	stage = ""
	talking = false
	world.remove_meta("village_market_open")
	for label in label_visibility:
		if is_instance_valid(label): label.visible = label_visibility[label]
	label_visibility.clear()
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	life.call_deferred("refresh")
	world.get_node("ResidentRequestDirector").call_deferred("refresh")

func _answer_offer(accepted: bool) -> void:
	if accepted: VillageMarketFlow.accept()
	stage = ""
	_end_talk()

func _exit_tree() -> void:
	if is_instance_valid(request_offer): request_offer.dismiss()
	stage = ""
	_end_talk()
