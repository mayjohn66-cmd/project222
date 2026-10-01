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

func _ready() -> void:
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
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
		npc.visible = true
		npc.global_position = position
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
	return "[E] %s · %s" % [target["name"], "다시 이야기하기" if VillageLifeFlow.greeted_today(target["id"]) else "오늘의 안부 나누기"]

func try_interact() -> bool:
	var target := nearest()
	if target.is_empty(): return false
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
			lines.append("나루의 노점 옆에서 [E]로 재료를 교환할 수 있어요.")
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
	talking = false
	get_parent().remove_meta("village_life_dialogue")
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	call_deferred("refresh")

func _exit_tree() -> void:
	_end_talk()
