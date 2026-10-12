class_name ManualCheckoutController
extends Node

signal checkout_completed(customer, amount: int)
signal checkout_cancelled
@export var checkout_seconds: float = 1.2
@export var cashier_distance: float = 28.0
var player
var manager
var floor_node
var panel: ManualCheckoutPanel
var food_cleanup: RegisterDashboardPanel
var active_register
var active_customer
var active_cell := Vector2i(-1, -1)
var elapsed: float = 0.0

func _ready() -> void:
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	floor_node = get_parent().get_node("Floor")
	panel = ManualCheckoutPanel.new()
	add_child(panel)
	panel.checkout_requested.connect(try_interact)
	panel.cancel_requested.connect(cancel_checkout)
	food_cleanup = RegisterDashboardPanel.new()
	add_child(food_cleanup)
	var repair := PowerRepairDirector.new()
	repair.name = "PowerRepairDirector"
	add_child(repair)

func is_busy() -> bool:
	return is_instance_valid(active_register)

func blocked() -> bool:
	var interactions = get_parent().get_node_or_null("WorldInteractions")
	var story = get_parent().get_node_or_null("StoryDirector")
	var merchant = get_parent().get_node_or_null("SecretMerchantDirector")
	return get_tree().paused or player.in_production_room or player.in_warehouse_room \
		or (story != null and story.talking) or (merchant != null and merchant.shopping) \
		or player.shelf_panel.visible or player.rumor_dialog.visible \
		or (is_instance_valid(player.facility_dialog) and player.facility_dialog.visible) \
		or (interactions != null and interactions.blocked())

func _cashier_cell(register) -> Vector2i:
	var nearest := Vector2i(-1, -1)
	var distance: float = cashier_distance
	for cell in register.get_worker_cells():
		var position: Vector2 = floor_node.to_global(floor_node.grid_to_local(cell))
		var value: float = player.global_position.distance_to(position)
		if value <= distance:
			distance = value
			nearest = cell
	return nearest

func nearest_register():
	for register in get_tree().get_nodes_in_group("register"):
		if not is_instance_valid(register) or register.is_queued_for_deletion(): continue
		if register.get_parent() != get_parent().get_node("Objects") or register.get_meta("is_build_preview", false): continue
		if _cashier_cell(register) != Vector2i(-1, -1): return register
	return null

func try_interact() -> bool:
	if blocked(): return false
	if is_busy(): return true
	var register = nearest_register()
	if register == null: return false
	var customer = register.get_waiting_customer()
	if customer == null:
		panel.display("", 0.0, false, false)
		food_cleanup.open()
		return true
	if not manager.shop_open: return false
	if not _can_charge(customer): return true
	var cell := _cashier_cell(register)
	if not register.try_reserve_worker(player): return true
	if not register.try_reserve_worker_cell(cell, player):
		register.release_worker_reservation(player)
		return true
	active_register = register
	active_customer = customer
	active_cell = cell
	elapsed = 0.0
	return true

func _can_charge(customer) -> bool:
	if is_instance_valid(customer) and FoodShelfLife.tracked(customer.carried_item_id) and FoodShelfLife.customer_total(customer) <= 0:
		customer.go_to_exit()
		return false
	return is_instance_valid(customer) and not customer.is_queued_for_deletion() \
		and not customer.force_exit_requested and not customer.purchase_completed \
		and not customer.carried_item_id.is_empty() and customer.carried_amount > 0

func _process(delta: float) -> void:
	if active_cell != Vector2i(-1, -1) and not is_instance_valid(active_register):
		cancel_checkout()
	if is_busy():
		if not manager.shop_open or not _can_charge(active_customer) \
				or active_register.is_queued_for_deletion() \
				or active_register.get_waiting_customer() != active_customer \
				or _cashier_cell(active_register) != active_cell:
			cancel_checkout()
		elif not blocked():
			elapsed += delta
			if elapsed >= checkout_seconds:
				_finish_checkout()
	_update_panel()

func _finish_checkout() -> void:
	var customer = active_customer
	var register = active_register
	var price: int = FoodShelfLife.customer_total(customer)
	# 기존 매출·상품·퇴장 처리를 재사용해 결제 중복을 막는다.
	if customer.has_method("complete_checkout_by_player"):
		customer.complete_checkout_by_player()
	else:
		customer.complete_checkout_by_worker()
	if register.get_waiting_customer() == customer and customer.purchase_completed:
		register.finish_checkout()
	cancel_checkout()
	if customer.purchase_completed:
		checkout_completed.emit(customer, price)

func cancel_checkout() -> void:
	if is_instance_valid(active_register):
		active_register.release_worker_reservation(player)
		active_register.release_worker_cell(player)
	active_register = null
	active_customer = null
	active_cell = Vector2i(-1, -1)
	elapsed = 0.0
	if is_inside_tree(): checkout_cancelled.emit()

func _update_panel() -> void:
	if blocked():
		panel.display("", 0.0, false, false)
		return
	var register = active_register if is_busy() else nearest_register()
	if register == null:
		panel.display("", 0.0, false, false)
		return
	var customer = register.get_waiting_customer()
	if customer == null:
		panel.display("계산대 · 진열 상품 확인" if PowerRepairFlow.powered() else "계산대 전원 꺼짐 · 옆 장부로 상품 확인", 0.0, false, true, "상품 조회 [E]" if PowerRepairFlow.powered() else "장부 조회 [E]")
		return
	if not manager.shop_open:
		panel.display("", 0.0, false, false)
		return
	if not _can_charge(customer):
		panel.display("계산을 기다리는 손님이 없습니다", 0.0, false, false)
		return
	var available: bool = not register.is_reserved_for_other(player) \
		and register.is_worker_cell_available(_cashier_cell(register), player)
	var caption := "%s ×%d · %dG" % [ItemData.get_item_name(customer.carried_item_id),
		customer.carried_amount, FoodShelfLife.customer_total(customer)]
	if not available: caption = "직원이 계산 중입니다"
	panel.display(caption, elapsed / maxf(checkout_seconds, 0.01), is_busy(), available, "결제 [E]" if PowerRepairFlow.powered() else "손으로 계산 [E]")

func _exit_tree() -> void:
	cancel_checkout()
