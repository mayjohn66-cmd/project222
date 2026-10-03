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

func _ready() -> void:
	flow.settings = SETTINGS
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_talk)
	panel = TutorialGoalPanel.new()
	add_child(panel)
	call_deferred("refresh")

func is_guiding() -> bool:
	return enabled and not flow.current().is_empty()

func permits_first_checkout() -> bool:
	var step := flow.current()
	return not enabled or str(step.get("id", "")) == "checkout" or flow.done("checkout")

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

func _process(delta: float) -> void:
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
	panel.display("안내 · " + str(step["title"]), "완료! %s에게 보상을 받으세요. [E]" % SETTINGS.guide_name if ready else str(step["objective"]))
	var menu = get_parent().get_node_or_null("UI/GameMenu")
	# 실제 목표를 수행하는 건축/생산 구역에서는 안내를 계속 보여 준다.
	panel.root.visible = not talking and not get_tree().paused and not manager.summary_open \
		and not player.shelf_panel.visible and not manager.management_menu.visible \
		and not bool(get_parent().get_meta("checkout_tutorial_dialogue", false)) \
		and not (is_instance_valid(player.facility_dialog) and player.facility_dialog.visible) \
		and not (menu != null and (menu.menu_open or menu.settings_panel.visible or menu.save_slot_panel.visible))
	if talking or _blocked(): return
	if str(step["id"]) == "checkout" and not ready:
		# 같은 안내 인물이 첫 손님 역할을 맡는다. 두 NPC를 동시에 세우지 않는다.
		if is_instance_valid(npc): npc.queue_free()
		npc = null
		return
	if is_instance_valid(npc) and _npc_needs_relocation():
		npc.global_position = _guidance_position()
	if not is_instance_valid(npc):
		npc = StoryNpc.new()
		npc.setup({"beat_id": "tutorial", "lines": step["lines"]})
		get_parent().get_node("Actors").add_child(npc)
		var floor_node = get_parent().get_node("Floor")
		npc.global_position = _guidance_position()
		npc.mark.text = SETTINGS.guide_name + " [E]"
		npc.mark.size.x = 180
		npc.mark.position.x = -90
		npc.mark.add_theme_font_size_override("font_size", 18)

func try_interact() -> bool:
	if not enabled or talking or _blocked() or not is_instance_valid(npc): return false
	if player.global_position.distance_to(npc.global_position) > talk_distance: return false
	var step := flow.current()
	if step.is_empty(): return false
	var lines: Array[String] = []
	var gifts: Array[String] = []
	if not flow.seen(str(step["id"])):
		gifts = flow.introduce(step)
		lines.assign(step["lines"])
	elif flow.goal_met(step, get_parent()):
		gifts = flow.claim(step, get_parent())
		lines.assign(step["completion"])
	else:
		lines.assign(step["lines"])
	if not gifts.is_empty(): lines.append("받은 물건: " + ", ".join(gifts))
	talking = true
	panel.root.hide()
	timer_was_paused = manager.hour_timer.paused
	manager.hour_timer.paused = true
	physics_was_enabled = player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("progressive_tutorial_dialogue", true)
	dialogue.start(SETTINGS.guide_name, ArtLoader.load_texture("res://art/npc/npc_placeholder.png"), lines)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() and try_interact():
		get_viewport().set_input_as_handled()

func _end_talk() -> void:
	if not talking: return
	talking = false
	get_parent().remove_meta("progressive_tutorial_dialogue")
	if is_instance_valid(manager): manager.hour_timer.paused = timer_was_paused
	if is_instance_valid(player): player.set_physics_process(physics_was_enabled)
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
	if enabled and amount > 0 and item_id == "bread" and flow.seen("production"):
		PlayerProgress.record_story_beat("tutorial_event:produced_bread", GameState.total_day)

func _exit_tree() -> void:
	_end_talk()
