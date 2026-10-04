class_name ExpeditionContactVisits
extends RefCounted

static func prepare(customer: Node, introduced_type: String = "") -> bool:
	if not introduced_type.is_empty(): return false
	var tree := customer.get_tree()
	for entry in ExpeditionContactFlow.SETTINGS.events:
		var id := str(entry["id"])
		if ExpeditionContactFlow.phase(id) != "visit": continue
		if tree.get_nodes_in_group("expedition_contact_customer").any(func(other: Node) -> bool: return not other.is_queued_for_deletion() and str(other.get_meta("expedition_contact_id","")) == id): continue
		if RegularCustomerVisits.stock_count(tree,str(entry["purchase_item"])) < int(entry["purchase_amount"]): continue
		customer.customer_type_id = str(entry["type"])
		customer.customer_group_id = CustomerTypeData.get_group_id(customer.customer_type_id)
		customer.set_meta("expedition_contact_id",id)
		customer.set_meta("regular_story_item",str(entry["purchase_item"]))
		customer.set_meta("regular_story_amount",int(entry["purchase_amount"]))
		customer.add_to_group("expedition_contact_customer")
		RegularCustomerVisits.show_label(customer,"원정에서 만난 " + CustomerTypeData.get_display_name(customer.customer_type_id))
		return true
	return false

static func remark(customer: Node) -> void:
	var text := RequestTextData.text("service_text",str(customer.get_meta("expedition_contact_id","")) + "_bought","lines")
	RegularCustomerVisits.display_remark(customer,text)
