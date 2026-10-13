extends RefCounted
const ACCENTS := ["98703e","b06b3d","4b8068","527e9a","97754c","897299","567d86","a57179"]
const PAPERS := ["f5eddc","f7eddf","f0f1e3","edf1ec","f4eddf","f3edf2","edf1ef","f5eddc"]
# 포스트잇만 구역색을 사용한다. 본문 조작부는 종이/갈색 규칙을 유지한다.
const BOOKMARK_COLORS := ["E8C979","EFBFA8","BFD0A6","B8CEDE","E1BB86","C6B7D9","B3CFC7","E3B8BD"]
# 포스트잇 책갈피: 포스트잇은 쪽에 붙어 있고 책 옆면 밖으로 FLAG_OUT 만큼 튀어나와 있다(탭 이름이 적힘). 지금 펼친 탭의 포스트잇만
# 쪽 안쪽 여백으로 BookViews.ONTO 만큼 붙는다(한 장의 포스트잇이 쪽 가장자리를 감싼 모양, Strip 이 그림). 나머지는 밖으로 튀어나온 부분만 보인다.
const FLAG_OUT := 100.0
const FLAG_HEIGHT := 44.0
const FLAG_GAP := 20  # 포스트잇 사이 간격

# 포스트잇의 모양은 BookViews.Strip(책 밖)·BookViews.Note(쪽 위)가 그린다. 버튼은 글자와 클릭만 맡는다.
static func flag_style(_color: String) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = 16
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
	t.default_font_size = UiTypography.DEFAULT_SIZE
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
	InteractionUiStyle.apply(t)
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
	nav.add_theme_constant_override("separation",FLAG_GAP)  # 포스트잇 사이 간격
	v.get_node("Body").move_child(nav,v.get_node("Body").get_child_count()-1)
	v.get_node("Body").add_theme_constant_override("separation",0)
	var buttons: Array = nav.get_children()
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		b.custom_minimum_size = Vector2(FLAG_OUT,FLAG_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size",UiTypography.size(15))
		for state in ["normal","hover","pressed","hover_pressed"]:
			b.add_theme_stylebox_override(state,flag_style(""))
		for key in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:
			b.add_theme_color_override(key,InteractionUiStyle.INK)
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
		label.add_theme_font_size_override("font_size",UiTypography.size(15))
		label.add_theme_color_override("font_color",Color("67543b"))
	var area: Control = v.get_node("Body/ContentArea")
	var contents := [menu.inventory_content,menu.production_content,menu.employee_content,menu.blueprint_content,menu.construction_content,menu.schedule_content,menu.history_content,menu.request_content]
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
	for c in [menu.schedule_content,menu.history_content,menu.request_content]:
		var m: MarginContainer = c.get_node("MarginContainer")
		for side in ["left","right","top","bottom"]: m.add_theme_constant_override("margin_"+side,16)
	menu.history_content.get_node("MarginContainer/HistoryVBox").add_theme_constant_override("separation",10)
	menu.schedule_content.get_node("MarginContainer/ScheduleVBox").add_theme_constant_override("separation",14)
	menu.schedule_current_date_label.add_theme_font_size_override("font_size",UiTypography.size(22))
	menu.history_title_label.add_theme_font_size_override("font_size",UiTypography.size(20))
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
	var strip := BookViews.Strip.new()
	strip.name = "BookStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(strip)
	main.move_child(strip,1)  # 내비게이션 버튼(글자) 아래, 쪽 위
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for bi in range(nav.get_child_count()):
		var nb: Button = nav.get_child(bi)
		if not nb.visible: continue
		if not nb.visible: continue
		nb.mouse_entered.connect(func() -> void: strip.set_hover(bi))
		nb.mouse_exited.connect(func() -> void: strip.set_hover(-1))
	var note_view := BookViews.Note.new()
	note_view.name = "BookNote"
	note_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(note_view)
	note_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nav.sort_children.connect(func() -> void: _sync_note.call_deferred(menu))
	InventoryDetailPane.install(menu.management_inventory)
	_embed_in_viewport(menu,main,book)
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
		button.custom_minimum_size.x = FLAG_OUT
	_sync_note.call_deferred(menu)
	var last: int = int(menu.get_meta("book_last_tab",-1))
	menu.set_meta("book_last_tab",menu.current_tab)
	var stage = menu.get_meta("book_stage") if menu.has_meta("book_stage") else null
	if is_instance_valid(stage) and animations_enabled and last >= 0 and last != menu.current_tab and stage.at_rest():
		_flip_tabs(menu,stage,last)

# 포스트잇이 어느 쪽에 있는지: 현재 탭 뒤의 탭은 오른쪽, 앞의 탭은 넘어간 종이에 붙어 왼쪽 가장자리, 책장에 실려 넘어가는 중이면 "moving".
# 3D 책이 없으면(헤드리스) 모두 오른쪽.
static func flag_side(menu: Control,index: int) -> String:
	if not uses_3d(): return "right"
	var moving: Array = menu.get_meta("book_moving") if menu.has_meta("book_moving") else []
	if moving.has(index): return "moving"
	return "left" if index < menu.current_tab else "right"


# 펼친 탭의 포스트잇이 쪽 위로 넘어온 부분을 그리고(BookViews.Note), 포스트잇들의 자리를 쪽·왼쪽 가장자리에 맞춘다. 내비게이션이 자리를 잡은 뒤의 버튼 위치를 따라간다.
static func _sync_note(menu: Control) -> void:
	var main = menu.get_node_or_null("DimBackground/CenterContainer/MainPanel")
	if main == null: return
	var note = main.get_node_or_null("BookNote")
	var nav: Control = main.get_node("MainVBox/Body/Navigation")
	if note == null or menu.current_tab >= nav.get_child_count(): return
	var strip = main.get_node_or_null("BookStrip")
	var left_list: Array = []
	var list: Array = []
	for bi in range(nav.get_child_count()):
		var nb: Button = nav.get_child(bi)
		var side := flag_side(menu,bi)
		var on_right := side == "right"
		nb.modulate.a = 1.0 if on_right else 0.0
		nb.mouse_filter = Control.MOUSE_FILTER_STOP if on_right else Control.MOUSE_FILTER_IGNORE
		var nr := nb.get_global_rect()
		var color := bookmark_color(bi)
		if strip != null:
			list.append({"rect": Rect2(nr.position - strip.get_global_rect().position,nr.size),"color": color,"hidden": not on_right,"current": bi == menu.current_tab})
		if side == "left":
			left_list.append({"tab": bi,"rect": nr,"color": color,"label": nb.text})
	if strip != null: strip.set_items(list)
	var stage := _stage_of(menu)
	if stage != null: stage.set_left_flags(left_list)
	note.set_note(Rect2(),Color.WHITE)  # 쪽 위의 반투명 필름은 쓰지 않는다(포스트잇은 Strip 이 한 장으로 그린다)


# ---------------------------------------------------------------- 3D 책
# 관리 창의 실제 UI(MainPanel)는 SubViewport 안에서 계속 돌아가고, 그 화면이 3D 책(BookStage3D)의 두 쪽과 포스트잇 질감이 된다.
# 열기: 책이 화면 아래에서 올라온 뒤 표지가 넘어가며 펼쳐진다(쪽의 UI 가 표지 밑에서 드러난다).  닫기: 반대 순서.
# 탭 이동: 지금 두 쪽을 사진으로 떠 두고 책장을 넘기는 동안 사진을 쪽에 입힌다(BookFlip3D).
# 3D 를 못 쓰는 헤드리스에서는 SubViewport 없이 기존 2D 배치(Paper 가 책 모양을 그림) 그대로 쓴다.
# false 면 책 여닫기·책장 넘김 연출을 건너뛴다(검사 장면이 창이 움직이는 도중의 위치를 재지 않도록).
static var animations_enabled: bool = true
const BOOK_RISE := 0.42
const BOOK_SWING := 0.85
const BOOK_SINK := 0.30


static func uses_3d() -> bool:
	return DisplayServer.get_name() != "headless"


# MainPanel 을 SubViewport(이름은 그대로 CenterContainer)로 옮긴다. 경로 DimBackground/CenterContainer/MainPanel 은 바뀌지 않는다.
static func _embed_in_viewport(menu: Control,main: Control,paper: Control) -> void:
	if not uses_3d(): return
	var dim: Control = menu.get_node("DimBackground")
	var cc: Control = dim.get_node("CenterContainer")
	var ui_size := Vector2i(main.get_combined_minimum_size().max(Vector2(1040,580)))
	cc.name = "CenterContainerOld"
	var sv := SubViewport.new()
	sv.name = "CenterContainer"
	sv.size = ui_size
	sv.transparent_bg = true
	sv.gui_embed_subwindows = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	dim.add_child(sv)
	dim.move_child(sv,cc.get_index())
	cc.remove_child(main)
	sv.add_child(main)
	main.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	main.position = Vector2.ZERO
	main.size = Vector2(ui_size)
	cc.queue_free()
	paper.pages_only = true
	paper.queue_redraw()
	main.visible = false
	menu.set_meta("book_viewport",sv)
	menu.visibility_changed.connect(_on_menu_visibility.bind(menu))


# 메뉴가 보이는 동안만 UI 화면을 그리고 3D 책을 세워 둔다. (SubViewport 는 CanvasItem 이 아니어서 부모가 숨겨져도 자식은 "보임"으로 남으므로 직접 맞춘다)
static func _on_menu_visibility(menu: Control) -> void:
	var sv: SubViewport = menu.get_meta("book_viewport")
	var main: Control = sv.get_node("MainPanel")
	var shown: bool = menu.is_visible_in_tree()
	main.visible = shown
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if shown:
		_ensure_stage(menu)
	else:
		_free_stage(menu)


static func _stage_of(menu: Control) -> BookStage3D:
	var stage = menu.get_meta("book_stage") if menu.has_meta("book_stage") else null
	return stage if is_instance_valid(stage) else null


# 3D 책이 없으면 만든다(펼친 정지 상태로). 연출은 호출한 쪽이 상태를 다시 정한다.
static func _ensure_stage(menu: Control) -> BookStage3D:
	var stage := _stage_of(menu)
	if stage != null: return stage
	var sv: SubViewport = menu.get_meta("book_viewport")
	stage = BookStage3D.new()
	stage.name = "BookStage3D"
	menu.add_child(stage)
	menu.move_child(stage,menu.get_node("DimBackground").get_index() + 1)
	stage.build(sv,menu.get_viewport_rect().size,"영업 일지",PlayerProgress.display_player_name())
	stage.drag_allowed = func(dir: int) -> bool:
		var next := int(menu.current_tab) + dir
		var nav: Control = menu.inventory_button.get_parent()
		return next >= 0 and next < nav.get_child_count() and nav.get_child(next).visible
	stage.drag_started.connect(func(dir: int) -> void: _drag_begin(menu,stage,dir))
	stage.drag_moved.connect(func(th: float) -> void: _drag_move(menu,th))
	stage.drag_ended.connect(func() -> void: _drag_end(menu,stage))
	stage.tab_picked.connect(func(t: int) -> void: menu.select_tab(t))
	_sync_note.call_deferred(menu)
	stage.set_state(1.0,1.0)
	menu.set_meta("book_stage",stage)
	return stage


static func _free_stage(menu: Control) -> void:
	_kill_anim(menu)
	var stage := _stage_of(menu)
	if stage != null: stage.queue_free()
	menu.set_meta("book_stage",null)
	menu.set_meta("book_opening",false)
	menu.set_meta("book_closing",false)
	_restore_dim(menu)


static func _restore_dim(menu: Control) -> void:
	var dim: ColorRect = menu.get_node("DimBackground")
	if menu.has_meta("dim_alpha"): dim.color.a = float(menu.get_meta("dim_alpha"))


# 진행 중인 연출(트윈)과 책장 넘김 덮개를 걷고 쪽 질감을 UI 화면으로 되돌린다.
static func _kill_anim(menu: Control,keep_art: bool = false) -> void:
	var old = menu.get_meta("book_anim") if menu.has_meta("book_anim") else null
	if old is Tween and old.is_valid(): old.kill()
	menu.set_meta("book_anim",null)
	var flip = menu.get_meta("book_flip") if menu.has_meta("book_flip") else null
	if is_instance_valid(flip): flip.queue_free()
	menu.set_meta("book_flip",null)
	menu.set_meta("book_drag",null)
	if not keep_art:
		var art = menu.get_meta("book_flag_art") if menu.has_meta("book_flag_art") else null
		if is_instance_valid(art): art.queue_free()
		menu.set_meta("book_flag_art",null)
	var stage := _stage_of(menu)
	if stage != null: stage.unfreeze_pages()
	if menu.has_meta("book_moving") and not (menu.get_meta("book_moving") as Array).is_empty():
		menu.set_meta("book_moving",[])
		_sync_note.call_deferred(menu)


static func play_open(menu: Control) -> void:
	if not uses_3d() or not animations_enabled: return
	var stage := _ensure_stage(menu)
	var dim: ColorRect = menu.get_node("DimBackground")
	if not menu.has_meta("dim_alpha"): menu.set_meta("dim_alpha",dim.color.a)
	var dim_alpha: float = menu.get_meta("dim_alpha")
	var resume := bool(menu.get_meta("book_closing",false))  # 닫히는 도중에 다시 열면 지금 모습에서 이어서 올라온다
	var st := {"rise": stage.rise_value() if resume else 0.0,"open": stage.open_value() if resume else 0.0}
	_kill_anim(menu)
	menu.set_meta("book_opening",true)
	menu.set_meta("book_closing",false)
	stage.set_state(st["rise"],st["open"])
	dim.color.a = 0.0 if not resume else dim.color.a
	var apply := func() -> void: stage.set_state(st["rise"],st["open"])
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_method(func(v: float) -> void:
		st["rise"] = v
		apply.call(),st["rise"],1.0,BOOK_RISE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim,"color:a",dim_alpha,BOOK_RISE)
	tw.set_parallel(false)
	tw.tween_interval(0.08)
	tw.tween_method(func(v: float) -> void:
		st["open"] = v
		apply.call(),st["open"],1.0,BOOK_SWING).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		menu.set_meta("book_opening",false)
		if is_instance_valid(stage): stage.set_state(1.0,1.0))
	menu.set_meta("book_anim",tw)


