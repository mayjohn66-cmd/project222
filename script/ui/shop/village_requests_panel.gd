class_name VillageRequestsPanel
extends CommunityBoardPanel

func entries() -> Array[Dictionary]:
	var result := super.entries()
	for entry in PersonalRequestFlow.entries():
		var card: Dictionary = entry.duplicate(true)
		card["id"] = "personal:" + str(entry["id"])
		result.append(card)
	for event in VillageExpansionFlow.SETTINGS.events:
		result.append({"id":VillageExpansionFlow.JOURNAL_PREFIX + str(event["id"]),"title":VillageExpansionFlow.title(str(event["id"]))})
	for event in ActFourFlow.SETTINGS.events:
		result.append({"id":ActFourFlow.JOURNAL_PREFIX + str(event["id"]),"title":ActFourFlow.title(str(event["id"]))})
	return result

func refresh() -> void:
	super.refresh()
	for entry in ActFourFlow.SETTINGS.events:
		var id := str(entry["id"])
		var card: Dictionary = cards[ActFourFlow.JOURNAL_PREFIX + id]
		card["info"].get_parent().visible = ActFourFlow.started()
		card["info"].text = ActFourFlow.information(id) if ActFourFlow.started() else ""
		var reason := ActFourFlow.locked_reason(id)
		card["action"].disabled = ActFourFlow.accepted(id) or not reason.is_empty()
		card["action"].text = ResidentFollowthroughGuide.story_button(ActFourFlow.accepted(id),ActFourFlow.done(id),not str(entry.get("repeat","")).is_empty(),reason,"이야기 이어 듣기 [E]")
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

	for entry in VillageExpansionFlow.SETTINGS.events:
		var id := str(entry["id"])
		var card: Dictionary = cards[VillageExpansionFlow.JOURNAL_PREFIX + id]
		card["info"].text = VillageExpansionFlow.information(id)
		card["action"].disabled = VillageExpansionFlow.accepted(id) or not VillageExpansionFlow.locked_reason(id).is_empty()
		card["action"].text = ResidentFollowthroughGuide.story_button(VillageExpansionFlow.accepted(id),VillageExpansionFlow.done(id),not str(entry.get("repeat","")).is_empty(),VillageExpansionFlow.locked_reason(id),"주민에게 이어서 듣기 [E]")
