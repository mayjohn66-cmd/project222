class_name TutorialDirector
extends Node
const SETTINGS = preload("res://scenes/shop/tutorial/default_tutorial.tres")
@export var enabled: bool = true
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
	return not enabled or (flow.seen("checkout") or flow.done("checkout"))

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
	panel.display("안내 · " + str(step["title"]), "완료! 안내 NPC에게 보상을 받으세요. [E]" if ready else str(step["objective"]))
	var menu = get_parent().get_node_or_null("UI/GameMenu")
	# 실제 목표를 수행하는 건축/생산 구역에서는 안내를 계속 보여 준다.
	panel.root.visible = not talking and not get_tree().paused and not manager.summary_open \
		and not player.shelf_panel.visible and not manager.management_menu.visible \
		and not bool(get_parent().get_meta("checkout_tutorial_dialogue", false)) \
		and not (is_instance_valid(player.facility_dialog) and player.facility_dialog.visible) \
		and not (menu != null and (menu.menu_open or menu.settings_panel.visible or menu.save_slot_panel.visible))
	if talking or _blocked(): return
	if not is_instance_valid(npc):
		npc = StoryNpc.new()
		npc.setup({"beat_id": "tutorial", "lines": step["lines"]})
		get_parent().get_node("Actors").add_child(npc)
		var floor_node = get_parent().get_node("Floor")
		npc.global_position = floor_node.to_global(floor_node.grid_to_local(Vector2i(2, maxi(1, floor_node.rows - 2))))
		npc.mark.text = "안내 [E]"
		npc.mark.position.x = -52
		npc.mark.add_theme_font_size_override("font_size", 18)

func try_interact() -> bool:
	if not enabled or talking or _blocked() or not is_instance_valid(npc): return false
	if player.global_position.distance_to(npc.global_position) > 90: return false
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
	dialogue.start("이웃 주민", ArtLoader.load_texture("res://art/npc/npc_placeholder.png"), lines)
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

func _on_output_collected(item_id: String, amount: int) -> void:
	if enabled and amount > 0 and item_id == "bread" and flow.seen("production"):
		PlayerProgress.record_story_beat("tutorial_event:produced_bread", GameState.total_day)

func _exit_tree() -> void:
	_end_talk()
