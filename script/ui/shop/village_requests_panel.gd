class_name VillageRequestsPanel
extends CommunityBoardPanel

func entries() -> Array[Dictionary]:
	var result := super.entries()
	for entry in PersonalRequestFlow.entries():
		var card: Dictionary = entry.duplicate(true)
		card["id"] = "personal:" + str(entry["id"])
		result.append(card)
	return result

func refresh() -> void:
	super.refresh()
	# The base panel handles the existing community cards only.
	for entry in PersonalRequestFlow.entries():
		var id := str(entry["id"])
		var card: Dictionary = cards["personal:" + id]
		card["info"].text = PersonalRequestFlow.information(entry)
		var reason := PersonalRequestFlow.locked_reason(entry)
		card["action"].disabled = PersonalRequestFlow.done(id) or not reason.is_empty() or (PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.can_deliver(id))
		if PersonalRequestFlow.done(id): card["action"].text = "함께 완료한 부탁"
		elif not reason.is_empty(): card["action"].text = "아직 준비 중"
		elif PersonalRequestFlow.accepted(id): card["action"].text = "물품 전달하기" if PersonalRequestFlow.can_deliver(id) else "물품을 준비하는 중"
		else: card["action"].text = "개인 부탁 맡기"
