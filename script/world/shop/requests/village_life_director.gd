class_name VillageLifeDirector
extends Node

var residents: Dictionary = {}
var player
var manager
var dialogue: StoryDialoguePanel
var talking := false
var previous_paused := false
var previous_physics := true
var elapsed := 0.0
var story_panel: VillageStoryPanel
var story_action: Dictionary = {}

func _ready() -> void:
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
	story_panel = VillageStoryPanel.new()
	add_child(story_panel)
	story_panel.closed.connect(_end_talk)
	story_panel.action_requested.connect(_select_memory)
	call_deferred("refresh")

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0.0
	if not talking: refresh()

func refresh() -> void:
	var world := get_parent()
	var editor = world.get_node_or_null("VillageMapEditor")
	for entry in VillageLifeFlow.SETTINGS.residents:
		var id := str(entry["id"])
		var site := VillageSettlement.find_site(world, str(entry["site"]))
		var open: bool = VillageLifeFlow.available(entry) and site != null and site.visible and not (editor != null and editor.active)
		var npc = residents.get(id)
		if not open:
			if is_instance_valid(npc): npc.queue_free()
			residents.erase(id)
			continue
		var position := _approach_position(site)
		if position == Vector2.INF:
			if is_instance_valid(npc): npc.visible = false
			continue
		if not is_instance_valid(npc):
			npc = VillageResident.new()
			npc.resident_id = id
			npc.customer_type_id = str(entry["type"])
			npc.customer_group_id = str(entry["group"])
			world.get_node("Actors").add_child(npc)
			residents[id] = npc
			npc.global_position = position
		npc.visible = true
		var routine := VillageRoutine.location(entry,manager.current_hour)
		var destination_site := VillageSettlement.find_site(world,str(routine["path"]))
		if destination_site == null or not destination_site.visible: destination_site = site
		var target := _approach_position(destination_site)
		if target != Vector2.INF:
			# Offset neighbors sharing a landmark onto separate clear standing places.
			var offset := Vector2(32 * VillageLifeFlow.SETTINGS.residents.find(entry),0)
			var shape := CircleShape2D.new()
			shape.radius = VillageLifeFlow.SETTINGS.resident_radius
			if VillageRoutine.clear(world.get_world_2d().direct_space_state,shape,target + offset): target += offset
			npc.set_destination(target,str(routine["label"]))
		npc.refresh_title(entry)

