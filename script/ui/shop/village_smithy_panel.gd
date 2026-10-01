class_name VillageSmithyPanel
extends CommunityBoardPanel

func entries() -> Array[Dictionary]: return VillageSmithyFlow.recipes()
func panel_title() -> String: return RequestTextData.text("service_text", "smithy_panel", "title", "장비 제작")
func introduction() -> String: return RequestTextData.text("service_text", "smithy_panel", "summary")

func refresh() -> void:
	count_label.text = "도윤의 대장간 · " + VillageLifeFlow.friendship_name("doyun")
	for entry in entries():
		var id := str(entry["id"])
		var card: Dictionary = cards[id]
		var text := "완성품: %s ×%d\n필요 재료: " % [entry["title"], entry["result_amount"]]
		var materials: Array[String] = []
		for material in entry["materials"]:
			materials.append("%s %d/%d" % [ItemData.get_item_name(material["item_id"]), GameState.get_item_count(material["item_id"]), material["amount"]])
		text += " · ".join(materials)
		var reason := VillageSmithyFlow.blocked_reason(id)
		if not reason.is_empty(): text += "\n" + reason
		card["info"].text = text
		card["action"].text = "제작하기" if reason.is_empty() else "제작 준비 중"
		card["action"].disabled = not reason.is_empty()
