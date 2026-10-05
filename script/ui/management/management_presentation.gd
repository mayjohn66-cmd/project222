extends RefCounted
const ACCENTS := ["98703e","b06b3d","4b8068","527e9a","97754c","897299","567d86"]
const PAPERS := ["f5eddc","f7eddf","f0f1e3","edf1ec","f4eddf","f3edf2","edf1ef"]
const INDEX_COLORS := ["f2cf5b","ef8fa6","8fcf9a","7bbbe0","eeb06a","b79bdb","7fd0c8"]
# 포스트잇 책갈피: 책 옆면에서 튀어나온 길이를 탭마다 다르게(들쭉날쭉), 선택하면 +SELECTED_EXTRA 만큼 더 나온다. 가장 긴 값이 내비게이션 폭 104 를 넘지 않게 한다.
const FLAG_LENGTHS := [72.0,84.0,76.0,88.0,70.0,86.0,78.0]
const FLAG_HEIGHT := 34.0
const SELECTED_EXTRA := 16.0
const ADHESIVE := 14.0  # 책 옆면에 붙는 부분(반투명하게 보이는 띠) 폭

static func flag_style(color: String) -> StyleBoxFlat:
	var base := Color(color)
	var s := StyleBoxFlat.new()
	s.bg_color = base
	s.border_width_left = int(ADHESIVE)
	s.border_color = base.lerp(Color.WHITE,0.55)  # 붙이는 부분은 연하게(종이가 비쳐 보이는 느낌)
	s.border_width_bottom = 2
	s.shadow_color = Color("30231340")
	s.shadow_size = 0
	s.shadow_offset = Vector2(1,2)
	s.content_margin_left = ADHESIVE+8.0
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

static func box(color: String, padding: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color)
	s.set_content_margin_all(padding)
	return s

static func tab_theme(root: Control, index: int) -> void:
	var t := Theme.new()
	t.default_font = root.get_theme_default_font()
	t.default_font_size = 18
	t.set_color("font_color","Label",Color("44392e"))
	t.set_color("font_color","Button",Color("44392e"))
	t.set_color("font_hover_color","Button",Color("44392e"))
	t.set_color("font_pressed_color","Button",Color("fff7e6"))
	t.set_color("font_hover_pressed_color","Button",Color("fff7e6"))
	t.set_color("font_disabled_color","Button",Color("796f60"))
	t.set_stylebox("panel","PanelContainer",box("fff5df",12))
	t.set_stylebox("panel","Panel",box("fff5df",12))
	t.set_stylebox("normal","Button",box(PAPERS[index],10))
	t.set_stylebox("hover","Button",box("fff8e9",10))
	t.set_stylebox("pressed","Button",box(ACCENTS[index],10))
	t.set_stylebox("hover_pressed","Button",box(ACCENTS[index],10))
	t.set_stylebox("disabled","Button",box("dedacb",10))
	var focus := box("ffffff00",0)
	focus.border_color = Color(ACCENTS[index])
	focus.set_border_width_all(2)
	t.set_stylebox("focus","Button",focus)
	root.theme = t

static func inset(control: Control, amount: int = 16) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.offset_left = amount
	control.offset_top = amount
	control.offset_right = -amount
	control.offset_bottom = -amount

