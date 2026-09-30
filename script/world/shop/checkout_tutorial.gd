class_name CheckoutTutorial
extends Node

const GUIDE_SCENE = preload("res://scenes/shop/actors/checkout_guide.tscn")
const BEAT_ID: String = "tutorial_manual_checkout"
@export var intro_lines: Array[String] = [
	"개업을 축하해! 내가 첫 손님이 되어 줄게.",
	"진열대에서 물건을 골라 계산대로 가져갈게. 직원이 없어도 네가 계산할 수 있어."
]
@export var checkout_lines: Array[String] = [
	"물건을 골랐어. 표시된 계산대 뒤쪽으로 와 줘.",
	"거기서 E나 결제 버튼을 누르면 돼. 계산이 끝날 때까지 자리에 있어 줘."
]
@export var finished_lines: Array[String] = [
	"결제가 끝났네! 판매 대금은 보유금에, 판매 기록은 오늘 매출에 들어가.",
	"직원이 없을 때는 이렇게 직접 계산하면 돼. 문을 닫아도 하루의 시간은 계속 흐르니 기억해 줘!"
]
var manager
var player
var cashier: ManualCheckoutController
var dialogue: StoryDialoguePanel
var guide: CheckoutGuideCustomer
var guide_register
var guide_cell := Vector2i(-1, -1)
var stage: String = ""
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
		if stage == "shopping" and guide_register.get_waiting_customer() == guide:
			stage = "checkout"
			_show_dialogue(checkout_lines)
		return
	if not stage.is_empty(): _abort()
	if not completed(): try_start()

func try_start() -> void:
	var tutorial = get_parent().get_node_or_null("TutorialDirector")
	if tutorial != null and not tutorial.permits_first_checkout():
		if manager.shop_open and not completed():
			manager.customer_spawner.process_mode = Node.PROCESS_MODE_DISABLED
		return
	if completed() or is_instance_valid(guide) or not manager.shop_open \
			or manager.closing_shop or manager.summary_open or cashier.blocked(): return
	var story = get_parent().get_node_or_null("StoryDirector")
	var merchant = get_parent().get_node_or_null("SecretMerchantDirector")
	if (story != null and story.talking) or (merchant != null and merchant.shopping): return
	var items := ShopStock.get_stocked_item_ids(get_tree())
	items = items.filter(func(item_id: String) -> bool:
		return ItemData.get_item_price(item_id) > 0 and ItemData.get_sellable_items().has(item_id))
	if items.is_empty(): return
	var door
	for candidate in get_tree().get_nodes_in_group("door"):
		if candidate.get_parent() == get_parent().get_node("Objects") \
				and not candidate.get_meta("is_build_preview", false) and not candidate.is_queued_for_deletion():
			door = candidate
			break
	if door == null: return
	for register in get_tree().get_nodes_in_group("register"):
		if register.get_parent() != get_parent().get_node("Objects") \
				or register.is_queued_for_deletion() or register.get_meta("is_build_preview", false): continue
		if register.has_waiting_customer() or register.is_reserved_for_other(player): continue
		for cell in register.get_worker_cells():
			if not register.is_worker_cell_available(cell, player): continue
			if not register.try_reserve_worker(player): continue
			if not register.try_reserve_worker_cell(cell, player):
				register.release_worker_reservation(player)
				continue
			guide_register = register
			guide_cell = cell
			break
		if is_instance_valid(guide_register): break
	if not is_instance_valid(guide_register): return
	guide = GUIDE_SCENE.instantiate()
	guide.guide_register = guide_register
	guide.guide_item_id = items[0]
	get_parent().get_node("Actors").add_child(guide)
	guide.global_position = door.get_customer_target_position()
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
	dialogue.start("이웃 주민", ArtLoader.load_texture("res://art/npc/npc_placeholder.png"), lines)

func _restore_dialogue_state() -> void:
	if not dialogue_open: return
	dialogue_open = false
	get_parent().remove_meta("checkout_tutorial_dialogue")
	manager.hour_timer.paused = previous_timer_paused
	player.set_physics_process(previous_player_physics)

func _on_dialogue_finished() -> void:
	_restore_dialogue_state()
	if aborting or not is_instance_valid(guide): return
	if stage == "intro":
		stage = "shopping"
		guide.start_shopping()
	elif stage == "finished":
		guide.go_to_exit()
		_release()
		guide = null
		stage = ""

func _on_checkout_completed(customer, _amount: int) -> void:
	if customer != guide: return
	PlayerProgress.record_story_beat(BEAT_ID, GameState.total_day)
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
