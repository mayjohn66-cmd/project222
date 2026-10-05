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
		slide.tween_property(button,"custom_minimum_size:x",FLAG_LENGTHS[i]+(SELECTED_EXTRA if i == menu.current_tab else 0.0),0.18)
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
	## 두꺼운 책을 비스듬히 본 모습: 단단한 표지(아래·오른쪽으로 두께가 보임), 겹쳐진 종이 가장자리(가는 줄무늬), 옆면에서 튀어나온 포스트잇 책갈피가 붙는 자리.
	func _draw() -> void:
		var width := size.x-104.0
		var h := size.y
		var fore_w := 24.0
		# 바닥 그림자와 표지 두께(아래·오른쪽)
		draw_rect(Rect2(-6,-4,width+34,h+34),Color("1d141066"))
		draw_rect(Rect2(-12,-12,width+fore_w+22.0,h+36),Color("4a3223"))  # 표지 뒷면(두께)
		draw_rect(Rect2(-12,-12,width+fore_w+22.0,h+26),Color("70503b"))  # 표지
		draw_rect(Rect2(-12,h+14,width+fore_w+22.0,6),Color("33231a"))  # 표지 바닥 모서리
		draw_rect(Rect2(-8,-8,width+16,h+16),Color("c4b28f"))
		# 종이 더미: 맨 위 종이 아래로 몇 장이 계단처럼 겹쳐 보인다
		for edge in [9,6,3,0]:
			draw_rect(Rect2(edge,edge,width,h),Color("e4d7bb"))
			draw_rect(Rect2(edge,edge,width,h),Color("b9a582"),false,1)
		draw_rect(Rect2(0,0,width,h-3),Color("f5eddc"))
		# 책 옆면(오른쪽): 쪽수가 쌓인 가는 줄무늬. 포스트잇이 이 위에 붙는다
		var fore_x := width-2.0
		draw_rect(Rect2(fore_x,3,fore_w,h-6),Color("efe3c7"))
		var y := 4.0
		var toggle := false
		while y < h-4.0:
			draw_line(Vector2(fore_x,y),Vector2(fore_x+fore_w,y),Color("b9a582") if toggle else Color("fffaf0"),1)
			toggle = not toggle
			y += 2.0
		draw_line(Vector2(fore_x+fore_w,3),Vector2(fore_x+fore_w,h-3),Color("9c8a68"),1)
		# 쪽수가 둥글게 휘어 보이도록 안쪽에 어두운 세로 줄 몇 개
		for k in range(1,4):
			draw_line(Vector2(fore_x+fore_w*float(k)/4.0,3),Vector2(fore_x+fore_w*float(k)/4.0,h-3),Color(0.55,0.47,0.34,0.22),1)
		# 아래쪽 종이 옆면
		draw_rect(Rect2(3,h-3,width+fore_w-2.0,11),Color("efe3c7"))
		for k in range(1,6):
			draw_line(Vector2(3,h-3+k*2),Vector2(width+fore_w+1.0,h-3+k*2),Color("b9a582"),1)
		# 왼쪽 제본 부분의 좁은 쪽과 홈
		draw_rect(Rect2(-5,0,13,h-3),Color("e5d5b5"))
		draw_line(Vector2(4,0),Vector2(4,h-3),Color("bca580"),2)
		draw_line(Vector2(8,0),Vector2(8,h-3),Color("dfcdae"),3)

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