# Keep a clear standing spot on an existing exterior tile, outside the building footprint.
func _approach_position(site: StaticBody2D) -> Vector2:
	var terrain = get_parent().get_node("StoreExterior")
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	for radius in [80.0, 112.0, 144.0, 176.0]:
		for direction in [Vector2.DOWN, Vector2(1,0.5).normalized(), Vector2(-1,0.5).normalized(), Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
			var candidate: Vector2 = site.global_position + direction * radius
			var grid := IsometricGrid.unproject(terrain.to_local(candidate), Vector2(terrain.tile_width, terrain.tile_height))
			var cell := Vector2i(roundi(grid.x), roundi(grid.y))
			if not terrain.is_exterior_cell(cell): continue
			query.transform = Transform2D(0, candidate)
			if player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return candidate
	return Vector2.INF

func _blocked() -> bool:
	var world := get_parent()
	var editor = world.get_node_or_null("VillageMapEditor")
	var story = world.get_node_or_null("StoryDirector")
	var merchant = world.get_node_or_null("SecretMerchantDirector")
	var cashier = world.get_node_or_null("ManualCheckoutController")
	return talking or world.get_node("WorldInteractions").blocked() or player.in_production_room or player.in_warehouse_room \
		or player.shelf_panel.visible or player.rumor_dialog.visible \
		or (is_instance_valid(player.facility_dialog) and player.facility_dialog.visible) \
		or (editor != null and editor.active) or (story != null and story.talking) or (merchant != null and merchant.shopping) \
		or (cashier != null and cashier.is_busy())

func nearest() -> Dictionary:
	if _blocked(): return {}
	var best: Dictionary = {}
	var distance: float = VillageLifeFlow.SETTINGS.interaction_distance
	for id in residents:
		var npc = residents[id]
		if not is_instance_valid(npc) or not npc.visible: continue
		var value: float = player.global_position.distance_to(npc.global_position)
		if value <= distance:
			distance = value
			best = {"id":id, "name":str(VillageLifeFlow.resident(id)["name"])}
	var well := VillageSettlement.find_site(get_parent(), "VillageDecor/VillageWell")
	if well != null and well.visible and ResidentRequestFlow.done("settle_sora") \
		and player.global_position.distance_to(well.global_position) <= distance:
		best = {"id":"well", "name":"공동 우물"}
	return best

func interaction_hint() -> String:
	var target := nearest()
	if target.is_empty(): return ""
	if target["id"] == "well": return "[E] 공동 우물 · 오늘 물을 길었어요" if VillageLifeFlow.well_used_today() else "[E] 공동 우물에서 물 긷기"
	var action := VillageStoryFlow.action(str(target["id"]))
	if not action.is_empty():
		var labels := {"introduction":"마을 이야기 시작", "listen":"마을 이야기 듣기", "choose":"남길 기억 고르기", "finish":"기록 마치기", "reminder":"남은 이야기 확인", "memory":"남긴 기억 다시 듣기"}
		return "[E] %s · %s" % [target["name"], labels[action["stage"]]]
	return "[E] %s · %s" % [target["name"], "다시 이야기하기" if VillageLifeFlow.greeted_today(target["id"]) else "오늘의 안부 나누기"]

func try_interact() -> bool:
	var target := nearest()
	if target.is_empty(): return false
	story_action = {}
	var lines: Array[String] = []
	if target["id"] == "well":
		var obtained := VillageLifeFlow.draw_water()
		lines.append("공동 우물에서 물을 길었습니다." if obtained else "오늘 사용할 물은 이미 길었습니다. 내일 다시 이용할 수 있어요.")
		if obtained: lines.append("받은 물건: %s ×%d" % [ItemData.get_item_name(VillageLifeFlow.SETTINGS.well_item), VillageLifeFlow.SETTINGS.well_amount])
	else:
		var entry := VillageLifeFlow.resident(target["id"])
		var result := VillageLifeFlow.greet(target["id"])
		if result.is_empty(): return false
		var period := 3
		if manager.current_hour >= 6 and manager.current_hour < 12: period = 0
		elif manager.current_hour >= 12 and manager.current_hour < 18: period = 1
		elif manager.current_hour >= 18: period = 2
		lines.append(str(entry["greetings"][period]))
		lines.append("%s · 함께 인사한 날 %d일" % [result["friendship"], VillageLifeFlow.friendship(target["id"])])
		if not str(result["gift"]).is_empty(): lines.append("이웃이 나눈 물건: " + str(result["gift"]))
		elif not result["first"]: lines.append("오늘은 이미 안부를 나눴어요. 내일 또 만나요.")
		if target["id"] == "naru" and result["first"] and VillageLifeFlow.friendship("naru") == 1:
			lines.append_array(RequestTextData.lines("service_text", "trade_first_greeting"))
		for request in PersonalRequestFlow.entries():
			if request["resident"] != target["id"] or PersonalRequestFlow.done(str(request["id"])) or not PersonalRequestFlow.locked_reason(request).is_empty(): continue
			lines.append_array(RequestTextData.lines("personal_request",str(request["id"])))
			lines.append("마을 게시판에서 개인 부탁을 맡거나 준비한 물품을 전달할 수 있어요.")
		story_action = VillageStoryFlow.action(str(target["id"]))
		if not story_action.is_empty():
			lines.append_array(RequestTextData.lines("service_text", str(story_action["id"]), str(story_action.get("field", "lines"))))
			if story_action["stage"] == "finish": lines.append("답례: " + VillageStoryFlow.reward_description())
	talking = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("village_life_dialogue", true)
	dialogue.start(target["name"], null, lines)
	return true

func _end_talk() -> void:
	if not talking: return
	if dialogue.line_index >= dialogue.lines.size():
		match str(story_action.get("stage", "")):
			"introduction": VillageStoryFlow.accept()
			"listen": VillageStoryFlow.listen(str(story_action["resident"]))
			"choose":
				if VillageStoryFlow.ready() and VillageStoryFlow.chosen().is_empty():
					story_action = {}
					story_panel.display()
					return
			"finish":
				if VillageStoryFlow.finish(): manager.customer_spawner.refresh_spawn_interval()
	story_action = {}
	talking = false
	get_parent().remove_meta("village_life_dialogue")
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	call_deferred("refresh")

func _select_memory(id: String) -> void:
	if not talking or not story_panel.root.visible or not VillageStoryFlow.select(id): return
	story_panel.root.hide()
	story_panel.backdrop.hide()
	story_action = {"stage":"finish", "id":"village_story_" + id}
	var lines := RequestTextData.lines("service_text", str(story_action["id"]))
	lines.append("답례: " + VillageStoryFlow.reward_description())
	dialogue.start(str(VillageLifeFlow.resident(VillageStoryFlow.SETTINGS.giver)["name"]), null, lines)

func _exit_tree() -> void:
	# Leaving a scene is not proof that its conversation was fully read.
	story_action = {}
	_end_talk()
