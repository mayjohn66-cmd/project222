class_name VillageExpansionDirector
extends Node

var life: VillageLifeDirector
var world: Node2D
var player
var manager
var visitors: Dictionary = {}
var dialogue: StoryDialoguePanel
var talking := false
var action: Dictionary = {}
var can_finish := false
var previous_paused := false
var previous_physics := true
var elapsed := 0.0

func _ready() -> void:
	life = get_parent()
	world = life.get_parent()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
	call_deferred("refresh")
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0.0
	if not talking: refresh()
func refresh() -> void:
	for facility in get_tree().get_nodes_in_group("production_facility"):
		if not facility.output_collected.is_connected(VillageExpansionFlow.record_output): facility.output_collected.connect(VillageExpansionFlow.record_output)
	var board := VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path)
	for entry in VillageExpansionFlow.SETTINGS.residents:
		var id := str(entry["id"])
		var pending := not VillageExpansionFlow.done(str(entry["expansion_event"])) and VillageExpansionFlow.locked_reason(str(entry["expansion_event"])).is_empty()
		var npc = visitors.get(id)
		if not pending or board == null or not board.visible:
			if is_instance_valid(npc): npc.queue_free()
			visitors.erase(id)
			continue
		if not is_instance_valid(npc):
			var point := visitor_position(board)
			if point == Vector2.INF: continue
			npc = VillageResident.new()
			npc.resident_id = id
			npc.customer_type_id = str(entry["type"])
			npc.customer_group_id = str(entry["group"])
			world.get_node("Actors").add_child(npc)
			npc.global_position = point
			visitors[id] = npc
			npc.set_physics_process(false)
		npc.title.text = str(entry["name"]) + " [E]\n" + ("정착 이야기 이어가기" if VillageExpansionFlow.accepted(str(entry["expansion_event"])) else "정착 제안 듣기")
func visitor_position(board: StaticBody2D, extra_visitors: Array = []) -> Vector2:
	var terrain = world.get_node("StoreExterior")
	var shape := CircleShape2D.new()
	shape.radius = VillageLifeFlow.SETTINGS.resident_radius
	for radius in [112.0,144.0,176.0]:
		for direction in [Vector2.DOWN,Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2(1,0.5).normalized(),Vector2(-1,0.5).normalized()]:
			var point: Vector2 = board.global_position + direction * radius
			var grid := IsometricGrid.unproject(terrain.to_local(point),Vector2(terrain.tile_width,terrain.tile_height))
			if not terrain.is_exterior_cell(Vector2i(roundi(grid.x),roundi(grid.y))): continue
			if player.global_position.distance_to(point) < VillageExpansionFlow.SETTINGS.visitor_spacing: continue
			if not VillageRoutine.clear(world.get_world_2d().direct_space_state,shape,point): continue
			var occupied := false
			for npc in visitors.values() + life.residents.values() + extra_visitors + get_tree().get_nodes_in_group("story_npc"):
				if is_instance_valid(npc) and not npc.is_queued_for_deletion() and npc.global_position.distance_to(point) < VillageExpansionFlow.SETTINGS.visitor_spacing: occupied = true
			if not occupied: return point
	return Vector2.INF
func npc_for(id: String):
	return life.residents.get(id,visitors.get(id))
func all_present(current: Dictionary) -> bool:
	var site := VillageSettlement.find_site(world,str(current["site"]))
	if site == null or not site.visible: return false
	for id in current["participants"]:
		var npc = npc_for(str(id))
		if not is_instance_valid(npc) or not npc.visible or npc.is_queued_for_deletion() or npc.global_position.distance_to(site.global_position) > VillageExpansionFlow.SETTINGS.arrival_distance: return false
	return true
# ---- 방문 감독 API (모임 단계는 여럿이 한 장소에 모이는 이야기라 대상이 아니다) ----
var visit_id := ""
func visit_target() -> Dictionary:
	if talking: return {}
	for entry in VillageExpansionFlow.SETTINGS.events:
		var id := str(entry["id"])
		var current := VillageExpansionFlow.step(id)
		if current.is_empty() or current.get("mode", "") == "gather": continue
		if not VillageExpansionFlow.step_reason(id, manager.current_hour).is_empty(): continue
		var resident := str(current["resident"])
		if not QuestVisitDirector.can_visit("expansion:" + resident): continue
		return {"id": resident, "key": "expansion:" + resident, "name": str(VillageLifeFlow.resident(resident).get("name", resident)), "standing": npc_for(resident)}
	return {}