# 닫기 연출을 시작한다. 연출을 못 쓰면(헤드리스 등) false 를 돌려주고 호출한 쪽이 바로 숨긴다.
static func play_close(menu: Control) -> bool:
	if not uses_3d() or not animations_enabled: return false
	var stage := _ensure_stage(menu)
	var dim: ColorRect = menu.get_node("DimBackground")
	if not menu.has_meta("dim_alpha"): menu.set_meta("dim_alpha",dim.color.a)
	var st := {"rise": stage.rise_value(),"open": stage.open_value()}
	_kill_anim(menu)
	menu.set_meta("book_opening",false)
	menu.set_meta("book_closing",true)
	var apply := func() -> void: stage.set_state(st["rise"],st["open"])
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void:
		st["open"] = v
		apply.call(),st["open"],0.0,BOOK_SWING * 0.82 * maxf(st["open"],0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.05)
	tw.set_parallel(true)
	tw.tween_method(func(v: float) -> void:
		st["rise"] = v
		apply.call(),st["rise"],0.0,BOOK_SINK).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(dim,"color:a",0.0,BOOK_SINK)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		menu.visible = false  # 보이지 않게 되면 3D 책이 걷힌다(_on_menu_visibility)
		menu.set_meta("book_closing",false)
		_restore_dim(menu))
	menu.set_meta("book_anim",tw)
	return true


