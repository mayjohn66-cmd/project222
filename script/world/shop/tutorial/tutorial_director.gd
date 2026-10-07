class_name TutorialDirector
extends Node
const SETTINGS = preload("res://scenes/shop/tutorial/default_tutorial.tres")
@export var enabled: bool = true
@export var talk_distance: float = 48.0
var flow := TutorialFlow.new()
var npc: StoryNpc
var dialogue: StoryDialoguePanel
var panel: TutorialGoalPanel
var player
var manager
var talking: bool = false
var timer_was_paused: bool = false
var physics_was_enabled: bool = true
var elapsed: float = 0.0
var pending: Dictionary = {}
var barter_panel: ArrivalBarterPanel
var cutscene: OpeningCutscene  # 새 게임 프롤로그 연출(새 그림 없이 카메라·빛·소리)
var _cleanup_layer: CanvasLayer
var _cleanup_hint: Label       # 가장 가까운 잔해 더미 위 "[E] 잔해 치우기"
var _cleanup_note: Label       # 치운 뒤 얻은 자재 알림
var _cleanup_prepared: bool = false
var layout_editor: OpeningLayoutEditor

func _ready() -> void:
	add_child(FoodShelfLifeDirector.new())
	flow.settings = SETTINGS
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
	barter_panel = ArrivalBarterPanel.new()
	add_child(barter_panel)
	barter_panel.action_requested.connect(_on_trade)
	barter_panel.closed.connect(_end_talk)
	panel = TutorialGoalPanel.new()
	add_child(panel)
	cutscene = OpeningCutscene.new()
	add_child(cutscene)
	cutscene.setup(get_parent())
	if _is_primary():
		# 개발자 모드(F10): 프롤로그 가게 안 집기 배치 편집기
		layout_editor = OpeningLayoutEditor.new()
		add_child(layout_editor)
		layout_editor.setup(get_parent(), cutscene)
		layout_editor.closed.connect(func() -> void: _cleanup_prepared = false)
	add_to_group("tutorial_director")
	call_deferred("refresh")

func is_guiding() -> bool:
	return enabled and not OpeningJourneyFlow.core_finished()

func permits_first_checkout() -> bool:
	var step := flow.current()
	return not enabled or (not OpeningPrologueFlow.pending() and (str(step.get("id", "")) == "checkout" or flow.done("checkout")))

func _blocked() -> bool:
	var world = get_parent()
	var interactions = world.get_node_or_null("WorldInteractions")
	var cashier = world.get_node_or_null("ManualCheckoutController")
	var checkout = world.get_node_or_null("CheckoutTutorial")
	var story = world.get_node_or_null("StoryDirector")
	var merchant = world.get_node_or_null("SecretMerchantDirector")
	return get_tree().paused or player.in_production_room or player.in_warehouse_room \
		or player.shelf_panel.visible or player.rumor_dialog.visible \
		or (is_instance_valid(player.facility_dialog) and player.facility_dialog.visible) \
		or (interactions != null and interactions.blocked()) \
		or (cashier != null and cashier.is_busy()) \
		or (checkout != null and is_instance_valid(checkout.guide)) \
		or (story != null and story.talking) or (merchant != null and merchant.shopping)

# 관리 메뉴(영업 일지)를 열 때 안내 패널을 바로 숨긴다. 게임이 멈춰 있는 동안에는 refresh 가 돌지 않으므로 직접 숨겨야 한다. 닫은 뒤에는 refresh 가 다시 보여 준다.
func hide_panel_for_menu() -> void:
	if panel != null: panel.root.hide()

func _process(delta: float) -> void:
	_update_cleanup_hint()
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0.0
	refresh()

