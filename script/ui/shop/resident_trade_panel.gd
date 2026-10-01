class_name ResidentTradePanel
extends CommunityBoardPanel

func entries() -> Array[Dictionary]: return ResidentTradeFlow.SETTINGS.offers
func panel_title() -> String: return ResidentTradeFlow.SETTINGS.title
func introduction() -> String: return ResidentTradeFlow.SETTINGS.introduction

func refresh() -> void:
	count_label.text = "행상인 나루 · " + VillageLifeFlow.friendship_name("naru")
	for entry in entries():
		var id := str(entry["id"])
		var card: Dictionary = cards[id]
		var text := "%s ×%d → %s ×%d\n창고에 %s %d개 · 오늘 남은 교환 %d회" % [ItemData.get_item_name(entry["give"]), entry["give_amount"], ItemData.get_item_name(entry["receive"]), entry["receive_amount"], ItemData.get_item_name(entry["give"]), GameState.get_item_count(entry["give"]), ResidentTradeFlow.remaining(id)]
		var reason := ResidentTradeFlow.blocked_reason(id)
		if not reason.is_empty(): text += "\n" + reason
		card["info"].text = text
		card["action"].text = "교환하기" if reason.is_empty() else "교환 대기"
		card["action"].disabled = not reason.is_empty()
