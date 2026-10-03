class_name LanternWayfarerPanel
extends CommunityBoardPanel

func panel_title() -> String: return LanternWayfarerFlow.title()
func introduction() -> String: return "창고 물품 중 한 가지만 건넵니다. 준비가 안 됐다면 나중에 다시 와도 괜찮아요."

func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for choice in LanternWayfarerFlow.SETTINGS.choices:
		var id := str(choice["id"])
		result.append({"id":id, "title":RequestTextData.text("service_text", "lantern_wayfarer_" + id, "title", ItemData.get_item_name(str(choice["item"])))})
	return result

func refresh() -> void:
	count_label.text = "물 또는 빵 · 한 가지 선택"
	for choice in LanternWayfarerFlow.SETTINGS.choices:
		var id := str(choice["id"])
		var item := str(choice["item"])
		var card: Dictionary = cards[id]
		card["info"].text = "창고의 %s %d/%d" % [ItemData.get_item_name(item), GameState.get_item_count(item), int(choice["amount"])]
		card["action"].text = "건네기" if LanternWayfarerFlow.can_help(id) else "창고에 준비해 주세요"
		card["action"].disabled = not LanternWayfarerFlow.can_help(id)
