class_name ActFourVisits
extends RefCounted
static func prepare(customer: Node, introduced_type: String) -> bool:
	if not introduced_type.is_empty() or not ActFourFlow.started(): return false
	var current := ActFourFlow.step("a2_far_caravan")
	if current.get("sales",[]).is_empty(): return false
	if int(PlayerProgress.story_beat_days.get("act4_record:caravan_day",-1)) == GameState.total_day: return false
	var wanted := ""
	for requirement in current["sales"]:
		if requirement.get("amount") == null: continue
		var item := str(requirement["item"])
		var sold := int(PlayerProgress.story_beat_days.get(ActFourFlow.key("a2_far_caravan","sold:" + item,ActFourFlow.cycle("a2_far_caravan")),0))
		if sold < int(requirement["amount"]) and RegularCustomerVisits.stock_count(customer.get_tree(),item) > 0:
			wanted = item
			break
	if wanted.is_empty(): return false
	customer.set("customer_type_id","road_caravan")
	customer.set("customer_group_id",CustomerTypeData.get_group_id("road_caravan"))
	customer.set_meta("act4_first_caravan",true)
	customer.set_meta("regular_story_item",wanted)
	customer.set_meta("regular_story_amount",1)
	RegularCustomerVisits.show_label(customer,"먼 곳의 상단")
	PlayerProgress.record_story_beat("act4_record:caravan_day",GameState.total_day)
	return true