func refresh() -> void:
	if not enabled:
		panel.display("", "")
		if is_instance_valid(npc): npc.queue_free()
		npc = null
		return
	OpeningJourneyFlow.initialize(get_parent())
	if OpeningPrologueFlow.pending():
		panel.root.hide()
		if not talking and not _blocked(): _begin_prologue(OpeningPrologueFlow.current())
		return
	for facility in get_tree().get_nodes_in_group("production_facility"):
		if not facility.output_collected.is_connected(_on_output_collected):
			facility.output_collected.connect(_on_output_collected)
	var step := flow.current()
	if step.is_empty():
		panel.display("", "")
		if is_instance_valid(npc): npc.leave()
		npc = null
		return
	var ready: bool = flow.seen(str(step["id"])) and flow.goal_met(step, get_parent())
	var completion_hint := "타블렌에게 이야기를 마저 들으세요. [E]" if step.get("actor", "self") == "merchant" else "완료했습니다. 이야기를 이어갑니다."
	panel.display("안내 · " + str(step["title"]), completion_hint if ready else str(step["objective"]))
	var menu = get_parent().get_node_or_null("UI/GameMenu")
	# 실제 목표를 수행하는 건축/생산 구역에서는 안내를 계속 보여 준다.
	panel.root.visible = not talking and not get_tree().paused and not manager.summary_open \
		and not player.shelf_panel.visible and not manager.management_menu.visible \
		and not bool(get_parent().get_meta("checkout_tutorial_dialogue", false)) \
		and not (is_instance_valid(player.facility_dialog) and player.facility_dialog.visible) \
		and not (menu != null and (menu.menu_open or menu.settings_panel.visible or menu.save_slot_panel.visible))
	if talking or _blocked(): return
	var actor := str(step.get("actor", "self"))
	if actor != "merchant":
		if is_instance_valid(npc): npc.queue_free()
		npc = null
		if actor == "self" or ready:
			if not flow.seen(str(step["id"])) or ready: _begin_step(step)
		return
	if is_instance_valid(npc) and _npc_needs_relocation():
		npc.global_position = _guidance_position()
	if not is_instance_valid(npc):
		npc = StoryNpc.new()
		npc.setup({"beat_id": "tutorial", "lines": step["lines"]})
		get_parent().get_node("Actors").add_child(npc)
		npc.global_position = _guidance_position()
		npc.mark.text = SETTINGS.merchant_name + " [E]"
		npc.mark.size.x = 180
		npc.mark.position.x = -90
		npc.mark.add_theme_font_size_override("font_size", 18)

# ---- 청소 단계(OpeningCleanup): 부서진 잔해 더미를 [E]로 치워 자재를 얻는다 ----
# ResidentRequestDirector 도 이 클래스를 상속해 같은 처리 함수를 돌리므로, 청소 안내는 원래 안내자 하나만 맡는다.
func _is_primary() -> bool:
	return get_script().resource_path == "res://script/world/shop/tutorial/tutorial_director.gd"

func _cleanup_active() -> bool:
	if not _is_primary() or not enabled or talking: return false
	var step := flow.current()
	return not step.is_empty() and str(step["id"]) == "cleanup" and flow.seen("cleanup")

func _store_cell(world_position: Vector2) -> Vector2:
	var floor_node = get_parent().get_node("Floor")
	var local: Vector2 = floor_node.to_local(world_position)
	return Vector2(local.x / floor_node.tile_width + local.y / floor_node.tile_height, local.y / floor_node.tile_height - local.x / floor_node.tile_width)

func _cell_world(cell: Vector2) -> Vector2:
	var floor_node = get_parent().get_node("Floor")
	return floor_node.to_global(Vector2((cell.x - cell.y) * 0.5 * floor_node.tile_width, (cell.x + cell.y) * 0.5 * floor_node.tile_height))

func _try_clean() -> bool:
	if not _cleanup_active() or _blocked(): return false
	var index := OpeningCleanup.nearest(_store_cell(player.global_position), OpeningCleanup.REACH_CELLS)
	if index < 0: return false
	var loot := OpeningCleanup.clean(index)
	cutscene.clear_pile(index)
	_show_cleanup_note("잔해를 치웠다 · %s (%d/%d)\n“%s”" % [OpeningCleanup.loot_text(loot), OpeningCleanup.cleaned_count(), OpeningCleanup.piles().size(), _cleanup_murmur(loot)])
	call_deferred("refresh")
	return true

# 더미를 치울 때마다 나오는 혼잣말: 치운 차례대로(`cleanup_murmur`), 아무것도 못 건진 더미는 따로(`cleanup_murmur_empty`).
func _cleanup_murmur(loot: Dictionary) -> String:
	var order: int = maxi(OpeningCleanup.cleaned_count() - 1, 0)

	if loot.is_empty():
		var empty: Array[String] = RequestTextData.lines("tutorial_dialogue", "cleanup_murmur_empty")
		return empty[order % empty.size()]

	var lines: Array[String] = RequestTextData.lines("tutorial_dialogue", "cleanup_murmur")
	return lines[mini(order, lines.size() - 1)]

func _ensure_cleanup_ui() -> void:
	if _cleanup_layer != null: return
	_cleanup_layer = CanvasLayer.new()
	_cleanup_layer.layer = 22
	add_child(_cleanup_layer)
	var settings := LabelSettings.new()
	settings.font_size = 20
	settings.font_color = Color(1, 0.95, 0.75)
	settings.outline_size = 6
	settings.outline_color = Color(0, 0, 0, 0.9)
	_cleanup_hint = Label.new()
	_cleanup_hint.label_settings = settings
	_cleanup_hint.text = "▼ [E] 잔해 치우기"
	_cleanup_hint.visible = false
	_cleanup_layer.add_child(_cleanup_hint)
	_cleanup_note = Label.new()
	_cleanup_note.label_settings = settings
	_cleanup_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cleanup_note.visible = false
	_cleanup_layer.add_child(_cleanup_note)

