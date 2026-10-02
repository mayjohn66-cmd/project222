class_name VillageGatheringDirector
extends Node
var dialogue: StoryDialoguePanel
var talking := false
var previous_paused := false
var previous_physics := true
var label_visibility: Dictionary = {}
var player
var manager
func _ready() -> void:
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
func near_gathering() -> bool:
	if talking or not VillageGatheringFlow.active(manager.current_hour): return false
	if get_parent().get_node("VillageLifeDirector")._blocked(): return false
	var target := VillageGatheringFlow.site(get_parent())
	return target != null and player.global_position.distance_to(target.global_position) <= VillageGatheringFlow.SETTINGS.interaction_distance
func interaction_hint() -> String:
	if not near_gathering(): return ""
	return "[E] " + VillageGatheringFlow.title() if VillageGatheringFlow.all_present(get_parent()) else "이웃들이 우물 옆 벤치로 오고 있어요."
func try_interact() -> bool:
	if not near_gathering(): return false
	if not VillageGatheringFlow.all_present(get_parent()):
		get_parent().get_node("WorldInteractions").show_message("이웃들이 도착하면 함께 쉬어 갈 수 있어요.")
		return true
	talking = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("village_gathering_open",true)
	for npc in get_parent().get_node("VillageLifeDirector").residents.values():
		if not is_instance_valid(npc): continue
		label_visibility[npc.title] = npc.title.visible
		npc.title.hide()
	get_parent().get_node("ResidentRequestDirector").refresh()
	dialogue.start(VillageGatheringFlow.title(),null,VillageGatheringFlow.lines())
	return true
func _end_talk() -> void:
	if not talking: return
	if dialogue.line_index >= dialogue.lines.size(): VillageGatheringFlow.finish()
	talking = false
	get_parent().remove_meta("village_gathering_open")
	for label in label_visibility:
		if is_instance_valid(label): label.visible = label_visibility[label]
	label_visibility.clear()
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	get_parent().get_node("VillageLifeDirector").call_deferred("refresh")
	get_parent().get_node("ResidentRequestDirector").call_deferred("refresh")
func _exit_tree() -> void:
	if talking:
		dialogue.line_index = -1
		_end_talk()
