extends RefCounted
const ACCENTS := ["98703e","b06b3d","4b8068","527e9a","97754c","897299","567d86"]
const PAPERS := ["f5eddc","f7eddf","f0f1e3","edf1ec","f4eddf","f3edf2","edf1ef"]
const INDEX_COLORS := ["e6c983","eca993","a5c5a5","94bed0","d5bb91","bca8cb","92c9c5"]

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
	main.custom_minimum_size = Vector2(880,570)
	var cover := box("00000000",18)
	cover.border_color = Color("b58a51")
	cover.set_border_width_all(0)
	cover.shadow_size = 0
	cover.shadow_color = Color("241a16aa")
	main.add_theme_stylebox_override("panel",cover)
	var book := BookPaper.new()
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
	nav.add_theme_constant_override("separation",12)
	v.get_node("Body").move_child(nav,v.get_node("Body").get_child_count()-1)
	v.get_node("Body").add_theme_constant_override("separation",0)
	var buttons: Array = nav.get_children()
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		b.custom_minimum_size = Vector2(88,44)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.add_theme_font_size_override("font_size",16)
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style := box(INDEX_COLORS[i],8)
			style.border_width_left = 0
			style.border_width_bottom = 0
			style.shadow_color = Color("30231330")
			style.shadow_size = 2
			style.content_margin_left = 10
			style.content_margin_right = 10
			style.border_color = Color(ACCENTS[i])
			b.add_theme_stylebox_override(state,style)
		b.add_theme_color_override("font_color",Color("514333"))
		b.add_theme_color_override("font_pressed_color",Color("493e33"))
		b.add_theme_color_override("font_hover_pressed_color",Color("493e33"))
		var focus := box("ffffff00",8)
		focus.border_color = Color(ACCENTS[i])
		focus.set_border_width_all(2)
		b.add_theme_stylebox_override("focus",focus)
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
	var turn := PageTurn.new()
	turn.name = "PageTurn"
	turn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn.process_mode = Node.PROCESS_MODE_ALWAYS
	area.add_child(turn)
	inset(turn,16)
	apply_tab(menu)

static func fit_inventory(inv: Control) -> void:
	var scroll: ScrollContainer = inv.get_node("MainVBox/ItemScroll")
	var grid: GridContainer = scroll.get_node("ItemGrid")
	var columns := clampi(floori((scroll.size.x-12)/78),3,10)
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
		slide.tween_property(button,"custom_minimum_size:x",104.0 if i == menu.current_tab else 88.0,0.18)
		button.set_meta("index_slide",slide)
	var turn = area.get_node_or_null("PageTurn")
	if turn and menu.visible and turn.last_tab != menu.current_tab: turn.flip()
	if turn: turn.last_tab = menu.current_tab
	var pattern = area.get_node_or_null("TabPaperPattern")
	if pattern:
		pattern.mode = menu.current_tab
		pattern.queue_redraw()

class PaperPattern extends Control:
	var mode: int = 0
	func _draw() -> void:
		if mode==3 or mode==4:
			var color := Color(0.3,0.5,0.6,0.07) if mode==3 else Color(0.5,0.4,0.2,0.06)
			for x in range(0,int(size.x),24): draw_line(Vector2(x,0),Vector2(x,size.y),color)
			for y in range(0,int(size.y),24): draw_line(Vector2(0,y),Vector2(size.x,y),color)
		elif mode==5:
			draw_rect(Rect2(0,0,8,size.y),Color("897299"))

class BookPaper extends Control:
	func _draw() -> void:
		var width := size.x-104.0
		# The cover and layered paper stop before the exposed index strips.
		draw_rect(Rect2(-9,-8,width+21,size.y+22),Color("24191155"))
		draw_rect(Rect2(-12,-12,width+24,size.y+24),Color("70503b"))
		draw_rect(Rect2(-8,-8,width+16,size.y+16),Color("c4b28f"))
		for edge in [6,3,0]:
			draw_rect(Rect2(edge,edge,width,size.y),Color("e4d7bb"))
			draw_rect(Rect2(edge,edge,width,size.y),Color("b9a582"),false,1)
		draw_rect(Rect2(0,0,width,size.y-3),Color("f5eddc"))
		# Narrow visible left leaf and the shaded binding.
		draw_rect(Rect2(-5,0,13,size.y-3),Color("e5d5b5"))
		draw_line(Vector2(4,0),Vector2(4,size.y-3),Color("bca580"),2)
		draw_line(Vector2(8,0),Vector2(8,size.y-3),Color("dfcdae"),3)

class PageTurn extends Control:
	var progress := 1.0
	var last_tab := -1
	var animation: Tween
	var old_page: Texture2D
	func flip() -> void:
		# Keep the printed old page fixed until its corner folds away.
		if animation and animation.is_valid(): animation.kill()
		var screenshot: Image = null
		if DisplayServer.get_name() != "headless": screenshot = get_viewport().get_texture().get_image()
		if screenshot == null or screenshot.is_empty():
			old_page = null
		else:
			var ratio := Vector2(screenshot.get_size())/get_viewport_rect().size
			var logical := get_global_rect()
			var bounds := Rect2i(logical.position*ratio,logical.size*ratio).intersection(Rect2i(Vector2i.ZERO,screenshot.get_size()))
			if bounds.size.x > 0 and bounds.size.y > 0:
				old_page = ImageTexture.create_from_image(screenshot.get_region(bounds))
		progress = 0.0
		show()
		animation = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		animation.tween_method(_set_progress,0.0,1.0,0.5)
		animation.tween_callback(hide)
	func _set_progress(value: float) -> void:
		progress = value
		queue_redraw()
	func _clip(poly: PackedVector2Array, normal: Vector2, threshold: float) -> PackedVector2Array:
		var result := PackedVector2Array()
		if poly.is_empty(): return result
		var previous := poly[poly.size()-1]
		for point in poly:
			var a := normal.dot(previous)-threshold
			var b := normal.dot(point)-threshold
			if (a <= 0.0) != (b <= 0.0): result.append(previous.lerp(point,a/(a-b)))
			if b <= 0.0: result.append(point)
			previous = point
		return result
	func _draw() -> void:
		if progress >= 1.0 or size.x <= 0.0 or size.y <= 0.0: return
		var normal := Vector2(0.78,0.63).normalized()
		var threshold := normal.dot(size)*(1.0-progress)-55.0*progress
		var rectangle := PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])
		var flat := _clip(rectangle,normal,threshold)
		if flat.size() >= 3:
			var uv := PackedVector2Array()
			for point in flat: uv.append(point/size)
			if old_page: draw_polygon(flat,PackedColorArray([Color.WHITE]),uv,old_page)
			else: draw_colored_polygon(flat,Color("f5eddc"))
		var lifted := _clip(rectangle,-normal,-threshold)
		var folded := PackedVector2Array()
		var shadow := PackedVector2Array()
		for point in lifted:
			var reflected := point-2.0*normal*(normal.dot(point)-threshold)
			folded.append(reflected)
			shadow.append(reflected+Vector2(9,14)*sin(progress*PI))
		if folded.size() >= 3:
			draw_colored_polygon(shadow,Color(0.20,0.14,0.08,0.18))
			draw_colored_polygon(folded,Color("f4e9d1"))
			# A soft band around the crease gives the turned sheet thickness.
			for band in range(10):
				var strip := _clip(folded,normal,threshold-float(band)*3.0)
				strip = _clip(strip,-normal,-threshold+float(band+1)*3.0)
				if strip.size() >= 3:
					draw_colored_polygon(strip,Color(0.49,0.38,0.23,0.20*(1.0-float(band)/10.0)))
