class_name CheckoutTutorial
extends Node

const GUIDE_SCENE = preload("res://scenes/shop/actors/checkout_guide.tscn")
const BEAT_ID: String = "tutorial_manual_checkout"
var intro_lines: Array[String]:
	get: return RequestTextData.lines("tutorial_dialogue", ("raw_checkout_" if material_visit else "checkout_") + "intro")
var checkout_lines: Array[String]:
	get: return RequestTextData.lines("tutorial_dialogue", ("raw_checkout_" if material_visit else "checkout_") + "checkout")
var finished_lines: Array[String]:
	get: return RequestTextData.lines("tutorial_dialogue", ("raw_checkout_" if material_visit else "checkout_") + "finished")
var manager
var player
var cashier: ManualCheckoutController
var dialogue: StoryDialoguePanel
var guide: CheckoutGuideCustomer
var guide_register
var guide_cell := Vector2i(-1, -1)
var customer_cell := Vector2i(-1, -1)
var stage: String = ""
var material_visit: bool = false
var dialogue_open: bool = false
var previous_timer_paused: bool = false
var previous_player_physics: bool = true
var aborting: bool = false
var marker: Node2D

func _ready() -> void:
	manager = get_parent().get_node("DayManager")
	player = get_parent().get_node("Actors/Player")
	cashier = get_parent().get_node("ManualCheckoutController")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)
	cashier.checkout_completed.connect(_on_checkout_completed)
	cashier.checkout_cancelled.connect(_keep_tutorial_position)
	manager.shop_opened.connect(try_start)
	# 이 감독이 뒤에 있으므로 첫 개점 직후 기존 손님 생성보다 먼저 준비한다.

func completed() -> bool:
	return not PlayerProgress.can_play_story_beat(BEAT_ID, 0, GameState.total_day)

func _process(_delta: float) -> void:
	if is_instance_valid(guide):
		if not manager.shop_open or manager.closing_shop or guide.force_exit_requested \
				or not is_instance_valid(guide_register) or guide_register.is_queued_for_deletion():
			_abort()
			return
		if stage == "checkout" and not guide.purchase_completed and not guide_register.has_waiting_customer():
			guide_register.request_checkout(guide)
		return
	if not stage.is_empty(): _abort()
	try_start()

func try_start() -> void:
	if is_instance_valid(guide): return
	var tutorial = get_parent().get_node_or_null("TutorialDirector")
	material_visit = completed()
	if material_visit:
		if tutorial == null or not tutorial.enabled or tutorial.flow.current().get("id", "") != "raw_sale" \
				or PlayerProgress.story_beat_days.has(OpeningJourneyFlow.RAW_SALE): return
	elif tutorial != null and not tutorial.permits_first_checkout(): return
	if not manager.shop_open \
			or manager.closing_shop or manager.summary_open or cashier.blocked(): return
	var story = get_parent().get_node_or_null("StoryDirector")
	var merchant = get_parent().get_node_or_null("SecretMerchantDirector")
	if (story != null and story.talking) or (merchant != null and merchant.shopping): return
	var items := ShopStock.get_stocked_item_ids(get_tree())
	items = items.filter(func(item_id: String) -> bool:
		return ItemData.get_item_price(item_id) > 0 and ItemData.get_sellable_items().has(item_id))
	if material_visit: items = items.filter(func(id: String) -> bool: return OpeningJourneyFlow.is_raw_material(id))
	if items.is_empty(): return
	var door
	for candidate in get_tree().get_nodes_in_group("door"):
		if candidate.get_parent() == get_parent().get_node("Objects") \
				and not candidate.get_meta("is_build_preview", false) and not candidate.is_queued_for_deletion():
			door = candidate
			break
	var build = get_parent().get_node("BuildManager")
	for register in get_tree().get_nodes_in_group("register"):
		if register.get_parent() != get_parent().get_node("Objects") \
				or register.is_queued_for_deletion() or register.get_meta("is_build_preview", false): continue
		if register.has_waiting_customer(): continue
		var available_customer_cell := Vector2i(-1, -1)
		for cell in register.get_checkout_cells():
			if not build.is_cell_blocked_for_customer(cell):
				available_customer_cell = cell
				break
		if available_customer_cell == Vector2i(-1, -1): continue
		for cell in register.get_worker_cells():
			if build.is_cell_blocked_for_customer(cell): continue
			if not register.reserve_tutorial_cashier(player, cell): continue
			guide_register = register
			guide_cell = cell
			customer_cell = available_customer_cell
			break
		if is_instance_valid(guide_register): break
	if not is_instance_valid(guide_register): return
	guide = GUIDE_SCENE.instantiate()
	guide.guide_register = guide_register
	guide.guide_item_id = items[0]
	get_parent().get_node("Actors").add_child(guide)
	guide.global_position = door.get_customer_target_position() if door != null else build.get_cell_world_position(customer_cell)
	stage = "intro"
	manager.customer_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	marker = CashierMarker.new()
	get_parent().add_child(marker)
	var floor_node = get_parent().get_node("Floor")
	marker.global_position = floor_node.to_global(floor_node.grid_to_local(guide_cell))
	_show_dialogue(intro_lines)