# 탭을 옮길 때 책장 넘김. 옛 두 쪽을 사진으로 떠 쪽에 입혀 두고(살아 있는 화면이 먼저 바뀌어도 보이지 않게),
# 새 화면이 그려진 뒤 새 두 쪽 사진을 떠서 BookFlip3D 로 넘긴다. 사이를 건너는 탭들의 포스트잇은 종이에 붙어 함께 넘어간다:
# 뒤쪽 탭으로 가면 old..new-1 탭이 왼쪽으로(맨 위 종이가 old 탭 것), 앞쪽 탭으로 가면 new..old-1 탭이 오른쪽으로(맨 위 종이가 old-1 탭 것).
static func _flip_tabs(menu: Control,stage: BookStage3D,old_tab: int) -> void:
	var new_tab: int = menu.current_tab
	var forward := new_tab > old_tab
	var moving: Array = []
	var order: Array = []  # 종이 순서(먼저 넘어가는 종이부터)에 따른 탭
	if forward:
		for t in range(old_tab,new_tab): order.append(t)
	else:
		for t in range(old_tab - 1,new_tab - 1,-1): order.append(t)
	moving = order.duplicate()
	var old: Array = stage.capture_halves()
	if old.is_empty(): return
	stage.freeze_pages(old[0],old[1])
	menu.set_meta("book_moving",moving)
	_sync_note.call_deferred(menu)
	var arts := _flag_arts(menu,order)  # 두 프레임을 기다리는 동안 포스트잇 질감도 그려 둔다
	var art_owner: Node = menu.get_meta("book_flag_art")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(menu) or not is_instance_valid(stage) or not stage.is_inside_tree(): return
	# A newer tab/close can replace and free this capture during the two-frame wait.
	if not is_instance_valid(art_owner) or art_owner.is_queued_for_deletion() or menu.get_meta("book_flag_art",null) != art_owner: return
	if not menu.visible or bool(menu.get_meta("book_closing",false)): return
	var fresh: Array = stage.capture_halves()
	if fresh.is_empty():
		_kill_anim(menu)
		return
	_kill_anim(menu,true)  # 앞서 넘기던 것이 있으면 걷는다(쪽 질감은 곧 다시 사진으로). 방금 그린 포스트잇 질감은 남긴다
	stage.freeze_pages(old[0],old[1])
	menu.set_meta("book_moving",moving)
	_sync_note(menu)
	var flip := _make_flip(menu,stage,forward,order,old,fresh,arts)
	menu.set_meta("book_flip",flip)
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(flip.set_progress,0.0,1.0,flip.duration)
	tw.tween_callback(func() -> void: _kill_anim(menu))
	menu.set_meta("book_anim",tw)


