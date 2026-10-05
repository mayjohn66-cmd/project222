extends RefCounted
const ACCENTS := ["98703e","b06b3d","4b8068","527e9a","97754c","897299","567d86"]
const PAPERS := ["f5eddc","f7eddf","f0f1e3","edf1ec","f4eddf","f3edf2","edf1ef"]
const INDEX_COLORS := ["f2cf5b","ef8fa6","8fcf9a","7bbbe0","eeb06a","b79bdb","7fd0c8"]
# 포스트잇 책갈피: 책 옆면에서 튀어나온 길이를 탭마다 다르게(들쭉날쭉), 선택하면 +SELECTED_EXTRA 만큼 더 나온다. 가장 긴 값이 내비게이션 폭 104 를 넘지 않게 한다.
const FLAG_LENGTHS := [72.0,84.0,76.0,88.0,70.0,86.0,78.0]
const FLAG_HEIGHT := 30.0
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
	nav.add_theme_constant_override("separation",2)  # 포스트잇이 거의 맞닿게(참고 사진처럼 촘촘히)
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
	menu.close_button.hide()  # 닫기 버튼은 없애고 책 아래 "ESC 닫기" 안내(BookViews.Paper)와 바깥 클릭·ESC 로 닫는다
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
	menu.production_content.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
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
	var dim_area: Control = menu.get_node("DimBackground")
	dim_area.gui_input.connect(func(event: InputEvent) -> void:
		# 책 바깥(어두운 바닥)을 누르면 닫는다. 연출 중에는 무시한다.
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not bool(menu.get_meta("book_opening",false)) and not bool(menu.get_meta("book_closing",false)) and not main.get_global_rect().has_point(event.global_position):
			menu.close_menu())
	BookLayout.apply(menu)
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
	# 종이 색과 무늬는 쪽(BookViews.Paper)이 그린다. 안쪽 사각형 바탕을 따로 두면 쪽 위에 가장자리가 보여 어색하다.
	area.get_node("ContentBackdrop").add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var paper = area.get_parent().get_parent().get_parent().get_child(0)
	if paper.has_method("set_mode"): paper.set_mode(menu.current_tab)
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
			flip.begin(menu.current_tab > flip.last_tab,absi(menu.current_tab - flip.last_tab))
		flip.last_tab = menu.current_tab

# ---------------------------------------------------------------- 책 여닫기 연출
# 열기: 닫힌 책(세로형 표지 + 옆의 포스트잇)이 화면 아래에서 올라온 뒤, 표지가 가운데 제본선을 축으로 왼쪽으로 넘어가며 펼쳐지고
#       책 전체가 가운데로 옮겨 앉은 다음에야 쪽 안의 UI 가 나타난다.
# 닫기: UI 가 사라지고 표지가 다시 덮인 뒤 책이 아래로 내려간다. 트리가 멈춰 있어도 돌아가도록 PROCESS 모드 트윈을 쓴다.
# false 면 책 여닫기 연출을 건너뛴다(검사 장면이 창이 움직이는 도중의 위치를 재지 않도록).
static var animations_enabled: bool = true
# true 면 열고 닫을 때 3D 책(BookStage3D)을 쓰고, false 면 2D 로 그린 표지 연출을 쓴다.
static var book_3d: bool = true
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
	var stage = menu.get_meta("book_stage") if menu.has_meta("book_stage") else null
	if is_instance_valid(stage): stage.queue_free()
	menu.set_meta("book_stage",null)
	var main = menu.get_node_or_null("DimBackground/CenterContainer/MainPanel")
	if main: main.modulate.a = 1.0