func _show_cleanup_note(text: String) -> void:
	_ensure_cleanup_ui()
	_cleanup_note.text = text
	_cleanup_note.visible = true
	var size: Vector2 = get_viewport().get_visible_rect().size
	_cleanup_note.size = Vector2(size.x, 60)
	_cleanup_note.position = Vector2(0, size.y * 0.3)
	get_tree().create_timer(2.6).timeout.connect(func() -> void:
		if is_instance_valid(_cleanup_note): _cleanup_note.visible = false)

func _update_cleanup_hint() -> void:
	if not _cleanup_active():
		if _cleanup_hint != null: _cleanup_hint.visible = false
		return
	_ensure_cleanup_ui()
	if not _cleanup_prepared:
		_cleanup_prepared = true
		cutscene.prepare_cleanup()  # 독백을 건너뛰고 불러온 경우에도 잔해가 보이게(기다리지 않는다)
	var index := OpeningCleanup.nearest(_store_cell(player.global_position))
	if index < 0 or get_tree().paused:
		_cleanup_hint.visible = false
		return
	var world_pos: Vector2 = _cell_world(OpeningCleanup.piles()[index]["stand"])
	var screen: Vector2 = get_viewport().get_canvas_transform() * world_pos
	_cleanup_hint.visible = true
	_cleanup_hint.position = screen + Vector2(-60, -70 + sin(Time.get_ticks_msec() / 220.0) * 5.0)

func try_interact() -> bool:
	if _try_clean(): return true
	if not enabled or talking or _blocked() or not is_instance_valid(npc): return false
	if player.global_position.distance_to(npc.global_position) > talk_distance: return false
	var step := flow.current()
	if step.is_empty(): return false
	_begin_step(step)
	return true

func _begin_prologue(moment: Dictionary) -> void:
	var lines := RequestTextData.lines("service_text",str(moment["id"]))
	if lines.is_empty(): return
	pending = {"prologue":str(moment["id"])}
	talking = true
	timer_was_paused = manager.hour_timer.paused
	physics_was_enabled = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("progressive_tutorial_dialogue",true)
	# 프롤로그 연출: 독백1 앞에 현대 편의점과 손님·도시 거리, 독백2 앞에 깨어나 숲과 부서진 가게가 보이는 장면(자동 검사에서는 꺼져 있다)
	cutscene.skippable = str(moment["id"]) == "prologue_last_shift"
	if str(moment["id"]) == "prologue_last_shift":
		await cutscene.play_intro()
		if _first_scene_skipped:  # 도입 도중 Esc 로 건너뛰었다: 이미 다음 장면으로 넘어갔다
			_first_scene_skipped = false
			return
	elif str(moment["id"]) == "prologue_unfamiliar_window": await cutscene.play_transition()
	var moment_id := str(moment["id"])
	dialogue.beat_handler = func(read_index: int) -> void: await cutscene.beat(moment_id, read_index)
	dialogue.start("나",null,lines)

# Esc: 첫 장면(손님 → 졸기)을 통째로 건너뛰고 곧바로 이세계에 떨어진 장면(깨어남)으로 간다.
var _first_scene_skipped: bool = false

func _skip_first_scene() -> void:
	_first_scene_skipped = true
	cutscene.abort()
	# 아직 돌고 있는 연출(걷기·페이드)이 끝나도록 몇 프레임 기다린 뒤 장면을 끝낸 것으로 처리한다
	for i in range(3): await get_tree().process_frame
	if not talking: return
	if dialogue.open:
		dialogue.line_index = dialogue.lines.size()
		dialogue.close()  # finished → _end_talk 가 장면 완료를 기록하고 다음 장면(깨어남)을 연다
	else:
		# 대화가 시작되기 전(도입 연출 중)이면 완독한 것으로 기록하고 곧바로 끝낸다
		OpeningPrologueFlow.complete(str(pending.get("prologue", "")))
		pending.clear()
		_end_talk()

func _begin_step(step: Dictionary) -> void:
	var id := str(step["id"])
	var ready := flow.seen(id) and flow.goal_met(step, get_parent())
	var lines: Array[String] = []
	lines.assign(step["completion"] if ready else step["lines"])
	pending = {"step":step, "action":"claim" if ready else ("intro" if not flow.seen(id) else "repeat")}
	if not talking:
		talking = true
		timer_was_paused = manager.hour_timer.paused
		physics_was_enabled = player.is_physics_processing()
	panel.root.hide()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("progressive_tutorial_dialogue", true)
	var merchant: bool = str(step.get("actor", "self")) == "merchant"
	dialogue.start(SETTINGS.merchant_name if merchant else "나", ArtLoader.load_texture("res://art/npc/npc_placeholder.png") if merchant else null, lines)