func _show_dialogue(lines: Array[String]) -> void:
	dialogue_open = true
	get_parent().set_meta("checkout_tutorial_dialogue", true)
	previous_timer_paused = manager.hour_timer.paused
	manager.hour_timer.paused = true
	previous_player_physics = player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	dialogue.start(TutorialDirector.SETTINGS.guide_name, ArtLoader.load_texture("res://art/npc/npc_placeholder.png"), lines)

func _restore_dialogue_state() -> void:
	if not dialogue_open: return
	dialogue_open = false
	get_parent().remove_meta("checkout_tutorial_dialogue")
	manager.hour_timer.paused = previous_timer_paused
	player.set_physics_process(previous_player_physics)

func _on_dialogue_finished() -> void:
	_restore_dialogue_state()
	if aborting or not is_instance_valid(guide): return
	if dialogue.line_index < dialogue.lines.size():
		_abort()
		return
	if stage == "intro":
		var tutorial = get_parent().get_node_or_null("TutorialDirector")
		if tutorial != null:
			var step: Dictionary = tutorial.flow.current()
			if step.get("id", "") == ("raw_sale" if material_visit else "checkout"): tutorial.flow.introduce(step)
		if guide.prepare_practice_checkout(customer_cell):
			stage = "checkout"
			_show_dialogue(checkout_lines)
		else:
			_abort()
	elif stage == "finished":
		guide.go_to_exit()
		_release()
		guide = null
		stage = ""

func _on_checkout_completed(customer, _amount: int) -> void:
	if customer != guide: return
	PlayerProgress.record_story_beat(OpeningJourneyFlow.RAW_SALE if material_visit else BEAT_ID, GameState.total_day)
	stage = "finished"
	_show_dialogue(finished_lines)

func _keep_tutorial_position() -> void:
	# 연습 도중 취소해도 안내 위치를 직원이 차지하지 않게 한다.
	if not aborting and is_instance_valid(guide) and is_instance_valid(guide_register) \
			and manager.shop_open and not manager.closing_shop:
		guide_register.try_reserve_worker(player)
		guide_register.try_reserve_worker_cell(guide_cell, player)

func _release() -> void:
	if is_instance_valid(guide_register):
		guide_register.release_worker_reservation(player)
		guide_register.release_worker_cell(player)
	guide_register = null
	guide_cell = Vector2i(-1, -1)
	customer_cell = Vector2i(-1, -1)
	if is_instance_valid(marker): marker.queue_free()
	marker = null
	if manager.shop_open and not manager.closing_shop:
		manager.customer_spawner.process_mode = Node.PROCESS_MODE_INHERIT

func _abort() -> void:
	aborting = true
	if dialogue.open: dialogue.close()
	_restore_dialogue_state()
	if is_instance_valid(guide_register) and guide_register.get_waiting_customer() == guide:
		guide_register.finish_checkout()
	if is_instance_valid(guide) and not guide.force_exit_requested: guide.go_to_exit()
	_release()
	guide = null
	stage = ""
	aborting = false

func _exit_tree() -> void:
	_restore_dialogue_state()
	_release()

class CashierMarker extends Node2D:
	func _ready() -> void:
		z_index = 50
		var label := Label.new()
		label.text = "계산 위치"
		label.position = Vector2(-55, -27)
		label.add_theme_color_override("font_color", Color("ffe7a0"))
		label.add_theme_color_override("font_outline_color", Color("3a392c"))
		label.add_theme_constant_override("outline_size", 4)
		add_child(label)
	func _draw() -> void:
		draw_polyline(PackedVector2Array([Vector2(-24, 0), Vector2(0, -12), Vector2(24, 0),
			Vector2(0, 12), Vector2(-24, 0)]), Color("ffe7a0"), 3)
