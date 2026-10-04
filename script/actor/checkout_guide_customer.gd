class_name CheckoutGuideCustomer
extends "res://script/actor/customer.gd"

var guide_register
var guide_item_id: String = ""
var practice_item: bool = false

func _ready() -> void:
	choose_customer_type()
	rumor_checked = true
	super._ready()
	var label := Label.new()
	label.text = TutorialDirector.SETTINGS.guide_name
	label.position = Vector2(-65, -95)
	label.size = Vector2(130, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("ffe7a0"))
	label.add_theme_color_override("font_outline_color", Color("3a392c"))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

func choose_customer_type() -> void:
	customer_type_selected = true
	customer_type_id = "villager"
	customer_group_id = "normal"

func choose_wanted_item() -> String:
	wanted_amount = 1
	return guide_item_id

func find_register():
	return guide_register if is_instance_valid(guide_register) else null

func try_decoration_extra_purchase() -> void:
	pass # 첫 거래는 실제 진열 상품 하나를 구매한다.

func can_be_checked_out_by(actor: Node) -> bool:
	return actor == player

func complete_checkout_by_player() -> void:
	checkout_item() # 작별 대화가 끝나면 튜토리얼 감독이 퇴장시킨다.

func complete_checkout_by_worker() -> void:
	pass # 예약 전에 시작했던 직원 작업도 이 손님을 대신 결제하지 않는다.

func prepare_practice_checkout(cell: Vector2i) -> bool:
	if not visit_recorded:
		visit_recorded = true
		player.record_visitor(get_customer_type_id())
	carried_item_id = guide_item_id
	carried_amount = 0
	for shelf in get_parent().get_parent().get_node("Objects").get_children():
		if not shelf.is_in_group("shelf") or shelf.get_meta("is_build_preview", false) or shelf.is_queued_for_deletion(): continue
		if shelf.take_items_by_id(guide_item_id, 1) > 0:
			target_shelf = shelf
			carried_amount = 1
			break
	if carried_amount == 0:
		carried_item_id = ""
		return false
	moving = false
	velocity = Vector2.ZERO
	grid_path.clear()
	target_register = guide_register
	state = CustomerState.GO_TO_REGISTER
	global_position = floor_node.to_global(floor_node.grid_to_local(cell))
	return guide_register.request_checkout(self)

func _return_unpaid_items_to_shelf() -> void:
	if practice_item:
		carried_item_id = ""
		carried_amount = 0
		return
	super._return_unpaid_items_to_shelf()

