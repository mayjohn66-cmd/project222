class_name RegularCustomerVisits
extends RefCounted

# Reserve one representative regular for this occupation before the pedestrian appears.
# Ordinary visitors of the same type do not advance this named story without the tag.
static func prepare(customer: Node, introduced_type: String = "") -> bool:
	var tree := customer.get_tree()
	var stocked := ShopStock.get_stocked_item_ids(tree)
	var active: Array[String] = []
	for other in tree.get_nodes_in_group("regular_customer"):
		if other != customer and not other.is_queued_for_deletion(): active.append(str(other.get_meta("regular_story_id","")))
	var chosen: Dictionary = {}
	var stage := ""
	for entry in RegularCustomerFlow.SETTINGS.events:
		# Returning regulars never replace a different resident's first introduction.
		if not introduced_type.is_empty(): break
		var id := str(entry["id"])
		if active.has(id) or RegularCustomerFlow.phase(id) != "repeat_purchase": continue
		if stocked.has(str(entry["purchase_item"])) and stock_count(tree,str(entry["purchase_item"])) >= int(entry["repeat_amount"]):
			chosen = entry
			stage = "repeat"
			break
	if chosen.is_empty():
		for entry in RegularCustomerFlow.SETTINGS.events:
			if not introduced_type.is_empty() and introduced_type != str(entry["type"]): continue
			var id := str(entry["id"])
			if active.has(id) or customer.get_customer_type_id() != str(entry["type"]) or RegularCustomerFlow.phase(id) != "first_purchase": continue
			if stocked.has(str(entry["purchase_item"])):
				chosen = entry
				stage = "first"
				break
	if chosen.is_empty(): return false
	customer.customer_type_id = str(chosen["type"])
	customer.customer_group_id = CustomerTypeData.get_group_id(customer.customer_type_id)
	customer.set_meta("regular_story_id",str(chosen["id"]))
	customer.set_meta("regular_story_purchase",stage)
	customer.set_meta("regular_story_item",str(chosen["purchase_item"]))
	customer.set_meta("regular_story_amount",int(chosen["repeat_amount"]) if stage == "repeat" else 1)
	customer.add_to_group("regular_customer")
	var label := Label.new()
	label.name = "RegularCustomerName"
	label.text = "단골 · " + CustomerTypeData.get_display_name(customer.customer_type_id)
	label.position = Vector2(-120,-104)
	label.size.x = 240
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",Color("fff0d0"))
	label.add_theme_color_override("font_outline_color",Color("302415"))
	label.add_theme_constant_override("outline_size",4)
	customer.add_child(label)
	return true
static func stock_count(tree: SceneTree, item: String) -> int:
	var amount := 0
	for shelf in tree.get_nodes_in_group("shelf"):
		if not shelf.is_queued_for_deletion() and not shelf.get_meta("is_build_preview",false): amount += shelf.get_item_stock(item)
	return amount
static func remark(customer: Node) -> void:
	var id := str(customer.get_meta("regular_story_id",""))
	var stage := str(customer.get_meta("regular_story_purchase",""))
	var text := RequestTextData.text("service_text",id + "_" + stage + "_sale","lines")
	if text.is_empty() or not is_instance_valid(customer.player): return
	var notice = customer.player.get_node_or_null("StoreEventRemark")
	if notice == null:
		notice = StoreEventRemark.new()
		notice.name = "StoreEventRemark"
		customer.player.add_child(notice)
	notice.display(text)
