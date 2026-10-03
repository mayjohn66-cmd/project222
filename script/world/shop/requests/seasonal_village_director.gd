class_name SeasonalVillageDirector
extends Node
var world: Node
var life: VillageLifeDirector
var player
var manager
var dialogue: StoryDialoguePanel
var talking := false
var event_id := ""
var previous_paused := false
var previous_physics := true
func _ready() -> void:
	life = get_parent()
	world = life.get_parent()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
func nearest() -> String:
	if talking or life._blocked() or world.get_node("CommunityBoardDirector").near_board(): return ""
	for entry in SeasonalVillageFlow.SETTINGS.events:
		var id := str(entry["id"])
		if not SeasonalVillageFlow.can_observe(id, world, manager.current_hour): continue
		var target := SeasonalVillageFlow.site(world, id)
		var distance: float = player.global_position.distance_to(target.global_position)
		if distance > SeasonalVillageFlow.SETTINGS.interaction_distance: continue
		var neighbor := life.nearest()
		if not neighbor.is_empty():
			var npc = VillageSettlement.find_site(world, "VillageDecor/VillageWell") if neighbor["id"] == "well" else life.residents.get(neighbor["id"])
			if is_instance_valid(npc) and player.global_position.distance_to(npc.global_position) < distance: continue
		return id
	return ""
func interaction_hint() -> String:
	var id := nearest()
	return "[E] " + str(SeasonalVillageFlow.event(id)["site_name"]) + " · 계절 풍경 살펴보기" if not id.is_empty() else ""
func try_interact() -> bool:
	event_id = nearest()
	if event_id.is_empty(): return false
	talking = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	world.set_meta("seasonal_village_open", true)
	dialogue.start(SeasonalVillageFlow.title(event_id), null, RequestTextData.lines("service_text", event_id + "_observe"))
	return true
func _end_talk() -> void:
	if not talking: return
	if not event_id.is_empty() and dialogue.line_index >= dialogue.lines.size(): SeasonalVillageFlow.observe(event_id, world, manager.current_hour)
	event_id = ""
	talking = false
	world.remove_meta("seasonal_village_open")
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
func _exit_tree() -> void:
	event_id = ""
	_end_talk()
