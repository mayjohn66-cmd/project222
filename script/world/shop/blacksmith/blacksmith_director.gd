class_name BlacksmithDirector
extends Node
var player
var manager
var npc: VillageResident
var panel: BlacksmithServicePanel
var dialogue: StoryDialoguePanel
var open := false
var previous_paused := false
var previous_physics := true
var active_stage := ""
var return_to_service := false
var cancelled := false
var elapsed := 0.0
func _ready() -> void:
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	panel = BlacksmithServicePanel.new()
	add_child(panel)
	panel.action_requested.connect(_action)
	panel.closed.connect(_close)
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_finished)
	call_deferred("refresh")
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25 or open: return
	elapsed = 0.0
	refresh()
func refresh() -> void:
	if not BlacksmithProgressionFlow.npc_available():
		if is_instance_valid(npc): npc.queue_free()
		npc = null
		return
	var world := get_parent()
	var editor := world.get_node_or_null("VillageMapEditor")
	var life := world.get_node_or_null("VillageLifeDirector")
	var site := VillageSettlement.find_site(world,VillageSmithyFlow.SITE)
	if site == null: site = VillageSettlement.find_site(world,"VillageDecor/MarketStall")
	if site == null or life == null: return
	var point: Vector2 = life._approach_position(site)
	if point == Vector2.INF or (editor != null and editor.active):
		if is_instance_valid(npc): npc.hide()
		return
	if not is_instance_valid(npc):
		npc = VillageResident.new()
		npc.name = "VillageBlacksmithNpc"
		npc.resident_id = "village_blacksmith"
		npc.set_meta("look_key","story_npc") # 정식 그림 확정 전 기존 인물 모델.
		world.get_node("Actors").add_child(npc)
		npc.set_physics_process(false)
	npc.global_position = point
	npc.title.text = "대장장이 [E]"
	npc.show()
func _blocked() -> bool:
	var life := get_parent().get_node_or_null("VillageLifeDirector")
	return open or life == null or life._blocked()
func _naru_ready() -> bool:
	if not BlacksmithProgressionFlow.introduction_ready(): return false
	var life := get_parent().get_node("VillageLifeDirector")
	var nearest: Dictionary = life.nearest()
	return nearest.get("id","") == "naru" and VillageLifeFlow.greeted_today("naru") and life._next_story_action("naru").is_empty() and MarketAfterglowFlow.pending("naru").is_empty()
func near_npc() -> bool:
	return not _blocked() and is_instance_valid(npc) and npc.visible and player.global_position.distance_to(npc.global_position) <= VillageLifeFlow.SETTINGS.interaction_distance
func interaction_hint() -> String:
	if _blocked(): return ""
	if _naru_ready(): return "[E] 타블렌 · 대장장이의 소식"
	return "[E] 대장장이 · 안부와 장비 손질" if near_npc() else ""
func try_interact() -> bool:
	if _blocked(): return false
	if _naru_ready():
		_lock()
		_talk("smith_heard_naru")
		return true
	if not near_npc(): return false
	_lock()
	if BlacksmithProgressionFlow.service_available(): panel.display()
	else: _talk(BlacksmithProgressionFlow.stage())
	return true
func _lock() -> void:
	open = true
	cancelled = false
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("blacksmith_open",true)
func _talk(id: String, back: bool = false) -> void:
	active_stage = id
	return_to_service = back
	panel.hide_panel()
	var lines := BlacksmithProgressionFlow.lines(id)
	if id == "smith_first_meeting" and BlacksmithEquipmentAdapter.entries().is_empty():
		lines = ["쓰는 장비를 챙겨 오면 함께 살펴볼게. 타블렌에게 도구도 구할 수 있어."]
	dialogue.start("타블렌" if id == "smith_heard_naru" else "대장장이",null,lines)
func _finished() -> void:
	if not open: return
	var completed := not cancelled and dialogue.line_index >= dialogue.lines.size()
	if completed: BlacksmithProgressionFlow.complete(active_stage)
	var resume := completed and (return_to_service or active_stage == "smith_workshop_ready") and BlacksmithProgressionFlow.service_available()
	active_stage = ""
	if resume: panel.display()
	else: _close()
func _action(id: String) -> void:
	if not open or not panel.root.visible or not BlacksmithProgressionFlow.service_available(): return
	if id == "hello":
		_talk("smith_after_first_return" if BlacksmithProgressionFlow.afterglow_ready() else "smith_return_greeting",true)
	elif id == "enhance":
		var first := not BlacksmithProgressionRecords.has("first_enhanced")
		var result := BlacksmithEquipmentAdapter.enhance(panel.selected)
		panel.selected.clear()
		panel.refresh()
		panel.message.text = "%s +%d · 손질을 마쳤습니다." % [ItemData.get_item_name(str(result["item_id"])),int(result["new_level"])] if result.get("success",false) else str(result.get("message","강화할 수 없습니다."))
		if first and result.get("success",false): panel.message.text += "\n" + " ".join(BlacksmithProgressionFlow.lines("smith_first_enhancement"))
	elif id.begins_with("craft:"):
		var recipe_id := id.trim_prefix("craft:")
		var result := VillageSmithyFlow.craft(recipe_id)
		panel.refresh()
		panel.message.text = UiText.f("service.smith.done", [ItemData.get_item_name(str(result["item"])),int(result["amount"])]) if not result.is_empty() else VillageSmithyFlow.blocked_reason(recipe_id)
func _close() -> void:
	if not open: return
	open = false
	active_stage = ""
	get_parent().remove_meta("blacksmith_open")
	if is_instance_valid(panel): panel.hide_panel()
	if is_instance_valid(dialogue) and dialogue.open: dialogue.close()
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
func _input(event: InputEvent) -> void:
	if open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled = true
		_close()
	elif open and event is InputEventKey:
		for action in ["interact","ui_accept","ui_up","ui_down","ui_left","ui_right","ui_focus_next","ui_focus_prev"]:
			if event.is_action_pressed(action): return
		# 장비 창의 입력이 뒤쪽 건설·수첩·인벤토리로 새지 않도록 막는다.
		get_viewport().set_input_as_handled()
func _exit_tree() -> void:
	_close()
	if is_instance_valid(npc): npc.queue_free()
