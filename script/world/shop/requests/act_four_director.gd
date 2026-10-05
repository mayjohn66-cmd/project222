class_name ActFourDirector
extends Node

var life: VillageLifeDirector
var world: Node2D
var player
var manager
var dialogue: StoryDialoguePanel
var visitors: Dictionary = {}
var action: Dictionary = {}
var talking := false
var can_finish := false
var previous_paused := false
var previous_physics := true
var elapsed := 0.0
const ROLES := {"caravan":{"name":"먼 곳의 상단","type":"peddler"},"traveler":{"name":"쉬어 가는 길손","type":"backpacker"},"technician":{"name":"순회 기술자","type":"gem_hunter"}}

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
	if elapsed < 0.5: return
	elapsed = 0.0
	if not talking: refresh()
func refresh() -> void:
	var needed: Array[String] = []
	if ActFourFlow.started():
		for entry in ActFourFlow.SETTINGS.events:
			var current := ActFourFlow.step(str(entry["id"]))
			var role := str(current.get("resident",""))
			if ROLES.has(role) and not needed.has(role): needed.append(role)
		if ActFourFlow.done("a3_traveler_rest") and LanternWayfarerFlow.evening(manager.current_hour) and not needed.has("traveler"): needed.append("traveler")
	var board := VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path)
	for role in ROLES:
		var npc = visitors.get(role)
		if not needed.has(role) or board == null or not board.visible:
			if is_instance_valid(npc): npc.queue_free()
			visitors.erase(role)
			continue
		if not is_instance_valid(npc):
			var placement: VillageExpansionDirector = life.get_node("VillageExpansionDirector")
			var site := board
			if role == "traveler" and ActFourFlow.done("a3_traveler_rest"):
				var rest := VillageRestFlow.site(world)
				if rest != null: site = rest
			var point := placement.visitor_position(site,visitors.values())
			if point == Vector2.INF: continue
			# 기존 정착 방문자와 새 방문자 모두 같은 간격 규칙을 쓴다.
			var occupied := false
			for other in visitors.values():
				if is_instance_valid(other) and other.global_position.distance_to(point) < VillageExpansionFlow.SETTINGS.visitor_spacing: occupied = true
			if occupied: continue
			npc = VillageResident.new()
			npc.resident_id = role
			npc.customer_type_id = ROLES[role]["type"]
			npc.customer_group_id = CustomerTypeData.get_group_id(npc.customer_type_id)
			world.get_node("Actors").add_child(npc)
			npc.global_position = point
			npc.set_physics_process(false)
			visitors[role] = npc
		npc.title.text = str(ROLES[role]["name"]) + " [E]"
func npc_for(role: String):
	if role == "merchant":
		var merchant = world.get_node_or_null("SecretMerchantDirector")
		return merchant.active_npc if merchant != null and is_instance_valid(merchant.active_npc) else null
	return life.residents.get(role,visitors.get(role))
func nearest() -> Dictionary:
	if talking or not ActFourFlow.started() or world.get_node("WorldInteractions").blocked(): return {}
	if player.in_production_room or player.in_warehouse_room or player.shelf_panel.visible or player.rumor_dialog.visible: return {}
	if is_instance_valid(player.facility_dialog) and player.facility_dialog.visible: return {}
	var cashier = world.get_node_or_null("ManualCheckoutController")
	var merchant = world.get_node_or_null("SecretMerchantDirector")
	var editor = world.get_node_or_null("VillageMapEditor")
	if cashier != null and cashier.is_busy(): return {}
	if merchant != null and merchant.shopping: return {}
	if editor != null and editor.active: return {}
	var fallback: Dictionary = {}
	for entry in ActFourFlow.SETTINGS.events:
		var current := ActFourFlow.step(str(entry["id"]))
		if current.is_empty(): continue
		var role := str(current["resident"])
		var npc = npc_for(role)
		if not is_instance_valid(npc) or not npc.visible or npc.is_queued_for_deletion() or player.global_position.distance_to(npc.global_position) > VillageLifeFlow.SETTINGS.interaction_distance: continue
		if life.residents.has(role) and not VillageLifeFlow.greeted_today(role): continue
		current["reason"] = ActFourFlow.step_reason(str(entry["id"]))
		# 구매 대기 중에는 준비 안내로 E를 가로채지 않고 기존 상인의 판매 창을 연다.
		if role == "merchant" and current.get("map_purchase",false) and not str(current["reason"]).is_empty(): continue
		if str(current["reason"]).is_empty(): return current
		if fallback.is_empty(): fallback = current
	if not fallback.is_empty(): return fallback
	var traveler = visitors.get("traveler")
	if is_instance_valid(traveler) and ActFourFlow.done("a3_traveler_rest") and player.global_position.distance_to(traveler.global_position) <= VillageLifeFlow.SETTINGS.interaction_distance:
		return {"id":"act4_rest_greeting","resident":"traveler","role":"쉬어 가는 길손","preview":true,"reason":""}
	return {}
func interaction_hint() -> String:
	var current := nearest()
	return "" if current.is_empty() else "[E] " + str(current.get("role","길 위의 이야기")) + " · 이야기 듣기"
func try_interact() -> bool:
	var current := nearest()
	if current.is_empty(): return false
	action = current.duplicate(true)
	action.erase("reason")
	can_finish = str(current["reason"]).is_empty() and not current.get("preview",false)
	var lines: Array[String] = []
	if can_finish or current.get("preview",false): lines.assign(RequestTextData.lines("service_text",str(current["id"])))
	else: lines.append(str(current["reason"]))
	if current.has("event"): lines.append_array(ActFourFlow.information(str(current["event"])).split("\n",false))
	if current.get("event","") == "b5_question_stays": lines.append_array(ActFourFlow.clues())
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	talking = true
	world.set_meta("act_four_open",true)
	dialogue.start(str(current.get("role","이웃")),null,lines)
	return true
func _end_talk() -> void:
	if not talking: return
	if can_finish and dialogue.line_index >= dialogue.lines.size():
		if ActFourFlow.complete(action): manager.customer_spawner.refresh_spawn_interval()
	can_finish = false
	action = {}
	talking = false
	world.remove_meta("act_four_open")
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
	call_deferred("refresh")
func _exit_tree() -> void:
	can_finish = false
	_end_talk()
