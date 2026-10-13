class_name LanternWayfarerDirector
extends Node

var npc: VillageResident
var dialogue: StoryDialoguePanel
var panel: LanternWayfarerPanel
var player
var manager
var open := false
var previous_paused := false
var previous_physics := true
var elapsed := 0.0
var dialogue_phase := ""
var encounter_hour := -1
var request_offer: RequestOfferPanel

func _ready() -> void:
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_dialogue)
	request_offer = RequestOfferPanel.new()
	add_child(request_offer)
	request_offer.answered.connect(_answer_offer)
	panel = LanternWayfarerPanel.new()
	add_child(panel)
	panel.closed.connect(_release)
	panel.action_requested.connect(_help)
	call_deferred("refresh")

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0.0
	if not open: refresh()

func refresh() -> void:
	if open: return
	var state := LanternWayfarerFlow.phase(manager.current_hour)
	var target := LanternWayfarerFlow.site(get_parent())
	var editor = get_parent().get_node_or_null("VillageMapEditor")
	var present: bool = state in ["introduction", "supplies", "return"] and target != null and not (editor != null and editor.active)
	if not present:
		CustomerGates.dismiss(npc)
		npc = null
		return
	var position: Vector2 = get_parent().get_node("VillageLifeDirector")._approach_position(target)
	if position == Vector2.INF:
		if is_instance_valid(npc): npc.hide()
		return
	if not is_instance_valid(npc):
		npc = VillageResident.new()
		npc.resident_id = "lantern_wayfarer"
		npc.customer_type_id = LanternWayfarerFlow.SETTINGS.customer_type
		npc.customer_group_id = LanternWayfarerFlow.SETTINGS.customer_group
		npc.name = "LanternWayfarer"
		get_parent().get_node("Actors").add_child(npc)
		CustomerGates.appear(npc)
	npc.global_position = position
	npc.show()
	npc.title.text = LanternWayfarerFlow.SETTINGS.npc_name + " [E]\n" + ("다시 찾아온 길손" if state == "return" else "등불 곁에서 쉬는 중")
	npc.title.show()

# ---- 방문 감독 API ----
var visit_force := false
func visit_target() -> Dictionary:
	if open or not is_instance_valid(npc) or not QuestVisitDirector.can_visit("lantern"): return {}
	if not LanternWayfarerFlow.phase(manager.current_hour) in ["introduction", "supplies", "return"]: return {}
	return {"id": "lantern_wayfarer", "key": "lantern", "name": LanternWayfarerFlow.SETTINGS.npc_name, "standing": npc}
func begin_visit(_id: String) -> bool:
	visit_force = true
	var ok := try_interact()
	visit_force = false
	return ok
func visit_busy() -> bool:
	return open
func near() -> bool:
	if visit_force:
		return not open and is_instance_valid(npc) and not npc.is_queued_for_deletion() \
			and LanternWayfarerFlow.phase(manager.current_hour) in ["introduction", "supplies", "return"]
	return not open and is_instance_valid(npc) and npc.visible and not npc.is_queued_for_deletion() \
		and not get_parent().get_node("VillageLifeDirector")._blocked() \
		and LanternWayfarerFlow.phase(manager.current_hour) in ["introduction", "supplies", "return"] \
		and player.global_position.distance_to(npc.global_position) <= LanternWayfarerFlow.SETTINGS.interaction_distance

func interaction_hint() -> String:
	return "[E] " + ("다시 찾아온 길손과 이야기하기" if LanternWayfarerFlow.return_ready() else LanternWayfarerFlow.title()) if near() else ""

func try_interact() -> bool:
	if not near(): return false
	open = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("lantern_wayfarer_open", true)
	npc.title.hide()
	get_parent().get_node("ResidentRequestDirector").refresh()
	var state := LanternWayfarerFlow.phase(manager.current_hour)
	if state == "supplies":
		panel.display()
	else:
		encounter_hour = manager.current_hour
		var id := "lantern_wayfarer"
		if state == "return": id += "_return_" + LanternWayfarerFlow.chosen()
		var lines := RequestTextData.lines("service_text", id)
		if state == "return": lines.append("답례: " + LanternWayfarerFlow.reward_description())
		_start_dialogue(state, lines)
	return true

func _start_dialogue(state: String, lines: Array[String]) -> void:
	dialogue_phase = state
	dialogue.start(LanternWayfarerFlow.SETTINGS.npc_name, null, lines)

func _help(id: String) -> void:
	if not open or not panel.root.visible: return
	if not LanternWayfarerFlow.help(id):
		panel.message.text = "창고 물품을 확인해 주세요. 이미 건넨 물품은 다시 사용하지 않아요."
		panel.refresh()
		return
	panel.root.hide()
	panel.backdrop.hide()
	_start_dialogue("help", RequestTextData.lines("service_text", "lantern_wayfarer_" + id))

func _end_dialogue() -> void:
	if not open: return
	var fully_read := dialogue.line_index >= dialogue.lines.size()
	if fully_read and dialogue_phase == "introduction":
		request_offer.display({"title": LanternWayfarerFlow.title()})
		return
	if fully_read and dialogue_phase == "return" and LanternWayfarerFlow.finish():
		manager.customer_spawner.refresh_spawn_interval()
	_release()

func _answer_offer(accepted: bool) -> void:
	if accepted and LanternWayfarerFlow.accept(encounter_hour):
		dialogue_phase = ""
		panel.display()
	else: _release()

func _release() -> void:
	if is_instance_valid(request_offer): request_offer.dismiss()
	if not open: return
	open = false
	dialogue_phase = ""
	get_parent().remove_meta("lantern_wayfarer_open")
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	if is_instance_valid(npc): npc.title.show()
	call_deferred("refresh")
	get_parent().get_node("ResidentRequestDirector").call_deferred("refresh")

func _exit_tree() -> void:
	_release()
	if is_instance_valid(npc): npc.queue_free()
