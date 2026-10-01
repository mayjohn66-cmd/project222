class_name VillageSmithyDirector
extends CommunityBoardDirector

func create_panel() -> CommunityBoardPanel: return VillageSmithyPanel.new()
func modal_key() -> String: return "village_smithy_open"

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0.0
	if not VillageSmithyFlow.available(): return
	var smithy := VillageSettlement.find_site(get_parent(), VillageSmithyFlow.SITE)
	if smithy == null or not smithy.visible or smithy.has_node("SmithyHint"): return
	var hint := Label.new()
	hint.name = "SmithyHint"
	hint.text = "장비 제작 [E]"
	hint.position = Vector2(-90, -180)
	hint.size = Vector2(180,32)
	hint.z_index = 50
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size",18)
	hint.add_theme_color_override("font_color",Color("fff0d0"))
	hint.add_theme_color_override("font_outline_color",Color("302415"))
	hint.add_theme_constant_override("outline_size",4)
	smithy.add_child(hint)

func near_board() -> bool:
	return VillageSmithyFlow.available() and can_open_at(VillageSmithyFlow.SITE, VillageSmithyFlow.INTERACTION_DISTANCE)

func interaction_hint() -> String:
	return "[E] 도윤의 대장간에서 장비 제작" if near_board() else ""

func _on_action(id: String) -> void:
	if not open: return
	var result := VillageSmithyFlow.craft(id)
	panel.message.text = VillageSmithyFlow.blocked_reason(id) if result.is_empty() else "제작 완료: %s ×%d를 창고에 받았습니다. 원정 준비 화면에서 가방으로 옮겨 주세요." % [ItemData.get_item_name(result["item"]), result["amount"]]
	panel.refresh()
