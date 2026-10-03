class_name VillageMarketPanel
extends CommunityBoardPanel

func panel_title() -> String: return VillageMarketFlow.title()
func introduction() -> String: return " ".join(RequestTextData.lines("service_text", "first_market_preparation"))
func entries() -> Array[Dictionary]: return [{"id":"prepare", "title":"장터에 놓을 먹거리"}]
func refresh() -> void:
	count_label.text = "다음 낮의 첫 장터 준비"
	var card: Dictionary = cards["prepare"]
	card["info"].text = RequestTextData.text("service_text", "first_market_preparation", "summary") + "\n" + VillageMarketFlow.information()
	card["action"].text = "준비 물품 전달하기" if VillageMarketFlow.can_prepare() else "물품을 준비하는 중"
	card["action"].disabled = not VillageMarketFlow.can_prepare()