static func install(menu: Control) -> void:
	menu.z_index = 1001
	var main: PanelContainer = menu.get_node("DimBackground/CenterContainer/MainPanel")
	main.custom_minimum_size = Vector2(1040,580)
	var cover := box("00000000",18)
	cover.border_color = Color("b58a51")
	cover.set_border_width_all(0)
	cover.shadow_size = 0
	cover.shadow_color = Color("241a16aa")
	main.add_theme_stylebox_override("panel",cover)
	var book := BookViews.Paper.new()
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(book)
	main.move_child(book,0)
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	book.resized.connect(book.queue_redraw)
	var v: VBoxContainer = main.get_node("MainVBox")
	v.add_theme_constant_override("separation",8)
	var header: PanelContainer = v.get_node("Header")
	header.custom_minimum_size.y = 32
	header.add_theme_stylebox_override("panel",box("00000000",0))
	var margin: MarginContainer = header.get_node("HeaderMargin")
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,0)
	var row: HBoxContainer = margin.get_node("HeaderRow")
	row.add_theme_constant_override("separation",6)
	row.get_node("TitleLabel").hide()
	row.get_node("LeafIcon").hide()
	var nav: VBoxContainer = v.get_node("Body/Navigation")
	nav.custom_minimum_size.x = 104
	nav.add_theme_constant_override("separation",9)
	v.get_node("Body").move_child(nav,v.get_node("Body").get_child_count()-1)
	v.get_node("Body").add_theme_constant_override("separation",0)
	var buttons: Array = nav.get_children()
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		b.custom_minimum_size = Vector2(FLAG_LENGTHS[i],FLAG_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size",15)
		for state in ["normal","hover","pressed","hover_pressed"]:
			b.add_theme_stylebox_override(state,flag_style(INDEX_COLORS[i]))
		b.add_theme_color_override("font_color",Color("514333"))
		b.add_theme_color_override("font_pressed_color",Color("493e33"))
		b.add_theme_color_override("font_hover_pressed_color",Color("493e33"))
		b.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	nav.show()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.move_child(spacer,0)
	menu.close_button.custom_minimum_size = Vector2(32,32)
	menu.close_button.add_theme_constant_override("icon_max_width",28)
	row.move_child(menu.close_button,row.get_child_count()-1)
	var index_space := Control.new()
	index_space.custom_minimum_size.x = 104
	row.add_child(index_space)
	var footer: PanelContainer = v.get_node("Footer")
	footer.hide()
	footer.custom_minimum_size.y = 0
	footer.add_theme_stylebox_override("panel",box("00000000",0))
	var fm: MarginContainer = footer.get_node("FooterMargin")
	for side in ["left","right","top","bottom"]: fm.add_theme_constant_override("margin_"+side,0)
	footer.get_node("FooterMargin/FooterRow/CoinIcon").custom_minimum_size = Vector2(20,20)
	for label in [menu.money_label,menu.info_label]:
		label.add_theme_font_size_override("font_size",15)
		label.add_theme_color_override("font_color",Color("67543b"))
	var area: Control = v.get_node("Body/ContentArea")
	var contents := [menu.inventory_content,menu.production_content,menu.employee_content,menu.blueprint_content,menu.construction_content,menu.schedule_content,menu.history_content]
	for i in range(contents.size()):
		tab_theme(contents[i],i)
		inset(contents[i],16)
	area.clip_contents = true
	inset(area.get_node("ContentBackdrop"),16)
	# Flat inner paper, only the outer window keeps the decorative frame.
	menu.production_content.add_theme_stylebox_override("panel",box(PAPERS[1],16))
	for c in [menu.employee_content,menu.blueprint_content,menu.construction_content]:
		inset(c.get_node("MainVBox"))
		c.get_node("MainVBox").add_theme_constant_override("separation",10)
	for c in [menu.employee_content,menu.blueprint_content]: c.get_node("MainVBox/Title").hide()
	menu.construction_content.get_node("MainVBox/TitleLabel").hide()
	for c in [menu.schedule_content,menu.history_content]:
		var m: MarginContainer = c.get_node("MarginContainer")
		for side in ["left","right","top","bottom"]: m.add_theme_constant_override("margin_"+side,16)
	menu.history_content.get_node("MarginContainer/HistoryVBox").add_theme_constant_override("separation",10)
	menu.schedule_content.get_node("MarginContainer/ScheduleVBox").add_theme_constant_override("separation",14)
	menu.schedule_current_date_label.add_theme_font_size_override("font_size",22)
	menu.history_title_label.add_theme_font_size_override("font_size",20)
	var inv = menu.management_inventory
	inv.get_node("MainVBox/ItemScroll").custom_minimum_size.y = 0
	inv.get_node("MainVBox/ItemScroll").horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv.get_node("MainVBox/ItemScroll").resized.connect(fit_inventory.bind(inv))
	fit_inventory.call_deferred(inv)
	fit_inventory(inv)
	var prod = menu.management_production
	prod.get_node("MainHBox").add_theme_constant_override("separation",16)
	prod.get_node("MainHBox/LeftPanel").custom_minimum_size.x = 180
	prod.get_node("MainHBox/LeftPanel/LeftVBox/RecipeScroll/RecipeList").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prod.get_node("MainHBox/RightPanel/DetailVBox").add_theme_constant_override("separation",12)
	prod.get_node("MainHBox/RightPanel/DetailVBox/DescriptionLabel").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bp = menu.blueprint_content
	bp.get_node("MainVBox/Body/LeftPanel").custom_minimum_size.x = 180
	var pattern := PaperPattern.new()
	pattern.name = "TabPaperPattern"
	pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(pattern)
	area.move_child(pattern,1)
	inset(pattern,16)
	pattern.resized.connect(pattern.queue_redraw)
	var cover_view := BookViews.Cover.new()
	cover_view.name = "BookCover"
	cover_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_view.visible = false
	main.add_child(cover_view)
	main.move_child(cover_view,1)
	cover_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var flip := BookViews.Flip.new()
	flip.name = "BookFlip"
	flip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flip.process_mode = Node.PROCESS_MODE_ALWAYS
	flip.visible = false
	main.add_child(flip)
	flip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InventoryDetailPane.install(menu.management_inventory)
	apply_tab(menu)

static func fit_inventory(inv: Control) -> void:
	var scroll: ScrollContainer = inv.get_node("MainVBox/ItemScroll")
	var grid: GridContainer = scroll.get_node("ItemGrid")
	var columns := clampi(floori((scroll.size.x+6)/78),3,6)
	var rows := clampi(floori(scroll.size.y/78),3,6)
	if grid.columns==columns and inv.minimum_display_rows==rows: return
	grid.columns = columns
	inv.default_item_grid_columns = columns
	inv.minimum_display_rows = rows
	inv.refresh_inventory()

static func apply_tab(menu: Control) -> void:
	var area: Control = menu.get_node("DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea")
	area.get_node("ContentBackdrop").add_theme_stylebox_override("panel",box(PAPERS[menu.current_tab],0))
	var nav = area.get_parent().get_node("Navigation")
	for i in range(nav.get_child_count()):
		var button: Button = nav.get_child(i)
		var previous: Tween = button.get_meta("index_slide") if button.has_meta("index_slide") else null
		if previous and previous.is_valid(): previous.kill()
		var slide := button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		slide.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		slide.tween_property(button,"custom_minimum_size:x",FLAG_LENGTHS[i]+(SELECTED_EXTRA if i == menu.current_tab else 0.0),0.18)
		button.set_meta("index_slide",slide)
	var flip = area.get_parent().get_parent().get_parent().get_node_or_null("BookFlip")
	if flip:
		if menu.visible and flip.last_tab >= 0 and flip.last_tab != menu.current_tab and not bool(menu.get_meta("book_opening",false)) and not bool(menu.get_meta("book_closing",false)):
			flip.begin(menu.current_tab > flip.last_tab)
		flip.last_tab = menu.current_tab
	var pattern = area.get_node_or_null("TabPaperPattern")
	if pattern:
		pattern.mode = menu.current_tab
		pattern.queue_redraw()

class PaperPattern extends Control:
	var mode: int = 0
	func _draw() -> void:
		# 가운데 제본 홈(두 쪽 사이): 어느 탭이든 책이 펼쳐진 느낌이 나도록 양쪽으로 번지는 그림자
		var mid := size.x * 0.5
		for i in range(18):
			var a := 0.14 * pow(1.0 - float(i) / 18.0,2.0)
			draw_rect(Rect2(mid - float(i) - 1.0,0,1,size.y),Color(0.33,0.24,0.14,a))
			draw_rect(Rect2(mid + float(i),0,1,size.y),Color(0.33,0.24,0.14,a))
		draw_line(Vector2(mid,0),Vector2(mid,size.y),Color(0.33,0.24,0.14,0.28),2.0)
		if mode==3 or mode==4:
			var color := Color(0.3,0.5,0.6,0.07) if mode==3 else Color(0.5,0.4,0.2,0.06)
			for x in range(0,int(size.x),24): draw_line(Vector2(x,0),Vector2(x,size.y),color)
			for y in range(0,int(size.y),24): draw_line(Vector2(0,y),Vector2(size.x,y),color)
		elif mode==5:
			draw_rect(Rect2(0,0,8,size.y),Color("897299"))

# ---------------------------------------------------------------- 책 여닫기 연출
# 열기: 닫힌 책(세로형 표지 + 옆의 포스트잇)이 화면 아래에서 올라온 뒤, 표지가 가운데 제본선을 축으로 왼쪽으로 넘어가며 펼쳐지고
#       책 전체가 가운데로 옮겨 앉은 다음에야 쪽 안의 UI 가 나타난다.
# 닫기: UI 가 사라지고 표지가 다시 덮인 뒤 책이 아래로 내려간다. 트리가 멈춰 있어도 돌아가도록 PROCESS 모드 트윈을 쓴다.
const BOOK_RISE := 0.34
const BOOK_SWING := 0.62
const BOOK_SINK := 0.24

static func _book_nodes(menu: Control) -> Dictionary:
	var dim: ColorRect = menu.get_node("DimBackground")
	var cc: Control = dim.get_node("CenterContainer")
	var main: Control = cc.get_node("MainPanel")
	return {"dim": dim,"cc": cc,"main": main,"paper": main.get_child(0),"cover": main.get_node("BookCover"),
		"area": main.get_node("MainVBox/Body/ContentArea"),"header": main.get_node("MainVBox/Header")}

static func _kill_book_anim(menu: Control) -> void:
	var old = menu.get_meta("book_anim") if menu.has_meta("book_anim") else null
	if old is Tween and old.is_valid(): old.kill()

static func _book_settle(menu: Control,n: Dictionary,visible_book: bool) -> void:
	n["cc"].position = Vector2.ZERO
	n["dim"].color.a = float(menu.get_meta("dim_alpha",0.85))
	n["area"].modulate.a = 1.0
	n["header"].modulate.a = 1.0
	n["cover"].visible = false
	n["cover"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	n["cover"].angle = 0.0
	n["paper"].set_left_visible(true)
	menu.set_meta("book_opening",false)

# 닫힌 책을 가운데에 놓으려면 펼친 책 기준 위치에서 쪽 폭의 4분의 1만큼 왼쪽으로 옮긴다.
static func _closed_shift(main: Control) -> float:
	return BookViews.page_width(main.size) * 0.25

static func play_open(menu: Control) -> void:
	if DisplayServer.get_name() == "headless": return
	var n := _book_nodes(menu)
	_kill_book_anim(menu)
	if not menu.has_meta("dim_alpha"): menu.set_meta("dim_alpha",n["dim"].color.a)
	var dim_alpha: float = menu.get_meta("dim_alpha")
	var cover: Control = n["cover"]
	var paper: Control = n["paper"]
	var area: Control = n["area"]
	var header: Control = n["header"]
	var cc: Control = n["cc"]
	var dim: ColorRect = n["dim"]
	var shift := _closed_shift(n["main"])
	menu.set_meta("book_opening",true)
	menu.set_meta("book_closing",false)
	paper.set_left_visible(false)
	cover.set_angle(0.0)
	cover.visible = true
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	area.modulate.a = 0.0
	header.modulate.a = 0.0
	dim.color.a = 0.0
	cc.position = Vector2(-shift,menu.get_viewport_rect().size.y * 0.6)
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(cc,"position:y",0.0,BOOK_RISE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim,"color:a",dim_alpha,BOOK_RISE)
	tw.set_parallel(false)
	tw.tween_interval(0.08)
	tw.tween_method(func(a: float) -> void:
		cover.set_angle(a * 2.0)
		cc.position.x = lerpf(-shift,0.0,smoothstep(0.35,1.0,a))
		var fade := smoothstep(0.88,1.0,a)
		area.modulate.a = fade
		header.modulate.a = fade,0.0,1.0,BOOK_SWING).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: _book_settle(menu,n,true))
	menu.set_meta("book_anim",tw)

# 닫기 연출을 시작한다. 연출을 못 쓰면(헤드리스 등) false 를 돌려주고 호출한 쪽이 바로 숨긴다.
static func play_close(menu: Control) -> bool:
	if DisplayServer.get_name() == "headless": return false
	var n := _book_nodes(menu)
	_kill_book_anim(menu)
	if not menu.has_meta("dim_alpha"): menu.set_meta("dim_alpha",n["dim"].color.a)
	var cover: Control = n["cover"]
	var paper: Control = n["paper"]
	var area: Control = n["area"]
	var header: Control = n["header"]
	var cc: Control = n["cc"]
	var dim: ColorRect = n["dim"]
	var shift := _closed_shift(n["main"])
	menu.set_meta("book_closing",true)
	cover.set_angle(2.0)
	cover.visible = true
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(a: float) -> void:
		var fade := 1.0 - smoothstep(0.0,0.12,a)
		area.modulate.a = fade
		header.modulate.a = fade,0.0,1.0,0.1)
	tw.tween_callback(func() -> void: paper.set_left_visible(false))
	tw.tween_method(func(a: float) -> void:
		cover.set_angle(2.0 - a * 2.0)
		cc.position.x = lerpf(0.0,-shift,smoothstep(0.0,0.65,a)),0.0,1.0,BOOK_SWING * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(true)
	tw.tween_property(cc,"position:y",menu.get_viewport_rect().size.y * 0.6,BOOK_SINK).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(dim,"color:a",0.0,BOOK_SINK)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		menu.visible = false
		menu.set_meta("book_closing",false)
		_book_settle(menu,n,false))
	menu.set_meta("book_anim",tw)
	return true
