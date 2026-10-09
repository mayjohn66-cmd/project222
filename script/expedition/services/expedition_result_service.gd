extends RefCounted


func build_result_text(
	expedition_bag,
	day_name: String
) -> String:
	if expedition_bag == null:
		return "원정 가방을 확인할 수 없습니다."

	var deposit_totals: Dictionary = {}
	var retained_totals: Dictionary = {}

	for placement in expedition_bag.placements:
		var item_id: String = str(
			placement.get("item_id", "")
		)

		var amount: int = int(
			placement.get("amount", 0)
		)

		if item_id.is_empty() or amount <= 0:
			continue

		var target_totals: Dictionary

		if ItemData.should_deposit_after_expedition(
			item_id
		):
			target_totals = deposit_totals
		else:
			target_totals = retained_totals

		target_totals[item_id] = (
			int(target_totals.get(item_id, 0))
			+ amount
		)

	var result_text: String = (
		day_name + " 원정 결과"
	)

	result_text += (
		"\n\n[자동 보관할 아이템]\n"
	)

	result_text += _build_item_lines(
		deposit_totals
	)

	result_text += (
		"\n[가방에 유지할 아이템]\n"
	)

	result_text += _build_item_lines(
		retained_totals
	)

	result_text += (
		"\n확인하면 자동 보관 아이템이"
		+ " 보유 인벤토리로 이동합니다."
	)

	return result_text


func deposit_items(
	expedition_bag,
	context: Dictionary = {}
) -> Dictionary:
	if expedition_bag == null:
		return _failure(
			"원정 가방을 찾지 못했습니다."
		)

	if not ExpeditionFoodBatches.valid_entries(expedition_bag.placements,GameState.total_day):
		return _failure("가방의 식품 기한 기록을 확인할 수 없습니다.")
	var targets: Array[Dictionary] = []
	var checked_uids: Array[int] = []

	# 자동 보관 여부와 관계없이 모든 배치를 먼저 검사
	for placement in expedition_bag.placements:
		var item_id: String = str(
			placement.get("item_id", "")
		)

		var uid: int = int(
			placement.get("uid", -1)
		)

		var amount: int = int(
			placement.get("amount", 0)
		)

		if not ItemData.has_item(item_id):
			return _failure(
				"등록되지 않은 가방 아이템: "
				+ item_id
			)

		if uid < 0 or amount <= 0:
			return _failure(
				"잘못된 가방 배치 데이터: "
				+ str(placement)
			)

		if checked_uids.has(uid):
			return _failure(
				"중복된 가방 UID: "
				+ str(uid)
			)

		checked_uids.append(uid)

		# 전체 배치를 검사하되 이동 대상만 따로 수집
		if not ItemData.should_deposit_after_expedition(
			item_id
		):
			continue

		targets.append(
			{
				"uid": uid,
				"item_id": item_id,
				"amount": amount
			}
		)

	FoodShelfLife.settle()
	ExpeditionFoodBatches.settle_bag(expedition_bag)
	# Expired lots are no longer deposit targets; use the remaining actual counts.
	targets.clear()
	for placement in expedition_bag.placements:
		if ItemData.should_deposit_after_expedition(str(placement["item_id"])):
			targets.append({"uid":int(placement["uid"]),"item_id":str(placement["item_id"]),"amount":int(placement["amount"])})

	var deposited_amount: int = 0

	# 검사가 끝난 아이템만 실제로 이동한다.
	for target in targets:
		var uid: int = int(
			target["uid"]
		)

		var removed: Dictionary = (
			expedition_bag.remove_item(uid)
		)

		if removed.is_empty():
			return _failure(
				"가방에서 아이템을 꺼내지 못했습니다: "
				+ str(uid)
			)

		var item_id: String = str(
			removed["item_id"]
		)

		var amount: int = int(
			removed["amount"]
		)

		GameState.add_item(
			item_id,
			amount,
			ExpeditionFoodBatches.batches(removed)
		)

		BlacksmithProgressionRecords.deposited(context, removed)
		deposited_amount += amount

		DebugLog.write(
			"[원정 정산] 자동 보관 / ",
			item_id,
			" ×",
			amount
		)

	ActFourRecords.record_settlement(context,targets)
	BlacksmithProgressionRecords.returned(context)
	return {
		"success": true,
		"message": "",
		"deposited_amount": deposited_amount
	}


func _build_item_lines(
	totals: Dictionary
) -> String:
	if totals.is_empty():
		return "없음\n"

	var text: String = ""

	for raw_item_id in totals.keys():
		var item_id: String = str(
			raw_item_id
		)

		text += "%s ×%d\n" % [
			ItemData.get_item_name(item_id),
			int(totals[item_id])
		]

	return text


func _failure(
	message: String
) -> Dictionary:
	push_error(
		"[원정 정산] " + message
	)

	return {
		"success": false,
		"message": message,
		"deposited_amount": 0
	}