static func _book_settle(menu: Control,n: Dictionary,visible_book: bool) -> void:
	n["cc"].position = Vector2.ZERO
	n["dim"].color.a = float(menu.get_meta("dim_alpha",0.85))
	n["area"].modulate.a = 1.0
	n["header"].modulate.a = 1.0
	n["cover"].visible = false
	n["cover"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	n["cover"].angle = 0.0
	n["paper"].set_left_visible(true)
	n["main"].modulate.a = 1.0
	menu.set_meta("book_opening",false)

# 닫힌 책을 가운데에 놓으려면 펼친 책 기준 위치에서 쪽 폭의 4분의 1만큼 왼쪽으로 옮긴다.
static func _closed_shift(main: Control) -> float:
	return BookViews.page_width(main.size) * 0.25

static func play_open(menu: Control) -> void:
	if DisplayServer.get_name() == "headless" or not animations_enabled: return
	var n := _book_nodes(menu)
	_kill_book_anim(menu)
	if not menu.has_meta("dim_alpha"): menu.set_meta("dim_alpha",n["dim"].color.a)
	if book_3d:
		_open_3d(menu,n)
		return
	var dim_alpha: float = menu.get_meta("dim_alpha")
	var cover: Control = n["cover"]
	var paper: Control = n["paper"]
	var area: Control = n["area"]
	var header: Control = n["header"]
	var cc: Control = n["cc"]
	var dim: ColorRect = n["dim"]
	var shift := _closed_shift(n["main"])
	cover.owner_text = PlayerProgress.display_player_name()
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
	if DisplayServer.get_name() == "headless" or not animations_enabled: return false
	var n := _book_nodes(menu)
	_kill_book_anim(menu)
	if not menu.has_meta("dim_alpha"): menu.set_meta("dim_alpha",n["dim"].color.a)
	if book_3d:
		_close_3d(menu,n)
		return true
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


# ---------------------------------------------------------------- 3D 책 연출
# 열기: 3D 책이 화면 아래에서 올라오고 → 표지가 제본선을 축으로 왼쪽으로 넘어가며 카메라가 바로 위로 돌고 → 3D 를 걷어 내며 2D 펼침면(UI)이 나타난다.
# 닫기: 2D → 3D 로 바꾼 뒤 표지가 덮이고 책이 아래로 내려간다. 3D 쪽은 쪽에 글이 없다(펼침이 끝난 뒤에 UI 가 나타난다).

# 3D 책을 만든다: 2D 펼침면(Paper)과 같은 자리·크기, 포스트잇은 내비게이션 버튼의 현재 위치에 맞춘다.
static func _make_stage(menu: Control,n: Dictionary) -> BookStage3D:
	var paper: Control = n["paper"]
	var page_w := BookViews.page_width(paper.size)
	var page_h := paper.size.y - 3.0
	var origin := paper.get_global_rect().position
	var spine := origin + Vector2(page_w * 0.5,page_h * 0.5)
	var flags: Array = []
	var nav: Control = n["main"].get_node("MainVBox/Body/Navigation")
	for i in range(nav.get_child_count()):
		var b: Control = nav.get_child(i)
		flags.append({"rect": b.get_global_rect(),"color": Color(INDEX_COLORS[i % INDEX_COLORS.size()])})
	var stage := BookStage3D.new()
	stage.name = "BookStage3D"
	menu.add_child(stage)
	stage.build(page_w,page_h,spine,flags,menu.get_viewport_rect().size,"영업 일지",PlayerProgress.display_player_name())
	menu.set_meta("book_stage",stage)
	return stage

static func _open_3d(menu: Control,n: Dictionary) -> void:
	var main: Control = n["main"]
	var dim: ColorRect = n["dim"]
	var dim_alpha: float = menu.get_meta("dim_alpha")
	menu.set_meta("book_opening",true)
	menu.set_meta("book_closing",false)
	main.modulate.a = 0.0
	dim.color.a = 0.0
	n["cc"].position = Vector2.ZERO
	n["cover"].visible = false
	n["paper"].set_left_visible(true)
	await menu.get_tree().process_frame  # 레이아웃이 확정된 뒤에 위치를 읽는다
	if not menu.visible or bool(menu.get_meta("book_closing",false)): return
	var stage := _make_stage(menu,n)
	await menu.get_tree().process_frame  # 표지 질감이 한 번 그려지도록
	if not is_instance_valid(stage): return
	var st := {"rise": 0.0,"open": 0.0}
	var rise_cb := func(v: float) -> void:
		st["rise"] = v
		stage.set_state(st["rise"],st["open"])
	var open_cb := func(v: float) -> void:
		st["open"] = v
		stage.set_state(st["rise"],st["open"])
	stage.set_state(0.0,0.0)
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_method(rise_cb,0.0,1.0,0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim,"color:a",dim_alpha,0.42)
	tw.set_parallel(false)
	tw.tween_interval(0.08)
	tw.tween_method(open_cb,0.0,1.0,0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.03)
	tw.set_parallel(true)
	tw.tween_property(stage,"modulate:a",0.0,0.22)
	tw.tween_property(main,"modulate:a",1.0,0.22)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		if is_instance_valid(stage): stage.queue_free()
		menu.set_meta("book_stage",null)
		_book_settle(menu,n,true))
	menu.set_meta("book_anim",tw)

static func _close_3d(menu: Control,n: Dictionary) -> void:
	var main: Control = n["main"]
	var dim: ColorRect = n["dim"]
	menu.set_meta("book_closing",true)
	var stage := _make_stage(menu,n)
	stage.set_state(1.0,1.0)
	stage.modulate.a = 0.0
	var st := {"rise": 1.0,"open": 1.0}
	var rise_cb := func(v: float) -> void:
		st["rise"] = v
		stage.set_state(st["rise"],st["open"])
	var open_cb := func(v: float) -> void:
		st["open"] = v
		stage.set_state(st["rise"],st["open"])
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(stage,"modulate:a",1.0,0.14)
	tw.tween_property(main,"modulate:a",0.0,0.14)
	tw.set_parallel(false)
	tw.tween_method(open_cb,1.0,0.0,0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.05)
	tw.set_parallel(true)
	tw.tween_method(rise_cb,1.0,0.0,0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(dim,"color:a",0.0,0.3)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		menu.visible = false
		menu.set_meta("book_closing",false)
		if is_instance_valid(stage): stage.queue_free()
		menu.set_meta("book_stage",null)
		_book_settle(menu,n,false))
	menu.set_meta("book_anim",tw)
