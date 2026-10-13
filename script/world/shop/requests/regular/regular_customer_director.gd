class_name RegularCustomerDirector
extends Node
var world: Node
var player: Node2D
var manager: Node
var npc: VillageResident
var dialogue: StoryDialoguePanel
var current_id := ""
var action_stage := ""
var open := false
var previous_paused := false
var previous_physics := true
var elapsed := 0.0
var story_flow = RegularCustomerFlow
var purchase_group := "regular_customer"
var identity_meta := "regular_story_id"
var open_meta := "regular_customer_open"
var visitor_prefix := "단골 · "
var interaction_prefix := "[E] 단골의 이야기 · "

func _ready() -> void:
	world = get_parent().get_parent()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_dialogue)
	call_deferred("refresh")
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0.0
	if not open: refresh()
func _hide_visitor() -> void:
	CustomerGates.dismiss(npc)
	npc = null
	current_id = ""
func _live_purchase(id: String) -> bool:
	for customer in get_tree().get_nodes_in_group(purchase_group):
		if not customer.is_queued_for_deletion() and str(customer.get_meta(identity_meta,"")) == id: return true
	return false
func refresh() -> void:
	if open: return
	var editor = world.get_node_or_null("VillageMapEditor")
	var site := VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path)
	if not CommunityRequestFlow.board_available() or site == null or not site.visible or (editor != null and editor.active):
		_hide_visitor()
		return
	var selected: Dictionary = {}
	# A ready delivery or unread afterglow stays ahead of new introductions.
	for stages in [["finish","after"],["intro","request"],["wait"]]:
		for entry in story_flow.SETTINGS.events:
			if story_flow.phase(str(entry["id"])) in stages and not _live_purchase(str(entry["id"])):
				selected = entry
				break
		if not selected.is_empty(): break
	if selected.is_empty():
		_hide_visitor()
		return
	var id := str(selected["id"])
	var point: Vector2 = npc.global_position if is_instance_valid(npc) and current_id == id else _position(site)
	if point == Vector2.INF:
		_hide_visitor()
		return
	if not is_instance_valid(npc) or current_id != id:
		_hide_visitor()
		npc = VillageResident.new()
		npc.resident_id = id
		npc.customer_type_id = str(selected["type"])
		npc.customer_group_id = CustomerTypeData.get_group_id(npc.customer_type_id)
		npc.name = "RegularCustomerVisitor"
		world.get_node("Actors").add_child(npc)
		CustomerGates.appear(npc)
		current_id = id
	npc.global_position = point
	npc.title.text = visitor_prefix + CustomerTypeData.get_display_name(npc.customer_type_id) + " [E]"
	npc.show()
func _position(site: Node2D) -> Vector2:
	var terrain = world.get_node("StoreExterior")
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = VillageLifeFlow.SETTINGS.resident_radius
	query.shape = shape
	query.collision_mask = 1
	for radius in story_flow.SETTINGS.placement_radii:
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP,Vector2(1,0.5).normalized(),Vector2(-1,0.5).normalized()]:
			var point: Vector2 = site.global_position + direction * radius
			var grid := IsometricGrid.unproject(terrain.to_local(point),Vector2(terrain.tile_width,terrain.tile_height))
			if not terrain.is_exterior_cell(Vector2i(roundi(grid.x),roundi(grid.y))): continue
			if player.global_position.distance_to(point) < story_flow.SETTINGS.separation: continue
			var crowded := false
			for actor in world.get_node("Actors").get_children():
				if actor == npc or not actor is Node2D or not actor.visible or actor.is_queued_for_deletion(): continue
				if actor.global_position.distance_to(point) < story_flow.SETTINGS.separation: crowded = true
			if crowded: continue
			query.transform = Transform2D(0,point)
			if player.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return point
	return Vector2.INF
# ---- 방문 감독 API ----
var visit_force := false
func _pick_entry() -> Dictionary:
	for stages in [["finish","after"],["intro","request"],["wait"]]:
		for entry in story_flow.SETTINGS.events:
			if story_flow.phase(str(entry["id"])) in stages and not _live_purchase(str(entry["id"])): return entry
	return {}
func visit_target() -> Dictionary:
	if open: return {}
	var entry := _pick_entry()
	if entry.is_empty() or story_flow.phase(str(entry["id"])) == "wait": return {}   # 준비 중 재촉은 방문 사유가 아니다
	if not QuestVisitDirector.can_visit("regular:" + str(entry["id"])): return {}
	return {"id": str(entry["id"]), "key": "regular:" + str(entry["id"]), "name": CustomerTypeData.get_display_name(str(entry["type"])), "standing": npc if is_instance_valid(npc) and current_id == str(entry["id"]) else null}
func begin_visit(id: String) -> bool:
	if open: return false
	var chosen: Dictionary = {}
	for entry in story_flow.SETTINGS.events:
		if str(entry["id"]) == id: chosen = entry
	if chosen.is_empty(): return false
	if not is_instance_valid(npc) or current_id != id:
		_hide_visitor()
		npc = VillageResident.new()
		npc.resident_id = id
		npc.customer_type_id = str(chosen["type"])
		npc.customer_group_id = CustomerTypeData.get_group_id(npc.customer_type_id)
		npc.name = "RegularCustomerVisitor"
		world.get_node("Actors").add_child(npc)
		npc.hide()
		current_id = id
	visit_force = true
	var ok := try_interact()
	visit_force = false
	return ok
func visit_busy() -> bool:
	return open
func near() -> bool:
	if visit_force: return not open and is_instance_valid(npc) and not npc.is_queued_for_deletion()
	return not open and is_instance_valid(npc) and npc.visible and not npc.is_queued_for_deletion() \
		and not get_parent()._blocked() and player.global_position.distance_to(npc.global_position) <= story_flow.SETTINGS.interaction_distance
func interaction_hint() -> String:
	return interaction_prefix + story_flow.title(current_id) if near() else ""
func try_interact() -> bool:
	if not near(): return false
	action_stage = story_flow.phase(current_id)
	if not action_stage in ["intro","request","wait","finish","after"]: return false
	var lines := RequestTextData.lines("service_text",current_id + "_" + action_stage)
	if lines.is_empty(): return false
	if action_stage in ["request","wait","finish"]: lines.append(story_flow.requirements(current_id))
	if action_stage == "finish": lines.append("답례: " + story_flow.reward(current_id))
	open = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	world.set_meta(open_meta,true)
	npc.title.hide()
	dialogue.start(CustomerTypeData.get_display_name(npc.customer_type_id),null,lines)
	return true
func _end_dialogue() -> void:
	if not open: return
	if dialogue.line_index >= dialogue.lines.size():
		if story_flow.complete_action(current_id,action_stage) and action_stage == "finish": manager.customer_spawner.refresh_spawn_interval()
	_release()
func _release() -> void:
	if not open: return
	open = false
	if is_instance_valid(world): world.remove_meta(open_meta)
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	if is_instance_valid(npc): npc.title.show()
func _exit_tree() -> void:
	_release()
	if is_instance_valid(npc): npc.queue_free()
