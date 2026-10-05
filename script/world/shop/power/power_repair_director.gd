class_name PowerRepairDirector
extends Node
var npc: VillageResident
var dialogue: StoryDialoguePanel
var panel: PowerRepairPanel
var world: Node2D
var player
var open := false
var phase := ""
var previous_pause := false
var elapsed := 0.0
func _ready() -> void:
	world = get_parent().get_parent()
	player = world.get_node("Actors/Player")
	dialogue = StoryDialoguePanel.new()
	dialogue.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dialogue)
	dialogue.finished.connect(_end_dialogue)
	panel = PowerRepairPanel.new()
	add_child(panel)
	panel.confirmed.connect(_release)
	panel.close_requested.connect(_release)
	panel.repair_requested.connect(_order)
	call_deferred("refresh")
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0.0
	if not open: refresh()
func refresh() -> void:
	if open: return
	var editor = world.get_node_or_null("VillageMapEditor")
	var site := VillageSettlement.find_site(world, PowerRepairFlow.SETTINGS.site_path)
	if not PowerRepairFlow.introduced() or site == null or not site.visible or (editor != null and editor.active):
		if is_instance_valid(npc): npc.queue_free()
		npc = null
		return
	if not is_instance_valid(npc):
		var location := _standing_place(site)
		if location == Vector2.INF: return
		npc = VillageResident.new()
		npc.resident_id = "power_technician"
		npc.customer_type_id = "gem_hunter"
		npc.customer_group_id = "normal"
		world.get_node("Actors").add_child(npc)
		npc.global_position = location
	npc.title.text = "%s [E]\n계산대 개조" % PowerRepairFlow.SETTINGS.npc_name
func _standing_place(site: Node2D) -> Vector2:
	var terrain = world.get_node("StoreExterior")
	var shape := CircleShape2D.new()
	shape.radius = VillageLifeFlow.SETTINGS.resident_radius
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		for distance in [160.0, 208.0]:
			var candidate: Vector2 = site.global_position + direction * distance
			var grid := IsometricGrid.unproject(terrain.to_local(candidate), Vector2(terrain.tile_width, terrain.tile_height))
			var cell := Vector2i(roundi(grid.x), roundi(grid.y))
			if terrain.is_exterior_cell(cell) and terrain.get_connected_map_cells().has(cell) and VillageRoutine.clear(world.get_world_2d().direct_space_state, shape, candidate): return candidate
	return Vector2.INF
func interaction_hint() -> String:
	if open or not is_instance_valid(npc) or world.get_node("WorldInteractions").blocked(): return ""
	if player.in_production_room or player.in_warehouse_room: return ""
	return "[E] %s · 계산대 개조" % PowerRepairFlow.SETTINGS.npc_name if player.global_position.distance_to(npc.global_position) <= PowerRepairFlow.SETTINGS.interaction_distance else ""
func try_interact() -> bool:
	if interaction_hint().is_empty(): return false
	open = true
	previous_pause = get_tree().paused
	get_tree().paused = true
	phase = PowerRepairFlow.phase()
	if phase == "supplies": panel.display()
	else:
		var moment := {"inspection":"power_inspection", "working":"power_work_waiting", "finish":"power_restored", "memory":"power_memory"}
		if not moment.has(phase):
			_release()
			return false
		var lines := RequestTextData.lines("service_text", moment[phase])
		lines.append(PowerRepairFlow.information())
		dialogue.start(PowerRepairFlow.SETTINGS.npc_name, null, lines)
	return true
func _order() -> void:
	if not open or not panel.visible or not PowerRepairFlow.order():
		if panel.visible: panel.info.text = PowerRepairFlow.information() + "\n" + PowerRepairFlow.blocked_reason()
		return
	panel.hide()
	phase = "ordered"
	dialogue.start(PowerRepairFlow.SETTINGS.npc_name, null, RequestTextData.lines("service_text", "power_work_started"))
func _end_dialogue() -> void:
	if not open: return
	if dialogue.line_index >= dialogue.lines.size():
		if phase == "inspection": PowerRepairFlow.inspect()
		elif phase == "finish": PowerRepairFlow.finish()
	_release()
func _release() -> void:
	if not open: return
	open = false
	phase = ""
	panel.hide()
	if dialogue.open: dialogue.close()
	get_tree().paused = previous_pause
	call_deferred("refresh")
func _exit_tree() -> void:
	_release()
	if is_instance_valid(npc): npc.queue_free()