# 책장 넘김 한 장을 만든다. order = 종이에 붙어 함께 넘어갈 포스트잇 탭들(먼저 넘어가는 종이부터).
static func _make_flip(menu: Control,stage: BookStage3D,forward: bool,order: Array,old: Array,fresh: Array,arts: Array) -> BookFlip3D:
	var nav: Control = menu.get_node("DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation")
	var carry: Array = []
	for t in order:
		var zr := stage.flag_z_range(nav.get_child(t).get_global_rect())
		var art: Dictionary = arts[carry.size()]
		carry.append({"z0": zr.x,"z1": zr.y,"color": bookmark_color(t),"tex_right": art["right"].get_texture(),"tex_left": art["left"].get_texture(),"len": nav.get_child(t).size.x / 100.0})
	var geo: Dictionary = stage.page_geometry()
	var flip := BookFlip3D.new()
	flip.name = "BookFlip3D"
	menu.add_child(flip)
	menu.move_child(flip,stage.get_index() + 1)
	flip.build(geo["page_w"],geo["page_h"],geo["spine"],menu.get_viewport_rect().size,old[0],old[1],fresh[0],fresh[1],forward,order.size(),carry)
	return flip


# ---------------------------------------------------------------- 쪽 끌어 넘기기
# 손가락(마우스)이 끄는 대로 종이가 따라오고, 놓을 때 35% 이상 넘어갔으면 다음/이전 탭으로 넘어가고 못 넘었으면 되돌아간다.
# 끌기가 시작되면 지금 두 쪽을 사진으로 떠 두고 탭을 새 탭으로 옮겨 새 화면이 그려지면(두 프레임) 그 사진으로 종이 뒷면을 만든다.
const DRAG_COMPLETE := 0.35


