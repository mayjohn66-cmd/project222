class_name VillageStoryPanel
extends CommunityBoardPanel

func panel_title() -> String: return VillageStoryFlow.title()
func introduction() -> String: return "남길 기억을 고르세요. 답례는 같고 기한은 없습니다."

func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for choice in VillageStoryFlow.SETTINGS.choices:
		var id := str(choice["id"])
		result.append({"id":id, "title":RequestTextData.text("service_text", "village_story_" + id, "title")})
	return result

func refresh() -> void:
	count_label.text = "남길 기억 선택 · 한 가지"
	for choice in VillageStoryFlow.SETTINGS.choices:
		var id := str(choice["id"])
		var card: Dictionary = cards[id]
		card["info"].text = RequestTextData.text("service_text", "village_story_" + id, "summary")
		card["action"].text = "이 이야기를 남기기"
		card["action"].disabled = not VillageStoryFlow.ready() or not VillageStoryFlow.chosen().is_empty()
