class_name ExpeditionSupplyAccess
extends Node
## 기존 원정 상점을 준비 화면에 연결한다. 구매/가격/개별 장비 생성은 PrepShop이 담당한다.
const ENABLED := false # 도구는 타블렌의 노점에서 구매한다. 익명 원정 상점은 비활성화.
var prep: Control
var shop: Control
var entry: Button
var close_button: Button
var balance: Label
var detail_scroll: ScrollContainer
var layer: CanvasLayer
var scrim: ColorRect

static func install(target: Control) -> void:
	if not ENABLED: return
	var access := ExpeditionSupplyAccess.new()
	access.name = "SupplyAccess"
	access.prep = target
	target.add_child(access)

func _ready() -> void:
	shop = prep.get_node("ShopContent")
	shop.hide()
	entry = Button.new()
	entry.name = "SupplyButton"
	entry.text = "원정 상점"
	prep.add_child(entry)
	entry.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	entry.offset_left = 24
	entry.offset_top = 90
	entry.offset_right = 198
	entry.offset_bottom = 132
	entry.theme = preload("res://art/ui/pixel_theme/pixel_ui_theme.tres")
	entry.pressed.connect(open_shop)
	entry.tooltip_text = "채집용 물병과 낫 등 원정 장비를 구매합니다."
	shop.theme = preload("res://art/ui/pixel_theme/pixel_ui_theme.tres")
	for tab in [shop.weapon_button, shop.armor_button, shop.tool_button, shop.etc_button]:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			tab.add_theme_color_override(state, Color("3d2b20"))
	_style_panel(shop)
	var body: HBoxContainer = shop.get_node("ShopHBox")
	body.custom_minimum_size = Vector2.ZERO
	body.get_node("ShopNpcPanel").hide()
	var column: VBoxContainer = body.get_node("ShopItemArea")
	column.custom_minimum_size = Vector2.ZERO
	column.add_theme_constant_override("separation", 12)
	balance = Label.new()
	balance.add_theme_font_size_override("font_size", 22)
	column.add_child(balance)
	column.move_child(balance, 0)
	var hint := Label.new()
	hint.text = "구매한 도구는 보유 장비에 들어갑니다. 가방에 넣고 출발하세요."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 17)
	column.add_child(hint)
	column.move_child(hint, 1)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	column.move_child(scroll, 3)
	shop.shop_item_list.reparent(scroll)
	shop.shop_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button = Button.new()
	close_button.text = "원정 준비로 돌아가기"
	close_button.custom_minimum_size.y = 42
	column.add_child(close_button)
	close_button.pressed.connect(close_shop)
	shop.detail_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail: PanelContainer = shop.get_node("ShopDetailOverlay/CenterContainer/DetailPanel")
	_style_panel(detail)
	var info: VBoxContainer = detail.get_node("VBoxContainer")
	var buttons: HBoxContainer = info.get_node("ButtonRow")
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	detail.add_child(outer)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(detail_scroll)
	info.reparent(detail_scroll)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.reparent(outer)
	shop.purchase_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop.buy_button.pressed.connect(_purchase_finished)
	layer = CanvasLayer.new()
	layer.name = "SupplyLayer"
	layer.layer = 25
	prep.add_child(layer)
	scrim = ColorRect.new()
	scrim.name = "SupplyScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.03, 0.03, 0.03, 0.82)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(scrim)
	shop.reparent(layer)
	scrim.hide()
	prep.resized.connect(_layout)
	prep.visibility_changed.connect(_visibility_changed)
	_layout()
	_refresh_entry()

func _style_panel(panel: Control) -> void:
	var style := StyleBoxTexture.new()
	style.texture = preload("res://art/ui/pixel_theme/panel.png")
	style.texture_margin_left = 12
	style.texture_margin_right = 12
	style.texture_margin_top = 12
	style.texture_margin_bottom = 12
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_content_margin(side, 18)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_color_override("font_color", Color("3d2b20"))

func _layout() -> void:
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop.anchor_left = 0.12
	shop.anchor_right = 0.88
	shop.anchor_top = 0.10
	shop.anchor_bottom = 0.90
	shop.offset_left = 0
	shop.offset_right = 0
	shop.offset_top = 0
	shop.offset_bottom = 0
	detail_scroll.custom_minimum_size.y = minf(360, maxf(120, prep.size.y - 150))
	var detail: Control = shop.get_node("ShopDetailOverlay/CenterContainer/DetailPanel")
	detail.custom_minimum_size = Vector2(minf(480, maxf(280, prep.size.x - 120)), 0)

func available() -> bool:
	return ENABLED and (OpeningJourneyFlow.traded() or OpeningJourneyFlow.core_finished())

func _process(_delta: float) -> void:
	_refresh_entry()
	if shop.visible: balance.text = "원정 상점 · 보유금 %d G" % GameState.get_money()

func _refresh_entry() -> void:
	entry.visible = available() and not shop.visible

func open_shop() -> void:
	if not available() or not prep.is_visible_in_tree(): return
	if prep.transition_tween and prep.transition_tween.is_running(): prep.transition_tween.kill()
	prep.bag_content.hide()
	prep.bag_scrim.hide()
	prep.region_info_card.hide()
	prep.start_button.hide()
	prep.map_content.set_map_overlays_visible(false)
	shop.refresh_all()
	shop._show_category(ExpeditionShopData.CATEGORY_TOOL)
	scrim.show()
	shop.show()
	_refresh_entry()
	balance.text = "원정 상점 · 보유금 %d G" % GameState.get_money()
	shop.tool_button.grab_focus()

func close_shop() -> void:
	shop.refresh_all()
	shop.hide()
	scrim.hide()
	prep.select_tab(prep.current_tab)
	_refresh_entry()
	entry.grab_focus()

func _purchase_finished() -> void:
	# 구매 콜백 뒤에 목록의 '보유 중'도 갱신한다. 상세창의 결과 문구는 유지한다.
	if shop.selected_item_id.is_empty(): return
	var category := str(ExpeditionShopData.get_entry(shop.selected_item_id).get("shop_category", "tool"))
	shop._show_category(category)

func _visibility_changed() -> void:
	if not prep.visible:
		shop.refresh_all()
		shop.hide()
		scrim.hide()

func _input(event: InputEvent) -> void:
	if not shop.is_visible_in_tree() or not event.is_action_pressed("ui_cancel"): return
	if shop.detail_overlay.visible: shop._close_detail_popup()
	else: close_shop()
	get_viewport().set_input_as_handled()