func begin_visit(resident: String) -> bool:
	visit_id = resident
	var ok := try_interact()
	visit_id = ""
	return ok
func visit_busy() -> bool:
	return talking
func nearest() -> Dictionary:
	if talking or life._blocked(): return {}
	var fallback: Dictionary = {}
	for entry in VillageExpansionFlow.SETTINGS.events:
		var id := str(entry["id"])
		var current := VillageExpansionFlow.step(id)
		if current.is_empty(): continue
		var reason := VillageExpansionFlow.step_reason(id,manager.current_hour)
		if current.get("mode", "") == "gather" and reason.is_empty():
			var site := VillageSettlement.find_site(world,str(current["site"]))
			if site == null or not site.visible or player.global_position.distance_to(site.global_position) > VillageExpansionFlow.SETTINGS.gather_distance: continue
			if not all_present(current): reason = "이웃들이 모임 자리로 오고 있어요."
		else:
			var npc = npc_for(str(current["resident"]))
			var forced: bool = not visit_id.is_empty() and str(current["resident"]) == visit_id
			if not visit_id.is_empty() and not forced: continue
			if not forced and (not is_instance_valid(npc) or not npc.visible or npc.is_queued_for_deletion() or player.global_position.distance_to(npc.global_position) > VillageLifeFlow.SETTINGS.interaction_distance): continue
			if not forced and VillageLifeFlow.available(VillageLifeFlow.resident(str(current["resident"]))) and not VillageLifeFlow.greeted_today(str(current["resident"])): continue
		current["reason"] = reason
		if reason.is_empty(): return current
		if fallback.is_empty(): fallback = current
	if not fallback.is_empty(): return fallback
	for entry in VillageExpansionFlow.SETTINGS.residents:
		var id := str(entry["expansion_event"])
		var npc = visitors.get(str(entry["id"]))
		if VillageExpansionFlow.accepted(id) or not is_instance_valid(npc) or npc.is_queued_for_deletion(): continue
		if player.global_position.distance_to(npc.global_position) > VillageLifeFlow.SETTINGS.interaction_distance: continue
		return {"event":id,"resident":entry["id"],"id":VillageExpansionFlow.event(id)["steps"][0]["id"],"preview":true,"reason":"마을 게시판에서 이 정착 이야기를 맡으면 준비를 이어갈 수 있어요."}
	return {}
func interaction_hint() -> String:
	var current := nearest()
	return "" if current.is_empty() else "[E] " + VillageExpansionFlow.title(str(current["event"])) + (" · 준비 안내" if not str(current["reason"]).is_empty() else "")
func try_interact() -> bool:
	var current := nearest()
	if current.is_empty(): return false
	action = current.duplicate(true)
	action.erase("reason")
	can_finish = str(current["reason"]).is_empty()
	var lines: Array[String] = []
	if can_finish or bool(current.get("preview",false)): lines.assign(RequestTextData.lines("service_text",str(action["id"])))
	else: lines.append(str(current["reason"]))
	if bool(current.get("preview",false)): lines.append(str(current["reason"]))
	lines.append_array(VillageExpansionFlow.information(str(action["event"])).split("\n",false))
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	talking = true
	world.set_meta("village_expansion_open",true)
	var name_text := VillageExpansionFlow.title(str(action["event"])) if action.get("mode", "") == "gather" else str(VillageLifeFlow.resident(str(action["resident"])).get("name",action["resident"]))
	dialogue.start(name_text,null,lines)
	return true
func _end_talk() -> void:
	if not talking: return
	if can_finish and dialogue.line_index >= dialogue.lines.size():
		if action.get("mode", "") != "gather" or all_present(action):
			if VillageExpansionFlow.complete(action,manager.current_hour):
				VillageSettlement.apply_world(world)
				manager.customer_spawner.refresh_spawn_interval()
	action = {}
	can_finish = false
	talking = false
	world.remove_meta("village_expansion_open")
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	life.call_deferred("refresh")
	call_deferred("refresh")
func _exit_tree() -> void:
	can_finish = false
	_end_talk()
