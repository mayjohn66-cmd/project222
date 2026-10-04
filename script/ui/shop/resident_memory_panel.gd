class_name ResidentMemoryPanel
extends CommunityBoardPanel

var event_id := ""

func panel_title() -> String: return "이웃에게 전할 마음"
func introduction() -> String: return "마음에 가까운 답을 골라 보세요. 어떤 답을 골라도 답례는 같습니다."
func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in ResidentMemoryFlow.SETTINGS.events:
		for choice in entry["choices"]:
			result.append({"id":str(choice["id"]), "title":RequestTextData.text("service_text", str(choice["id"]), "title")})
	return result
func refresh() -> void:
	count_label.text = ResidentMemoryFlow.title(event_id)
	for id in cards:
		var card: Dictionary = cards[id]
		var belongs := not ResidentMemoryFlow.choice(event_id, str(id)).is_empty()
		card["info"].get_parent().visible = belongs
		if not belongs: continue
		card["info"].text = RequestTextData.text("service_text", str(id), "summary")
		card["action"].text = "이 마음 전하기"
		card["action"].disabled = not ResidentMemoryFlow.accepted(event_id) or ResidentMemoryFlow.completed(event_id) or not ResidentMemoryFlow.chosen(event_id).is_empty() or not ResidentMemoryFlow.locked_reason(ResidentMemoryFlow.event(event_id)).is_empty()