static func _drag_begin(menu: Control,stage: BookStage3D,dir: int) -> void:
	var old_tab: int = menu.current_tab
	var new_tab := old_tab + dir
	var old: Array = stage.capture_halves()
	if old.is_empty(): return
	var st := {"ready": false,"ended": false,"theta": 0.0,"old_tab": old_tab,"new_tab": new_tab,"dir": dir,"flip": null}
	menu.set_meta("book_drag",st)
	stage.freeze_pages(old[0],old[1])
	var order: Array = [old_tab] if dir > 0 else [new_tab]
	menu.set_meta("book_moving",order)
	menu.select_tab(new_tab)
	var arts := _flag_arts(menu,order)
	var art_owner: Node = menu.get_meta("book_flag_art")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(menu) or not is_instance_valid(stage) or menu.get_meta("book_drag") != st: return
	if not is_instance_valid(art_owner) or art_owner.is_queued_for_deletion() or menu.get_meta("book_flag_art",null) != art_owner: return
	var fresh: Array = stage.capture_halves()
	if fresh.is_empty():
		_kill_anim(menu)
		return
	var flip := _make_flip(menu,stage,dir > 0,order,old,fresh,arts)
	flip.set_theta(float(st["theta"]))
	st["flip"] = flip
	st["ready"] = true
	menu.set_meta("book_flip",flip)
	if bool(st["ended"]): _drag_finish(menu,st)


