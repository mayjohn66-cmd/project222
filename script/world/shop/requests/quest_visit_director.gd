class_name QuestVisitDirector
extends Node
## 주민 부탁을 NPC가 '손님으로 입장해' 계산대에서 건네게 한다(시험판: data/shop/requests/quest_visits.csv 의 부탁만).
## 흐름: 개점 중 부탁 차례가 되면 그 NPC가 문으로 들어와 → 소개(부탁) 대사 → 부탁 수락 기록 → 실제 상품을 계산 → 필요한 물건 안내 → 퇴장.
## 열 수 없는 때(영업 중 아님·진열 상품 없음·계산대 없음)는 아무 일도 하지 않는다. 그때는 기존 서 있는 NPC(ResidentRequestDirector)가 맡는다.
## 튜토리얼의 CheckoutTutorial 과 같은 안내 손님(CheckoutGuideCustomer)을 쓰되, 튜토리얼 코드는 건드리지 않는다.

const CSV_PATH := "res://data/shop/requests/quest_visits.csv"
const GUIDE_SCENE = preload("res://scenes/shop/actors/checkout_guide.tscn")
const POLL_SECONDS := 1.0

static var _ids: Array[String] = []
static var _loaded := false

var manager
var player
var cashier: ManualCheckoutController
var dialogue: StoryDialoguePanel
var guide: CheckoutGuideCustomer
var guide_register
var guide_cell := Vector2i(-1, -1)
var customer_cell := Vector2i(-1, -1)
var request: Dictionary = {}
var stage: String = ""
var dialogue_open: bool = false
var previous_timer_paused: bool = false
var previous_player_physics: bool = true
var aborting: bool = false
var elapsed: float = 0.0

# ---- 대상 부탁 목록 ----
static func ids() -> Array[String]:
	if not _loaded:
		_loaded = true
		_ids.clear()
		var file := FileAccess.open(CSV_PATH, FileAccess.READ)
		if file != null:
			file.get_csv_line()
			while not file.eof_reached():
				var cells := file.get_csv_line()
				if cells.size() >= 1 and not cells[0].strip_edges().is_empty(): _ids.append(cells[0].strip_edges())
	return _ids

# 지금 차례인 부탁이 '손님 입장'으로 건네야 하는 것이면 그 부탁을, 아니면 {}.
static func pending_request() -> Dictionary:
	var current := ResidentRequestFlow.current()
	if current.is_empty() or ResidentRequestFlow.accepted(str(current["id"])): return {}
	if not ids().has(str(current["id"])): return {}
	if not ResidentStoryFlow.pending_introduction().is_empty(): return {} # 새 손님 소개가 먼저다
	return current

# 서 있는 NPC를 숨겨야 하나: 영업 중이라 손님으로 올 수 있을 때만 숨긴다. 영업 전·후에는 기존 NPC가 대체한다.
static func replaces_standing_npc(world: Node) -> bool:
	if pending_request().is_empty(): return false
	var manager = world.get_node_or_null("DayManager")
	return manager != null and bool(manager.shop_open) and not bool(manager.closing_shop)

func _ready() -> void:
	manager = get_parent().get_node("DayManager")
	player = get_parent().get_node("Actors/Player")
	cashier = get_parent().get_node("ManualCheckoutController")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)
	cashier.checkout_completed.connect(_on_checkout_completed)
	cashier.checkout_cancelled.connect(_keep_position)
	manager.shop_opened.connect(try_start)

func _process(delta: float) -> void:
	if is_instance_valid(guide):
		if not manager.shop_open or manager.closing_shop or guide.force_exit_requested \
				or not is_instance_valid(guide_register) or guide_register.is_queued_for_deletion():
			_abort()
			return
		if stage == "checkout" and not guide.purchase_completed and not guide_register.has_waiting_customer():
			guide_register.request_checkout(guide)
		return
	if not stage.is_empty():
		_abort()
		return
	elapsed += delta
	if elapsed < POLL_SECONDS: return
	elapsed = 0.0
	try_start()

