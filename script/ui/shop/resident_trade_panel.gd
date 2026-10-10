class_name ResidentTradePanel
extends CommunityBoardPanel

func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if ResidentMerchantSupply.ENABLED:
		for item in ResidentMerchantSupply.items():
			result.append({"id":ResidentMerchantSupply.ACTION_PREFIX + item, "title":ItemData.get_item_name(item) + " · 도구 구매"})
	result.append_array(RequestTextData.enrich_all(ResidentTradeFlow.SETTINGS.offers, "trade_offer"))
	return result
func panel_title() -> String: return "타블렌의 노점 · 도구와 재료" if ResidentMerchantSupply.ENABLED else RequestTextData.text("service_text", "trade_panel", "title", "재료 교환")
func introduction() -> String: return UiText.t("service.trade.intro")

func refresh() -> void:
	count_label.text = str(VillageLifeFlow.resident("naru")["name"]) + " · " + VillageLifeFlow.friendship_name("naru") + " · 보유금 %d G" % GameState.get_money()
	for entry in entries():
		var id := str(entry["id"])
		var card: Dictionary = cards[id]
		if id.begins_with(ResidentMerchantSupply.ACTION_PREFIX):
			var item := id.trim_prefix(ResidentMerchantSupply.ACTION_PREFIX)
			var reason := ResidentMerchantSupply.blocked_reason(item)
			var effect := "물가에서 물을 채집하는 도구" if ExpeditionEquipmentData.get_effect_id(item) == "collect_water" else "밀 채집을 돕는 도구"
			card["info"].text = "%s · %d G\n보유 장비로 받은 뒤 원정 가방에 넣으세요." % [effect, ExpeditionShopData.get_price(item)]
			if not reason.is_empty(): card["info"].text += "\n" + reason
			card["action"].text = "도구 구매 · %d G" % ExpeditionShopData.get_price(item)
			card["action"].disabled = not reason.is_empty()
			continue
		var text := UiText.f("service.trade.stock", [ItemData.get_item_name(entry["give"]), entry["give_amount"], ItemData.get_item_name(entry["receive"]), entry["receive_amount"], ItemData.get_item_name(entry["give"]), GameState.get_item_count(entry["give"]), ResidentTradeFlow.remaining(id)])
		var reason := ResidentTradeFlow.blocked_reason(id)
		if not reason.is_empty(): text += "\n" + reason
		var supply := NpcServiceSupplyGuide.missing(self, {str(entry["give"]):int(entry["give_amount"])})
		if not supply.is_empty(): text += "\n" + supply
		card["info"].text = text
		card["action"].text = "교환하기" if reason.is_empty() else "교환 대기"
		card["action"].disabled = not reason.is_empty()