static func _drag_move(menu: Control,theta: float) -> void:
	var st = menu.get_meta("book_drag") if menu.has_meta("book_drag") else null
	if not (st is Dictionary): return
	st["theta"] = theta
	if bool(st["ready"]) and is_instance_valid(st["flip"]): (st["flip"] as BookFlip3D).set_theta(theta)


static func _drag_end(menu: Control,_stage: BookStage3D) -> void:
	var st = menu.get_meta("book_drag") if menu.has_meta("book_drag") else null
	if not (st is Dictionary): return
	st["ended"] = true
	if bool(st["ready"]): _drag_finish(menu,st)


# 놓았다: DRAG_COMPLETE(35%)를 넘었으면 끝까지 넘기고, 아니면 되돌린 뒤 탭도 원래대로 돌린다.
static func _drag_finish(menu: Control,st: Dictionary) -> void:
	var flip: BookFlip3D = st["flip"]
	var theta: float = st["theta"]
	var complete := theta >= PI * DRAG_COMPLETE  # 종이가 이만큼(각도 비율) 넘어갔으면 끝까지 넘긴다
	var target := PI if complete else 0.0
	var tw := menu.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(flip.set_theta,theta,target,0.08 + 0.22 * absf(target - theta) / PI).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if not complete:
			menu.select_tab(int(st["old_tab"]))  # 쪽은 아직 사진이라 되돌리는 모습은 보이지 않는다
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
		if is_instance_valid(menu): _kill_anim(menu))
	menu.set_meta("book_anim",tw)


# 책장에 실려 넘어가는 포스트잇(탭 order)의 질감을 그린다: [{right, left}] SubViewport. 넘김이 끝나면 함께 지운다.
static func _flag_arts(menu: Control,order: Array) -> Array:
	var holder := Node.new()
	holder.name = "BookFlagArt"
	menu.add_child(holder)
	var old = menu.get_meta("book_flag_art") if menu.has_meta("book_flag_art") else null
	if is_instance_valid(old): old.queue_free()
	menu.set_meta("book_flag_art",holder)
	var nav: Control = menu.get_node("DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation")
	var out: Array = []
	for t in order:
		var nb: Button = nav.get_child(t)
		var color := bookmark_color(t)
		out.append({"right": BookViews.make_flag_art(holder,color,nb.text,false,nb.size),"left": BookViews.make_flag_art(holder,color,nb.text,true,nb.size)})
	return out

static func bookmark_color(index: int) -> Color:
	return Color(BOOKMARK_COLORS[index % BOOKMARK_COLORS.size()])
