class_name ResidentTradeDirector
extends CommunityBoardDirector

func create_panel() -> CommunityBoardPanel: return ResidentTradePanel.new()
func modal_key() -> String: return "resident_trade_open"
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0.0
	if not ResidentTradeFlow.available(): return
	var stall := VillageSettlement.find_site(get_parent(), ResidentTradeFlow.SETTINGS.site)
	if stall == null or not stall.visible or stall.has_node("TradeHint"): return
	var hint := Label.new()
	hint.name = "TradeHint"
	hint.text = "도구 구매 · 재료 교환 [E]"
	hint.position = Vector2(-90,-230)
	hint.size = Vector2(180,32)
	hint.z_index = 50
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size",18)
	hint.add_theme_color_override("font_color",Color("fff0d0"))
	hint.add_theme_color_override("font_outline_color",Color("302415"))
	hint.add_theme_constant_override("outline_size",4)
	stall.add_child(hint)

func near_board() -> bool:
	return ResidentTradeFlow.available() and can_open_at(ResidentTradeFlow.SETTINGS.site, ResidentTradeFlow.SETTINGS.interaction_distance)

func interaction_hint() -> String:
	return "[E] %s의 노점에서 도구 구매 · 재료 교환" % VillageLifeFlow.resident("naru")["name"] if near_board() else ""

func _on_action(id: String) -> void:
	if not open: return
	if id.begins_with(ResidentMerchantSupply.ACTION_PREFIX):
		var item := id.trim_prefix(ResidentMerchantSupply.ACTION_PREFIX)
		var purchase := ResidentMerchantSupply.buy(item)
		panel.message.text = ResidentMerchantSupply.blocked_reason(item) if purchase.is_empty() else "%s 구매 완료. 원정 준비의 보유 장비에서 가방에 넣으세요." % ItemData.get_item_name(item)
		panel.refresh()
		return
	var result := ResidentTradeFlow.exchange(id)
	panel.message.text = ResidentTradeFlow.blocked_reason(id) if result.is_empty() else UiText.f("service.trade.done", [ItemData.get_item_name(result["item"]), result["amount"]])
	panel.refresh()
