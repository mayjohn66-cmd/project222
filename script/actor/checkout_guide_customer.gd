class_name CheckoutGuideCustomer
extends "res://script/actor/customer.gd"

var guide_register
var guide_item_id: String = ""

func _ready() -> void:
	choose_customer_type()
	rumor_checked = true
	super._ready()
	var label := Label.new()
	label.text = "이웃 주민"
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
	pass # 첫 거래는 상품 하나로 연습한다.

func can_be_checked_out_by(actor: Node) -> bool:
	return actor == player

func complete_checkout_by_player() -> void:
	checkout_item() # 작별 대화가 끝나면 튜토리얼 감독이 퇴장시킨다.