func try_start() -> void:
	if is_instance_valid(guide): return
	var wanted := pending_request()
	if wanted.is_empty(): return
	var world := get_parent()
	var tutorial = world.get_node_or_null("TutorialDirector")
	if tutorial != null and tutorial.enabled and tutorial.is_guiding(): return
	if not manager.shop_open or manager.closing_shop or manager.summary_open or cashier.blocked(): return
	if get_tree().paused: return
	var checkout = world.get_node_or_null("CheckoutTutorial")
	if checkout != null and (is_instance_valid(checkout.guide) or not checkout.stage.is_empty()): return
	var story = world.get_node_or_null("StoryDirector")
	var merchant = world.get_node_or_null("SecretMerchantDirector")
	if (story != null and story.talking) or (merchant != null and merchant.shopping): return
	var items := ShopStock.get_stocked_item_ids(get_tree())
	items = items.filter(func(item_id: String) -> bool:
		return ItemData.get_item_price(item_id) > 0 and ItemData.get_sellable_items().has(item_id))
	if items.is_empty(): return
	var door
	for candidate in get_tree().get_nodes_in_group("door"):
		if candidate.get_parent() == world.get_node("Objects") \
				and not candidate.get_meta("is_build_preview", false) and not candidate.is_queued_for_deletion():
			door = candidate
			break
	if door == null: return
	var build = world.get_node("BuildManager")
	for register in get_tree().get_nodes_in_group("register"):
		if register.get_parent() != world.get_node("Objects") \
				or register.is_queued_for_deletion() or register.get_meta("is_build_preview", false): continue
		if register.has_waiting_customer(): continue
		var free_customer_cell := Vector2i(-1, -1)
		for cell in register.get_checkout_cells():
			if not build.is_cell_blocked_for_customer(cell):
				free_customer_cell = cell
				break
		if free_customer_cell == Vector2i(-1, -1): continue
		for cell in register.get_worker_cells():
			if build.is_cell_blocked_for_customer(cell): continue
			if not register.reserve_tutorial_cashier(player, cell): continue
			guide_register = register
			guide_cell = cell
			customer_cell = free_customer_cell
			break
		if is_instance_valid(guide_register): break
	if not is_instance_valid(guide_register): return
	request = wanted
	guide = GUIDE_SCENE.instantiate()
	guide.guide_register = guide_register
	guide.guide_item_id = items[0]
	world.get_node("Actors").add_child(guide)
	_relabel(guide, str(request["npc"]))
	guide.global_position = door.get_customer_target_position()
	stage = "intro"
	manager.customer_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	_show_dialogue(_lines("lines"))

# 안내 손님이 만든 이름표(마지막 Label)를 부탁한 사람 이름으로 바꾼다.
func _relabel(customer: Node, npc_name: String) -> void:
	for child in customer.get_children():
		if child is Label and child.text == TutorialDirector.SETTINGS.guide_name: child.text = npc_name

func _lines(field: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(request.get(field, []))
	return result

func _hint_lines() -> Array[String]:
	var result: Array[String] = []
	result.append("필요한 물건은 %s %d개야. 소지품에 챙겨 줘. 진열대나 보관 선반에 있다면 먼저 꺼내 줘." % [ItemData.get_item_name(str(request["item"])), int(request["amount"])])
	result.append("준비되면 가게 안에서 다시 말을 걸어 줘.")
	return result

func _show_dialogue(lines: Array[String]) -> void:
	dialogue_open = true
	get_parent().set_meta("checkout_tutorial_dialogue", true)
	previous_timer_paused = manager.hour_timer.paused
	manager.hour_timer.paused = true
	previous_player_physics = player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	dialogue.start(str(request["npc"]), ArtLoader.load_texture("res://art/npc/npc_placeholder.png"), lines)

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
		# 부탁을 끝까지 들었으니 수락으로 기록한다(서 있는 NPC와 같은 기록).
		ResidentRequestFlow.accept(request)
		if guide.prepare_practice_checkout(customer_cell):
			stage = "checkout"
		else:
			_abort()
	elif stage == "finished":
		guide.go_to_exit()
		_release()
		guide = null
		stage = ""
		request = {}

func _on_checkout_completed(customer, _amount: int) -> void:
	if customer != guide: return
	stage = "finished"
	_show_dialogue(_hint_lines())

func _keep_position() -> void:
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
	if is_instance_valid(manager) and manager.shop_open and not manager.closing_shop:
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
	request = {}
	aborting = false

func _exit_tree() -> void:
	_restore_dialogue_state()
	_release()
