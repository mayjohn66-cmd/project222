class_name ArrivalBarterPanel
extends CommunityBoardPanel

func entries() -> Array[Dictionary]:
	return [{"id":"arrival_barter", "title":"식품과 여행 장비 교환"}]

func panel_title() -> String: return "타블렌의 물물교환"
func introduction() -> String: return "창고의 식품을 건넵니다. 진열한 식품은 먼저 창고로 돌려놓으세요."

func refresh() -> void:
	count_label.text = "돈을 쓰지 않는 첫 거래 · 한 번만 교환"
	var text := "건넬 물품 (창고 재고)\n"
	for item in OpeningJourneyFlow.SETTINGS.barter_requirements:
		text += "%s %d / %d\n" % [ItemData.get_item_name(str(item["id"])), GameState.get_item_count(str(item["id"])), item["amount"]]
	text += "\n받을 물품\n"
	for gift in OpeningJourneyFlow.SETTINGS.barter_gifts:
		text += "%s ×%d\n" % [ItemData.get_item_name(str(gift["id"])), gift["amount"]]
	var card: Dictionary = cards["arrival_barter"]
	card["info"].text = text
	card["action"].disabled = not OpeningJourneyFlow.can_trade()
	card["action"].text = "교환 완료" if OpeningJourneyFlow.traded() else "식품을 건네고 장비 받기"
