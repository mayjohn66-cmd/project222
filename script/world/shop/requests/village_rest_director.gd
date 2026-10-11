class_name VillageRestDirector
extends Node

var dialogue: StoryDialoguePanel
var talking := false
var stage := ""
var world: Node
var life: VillageLifeDirector
var player
var manager
var previous_paused := false
var previous_physics := true
var label_visibility: Dictionary = {}
var seating := VillageRestPose.new()

func _ready() -> void:
	life = get_parent()
	world = life.get_parent()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
func near_bench() -> bool:
	if talking or life._blocked(): return false
	if not VillageRestFlow.completed() and not VillageRestFlow.active(manager.current_hour): return false
	var target := VillageRestFlow.site(world)
	if target == null: return false
	var distance: float = player.global_position.distance_to(target.global_position)
	if VillageRestFlow.completed():
		if world.get_node("CommunityBoardDirector").near_board(): return false
		var neighbor := life.nearest()
		if not neighbor.is_empty():
			var npc = VillageSettlement.find_site(world, "VillageDecor/VillageWell") if neighbor["id"] == "well" else life.residents.get(neighbor["id"])
			if is_instance_valid(npc) and player.global_position.distance_to(npc.global_position) < distance: return false
	return distance <= VillageRestFlow.SETTINGS.interaction_distance
func interaction_hint() -> String:
	if not near_bench(): return ""
	if VillageRestFlow.completed(): return "[E] 길목 벤치에서 잠깐 쉬어 가기"
	return "[E] 쉼터에서 처음 함께 쉬기" if VillageRestFlow.all_present(world) else "이웃들이 길목 벤치로 오고 있어요."
func try_interact() -> bool:
	if not near_bench(): return false
	if not VillageRestFlow.completed() and not VillageRestFlow.all_present(world):
		world.get_node("WorldInteractions").show_message("이웃들이 벤치에 도착하면 함께 쉬어 갈 수 있어요.")
		return true
	stage = "rest" if VillageRestFlow.completed() else "opening"
	talking = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	world.set_meta("village_rest_open", true)
	var seated: Node2D = player
	if stage == "opening":
		var participant := VillageRestFlow.SETTINGS.participants[0]
		seated = life.residents.get(participant,player)
	seating.begin(world,seated,VillageRestFlow.site(world))
	world.get_node("ResidentRequestDirector").refresh()
	var lines: Array[String]
	if stage == "opening":
		for npc in life.residents.values():
			if not is_instance_valid(npc): continue
			label_visibility[npc.title] = npc.title.visible
			npc.title.hide()
		lines = VillageRestFlow.lines()
		lines.append("처음 함께 쉰 답례: 평판 +%d" % maxi(0, VillageRestFlow.SETTINGS.opening_reputation))
	else: lines = RequestTextData.lines("service_text", VillageRestFlow.SETTINGS.quiet_id)
	dialogue.start(VillageRestFlow.title() if stage == "opening" else "길목의 작은 쉼터", null, lines)
	return true
func _end_talk() -> void:
	if not talking: return
	if dialogue.line_index >= dialogue.lines.size():
		if stage == "opening" and VillageRestFlow.finish(manager.current_hour, world): manager.customer_spawner.refresh_spawn_interval()
		elif stage == "rest": VillageRestFlow.rest(world)
	stage = ""
	talking = false
	seating.restore()
	world.remove_meta("village_rest_open")
	for label in label_visibility:
		if is_instance_valid(label): label.visible = label_visibility[label]
	label_visibility.clear()
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	life.call_deferred("refresh")
	world.get_node("ResidentRequestDirector").call_deferred("refresh")
func _exit_tree() -> void:
	stage = ""
	_end_talk()
