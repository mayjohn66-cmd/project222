class_name ShopOfflineSimulator
extends RefCounted


# 플레이어가 원정을 나가 있던 시간 동안 상점을 시간 단위로 계산한다(규칙서 2.3).
# 실제 손님 캐릭터를 만들지 않고, 도착률 → 손님 유형 → 원하는 품목 → 진열대 재고 순으로 결과만 낸다.
#   - 시간당 도착 손님 수는 시각별 도착률(CustomerArrivalData)의 기대값에 누적 오차를 이월해 정수로 만든다.
#   - 그 시각에 근무 중인 고용 직원이 없으면 손님은 놓친 손님이다(방문·판매로 세지 않음).
#   - 근무자가 있으면 손님 유형을 뽑고 원하는 품목을 진열대에서 꺼내 판매하고, 재고가 없으면 판매 실패다.
# 결과는 플레이어의 하루 통계와 돈에 그대로 반영한다.


# hours: 계산할 게임 시간(소수 가능). 반환: 요약 Dictionary.
static func simulate(
	tree: SceneTree,
	player: Node,
	start_hour: int,
	hours: float
) -> Dictionary:
	var result: Dictionary = {
		"arrivals": 0,
		"unstaffed_missed": 0,
		"visitors": 0,
		"sales": 0,
		"missed_sales": 0,
		"revenue": 0
	}

	if hours <= 0.0 or not is_instance_valid(player):
		return result

	var decoration_bonuses: Dictionary = _get_decoration_bonuses(tree)
	var remaining: float = hours
	var hour: int = posmod(start_hour, 24)
	var carry: float = 0.0

	while remaining > 0.0001:
		var slice: float = minf(remaining, 1.0)

		carry += CustomerArrivalData.get_rate(hour) * slice * (1.0 + DecorationEffectService.get_reputation_visit_bonus(ResidentRequestFlow.reputation()))

		var arrivals: int = int(floor(carry))
		carry -= float(arrivals)

		for _i in range(arrivals):
			result["arrivals"] = int(result["arrivals"]) + 1
			_process_customer(
				tree,
				player,
				hour,
				decoration_bonuses,
				result
			)

		remaining -= slice
		hour = (hour + 1) % 24

	return result


static func _process_customer(
	tree: SceneTree,
	player: Node,
	hour: int,
	decoration_bonuses: Dictionary,
	result: Dictionary
) -> void:
	# 근무 중인 직원이 없으면 놓친 손님이다.
	if not _has_staff_at_hour(tree, hour):
		result["unstaffed_missed"] = int(result["unstaffed_missed"]) + 1
		return

	var type_data: Dictionary = CustomerTypeData.get_random_customer_type(
		GameState.total_day,
		decoration_bonuses,
		EmployeeData.get_period_at_hour(hour)
	)

	var type_id: String = str(
		type_data.get("customer_type_id", "")
	)

	if type_id.is_empty():
		type_id = "villager"

	player.record_visitor(type_id)
	result["visitors"] = int(result["visitors"]) + 1

	var request: Dictionary = CustomerDemandData.get_random_wanted_request(
		type_id,
		GameState.total_day,
		ShopStock.get_stocked_item_ids(tree)
	)

	var item_id: String = str(request.get("item_id", ""))

	if item_id.is_empty():
		return

	var amount: int = maxi(int(request.get("amount", 1)), 1)
	var taken: int = _take_from_shelves(tree, item_id, amount)

	if taken <= 0:
		player.record_missed_sale(item_id, amount)
		result["missed_sales"] = int(result["missed_sales"]) + 1
		return

	var total_price: int = ItemData.get_item_price(item_id) * taken

	player.add_money(total_price)
	player.record_successful_sale(total_price, item_id, taken)

	result["sales"] = int(result["sales"]) + 1
	result["revenue"] = int(result["revenue"]) + total_price


static func _take_from_shelves(
	tree: SceneTree,
	item_id: String,
	amount: int
) -> int:
	var taken_total: int = 0

	for shelf in tree.get_nodes_in_group("shelf"):
		if taken_total >= amount:
			break

		if not is_instance_valid(shelf):
			continue

		if not shelf.has_method("take_items_by_id"):
			continue

		taken_total += int(
			shelf.call(
				"take_items_by_id",
				item_id,
				amount - taken_total
			)
		)

	return taken_total


static func _has_staff_at_hour(
	tree: SceneTree,
	hour: int
) -> bool:
	for worker in tree.get_nodes_in_group("worker"):
		if not is_instance_valid(worker):
			continue

		if not bool(worker.get("is_hired")):
			continue

		if worker.has_method("is_hour_in_shift") and worker.call(
			"is_hour_in_shift",
			hour
		):
			return true

	return false


static func _get_decoration_bonuses(
	tree: SceneTree
) -> Dictionary:
	var manager: Node = tree.get_first_node_in_group(
		"build_manager"
	)

	if (
		is_instance_valid(manager)
		and manager.has_method("get_customer_weight_bonuses")
	):
		return manager.call("get_customer_weight_bonuses")

	return {}


# 복귀 시 보여 주는 요약 문구.
static func format_summary(
	result: Dictionary,
	hours: float
) -> String:
	var lines: Array[String] = []

	lines.append(
		"자리를 비운 시간: 약 %.1f시간" % hours
	)
	lines.append(
		"방문 손님: %d명" % int(result.get("visitors", 0))
	)
	lines.append(
		"판매: %d건 / 매출 %dG" % [
			int(result.get("sales", 0)),
			int(result.get("revenue", 0))
		]
	)
	lines.append(
		"판매 실패(재고 부족 등): %d건" % int(
			result.get("missed_sales", 0)
		)
	)
	lines.append(
		"놓친 손님(근무자 없음): %d명" % int(
			result.get("unstaffed_missed", 0)
		)
	)

	return "\n".join(lines)