func _on_trade(_id: String) -> void:
	if not OpeningJourneyFlow.trade():
		barter_panel.refresh()
		return
	# 닫기 신호로 대화 상태를 풀지 않고 교환 결과 대화로 이어 간다.
	barter_panel.root.hide()
	barter_panel.backdrop.hide()
	_begin_step(flow.current())

func _unhandled_input(event: InputEvent) -> void:
	if _is_primary() and cutscene != null and cutscene.enabled and cutscene.skippable and event.is_action_pressed("ui_cancel") and not event.is_echo() and str(pending.get("prologue", "")) == "prologue_last_shift":
		get_viewport().set_input_as_handled()
		_skip_first_scene()
		return
	if event.is_action_pressed("interact") and not event.is_echo() and try_interact():
		get_viewport().set_input_as_handled()

func _end_talk() -> void:
	dialogue.beat_handler = Callable()
	if cutscene != null: cutscene.skippable = false
	if not talking: return
	var completed_read: bool = dialogue.line_index >= dialogue.lines.size()
	var result := pending.duplicate(true)
	pending.clear()
	if result.has("prologue") and completed_read:
		OpeningPrologueFlow.complete(str(result["prologue"]))
		if str(result["prologue"]) == "prologue_unfamiliar_window": cutscene.play_outro()
	elif not result.is_empty() and completed_read:
		var step: Dictionary = result["step"]
		if flow.current().get("id", "") == step.get("id", ""):
			if result["action"] == "intro": flow.introduce(step)
			elif result["action"] == "claim": flow.claim(step, get_parent())
			if step["id"] == "barter" and not OpeningJourneyFlow.traded():
				barter_panel.display()
				return
	talking = false
	get_parent().remove_meta("progressive_tutorial_dialogue")
	if is_instance_valid(manager): manager.hour_timer.paused = timer_was_paused
	if is_instance_valid(player): player.set_physics_process(physics_was_enabled)
	if not is_inside_tree() or is_queued_for_deletion(): return
	call_deferred("refresh")
	var checkout = get_parent().get_node_or_null("CheckoutTutorial")
	if checkout != null: checkout.call_deferred("try_start")

func _guidance_position() -> Vector2:
	var floor_node = get_parent().get_node("Floor")
	var build = get_parent().get_node("BuildManager")
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, floor_node.columns, floor_node.rows)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for x in range(floor_node.columns):
		for y in range(floor_node.rows):
			astar.set_point_solid(Vector2i(x, y), build.is_cell_blocked_for_customer(Vector2i(x, y)))
	var start: Vector2i = floor_node.local_to_grid(floor_node.to_local(player.global_position))
	start = Vector2i(clampi(start.x, 0, floor_node.columns - 1), clampi(start.y, 0, floor_node.rows - 1))
	astar.set_point_solid(start, false)
	var best: Vector2 = player.global_position + Vector2(180, 0)
	var best_score: float = -1.0
	for x in range(1, floor_node.columns - 1):
		for y in range(1, floor_node.rows - 1):
			var cell := Vector2i(x, y)
			if build.is_cell_blocked_for_customer(cell) or astar.get_id_path(start, cell).is_empty(): continue
			var position: Vector2 = floor_node.to_global(floor_node.grid_to_local(cell))
			var clearance: float = position.distance_to(player.global_position)
			for object in get_parent().get_node("Objects").get_children():
				if object.get_meta("is_build_preview", false) or object.is_queued_for_deletion(): continue
				clearance = minf(clearance, position.distance_to(object.global_position))
				if object.is_in_group("register"):
					for service_cell in object.get_worker_cells() + object.get_checkout_cells():
						clearance = minf(clearance, position.distance_to(floor_node.to_global(floor_node.grid_to_local(service_cell))))
			if clearance > best_score:
				best_score = clearance
				best = position
	return best

func _npc_needs_relocation() -> bool:
	var floor_node = get_parent().get_node("Floor")
	var cell: Vector2i = floor_node.local_to_grid(floor_node.to_local(npc.global_position))
	if get_parent().get_node("BuildManager").is_cell_blocked_for_customer(cell): return true
	for object in get_parent().get_node("Objects").get_children():
		if object.get_meta("is_build_preview", false) or object.is_queued_for_deletion(): continue
		if npc.global_position.distance_to(object.global_position) < 100: return true
	return false

func _on_output_collected(item_id: String, amount: int) -> void:
	var local_bread: bool = item_id == "camp_bread" or (item_id == "bread" and not PlayerProgress.story_beat_days.has(CraftingPathFlow.NEW_GAME))
	if enabled and amount > 0 and local_bread and flow.seen("production"):
		PlayerProgress.record_story_beat("tutorial_event:produced_bread", GameState.total_day)

func _exit_tree() -> void:
	pending.clear()
	_end_talk()
