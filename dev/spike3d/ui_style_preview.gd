extends Node
## 새 UI 스타일(StoreUiStyle) 시안: 실제 매장 화면 위에 HUD·메뉴 버튼·관리 창 모양을 겹쳐 그려 PNG 로 저장한다.
## 사용: godot --path . res://dev/spike3d/ui_style_preview.tscn -- <저장 폴더>

const S = preload("res://script/ui/style/store_ui_style.gd")

func lab(text: String, size: int = 18, color: Color = S.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

var hybrid: bool = false

func btn(text: String, primary: bool = false, w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 0)
	for st in ["normal", "hover", "pressed", "disabled"]:
		if hybrid:
			var fill: Color = S.BRAND if primary else S.PARCH
			if st == "hover": fill = fill.lightened(0.1)
			if st == "pressed": fill = fill.darkened(0.12)
			b.add_theme_stylebox_override(st, S.box(fill, S.BRASS if primary else S.WOOD, 2, Vector4(16, 9, 16, 9)))
		else:
			b.add_theme_stylebox_override(st, S.button(st, primary))
	var fc: Color = S.WHITE if primary else (S.INK_BROWN if hybrid else S.INK)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fc)
	return b

func hud() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", S.box(S.PAPER, S.BRAND_DEEP, 3, Vector4(0, 0, 0, 0), true))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", S.header_bar())
	head.add_child(lab("1년차 봄 1일  월요일 · 영업", 17, S.WHITE))
	v.add_child(head)
	var body := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: body.add_theme_constant_override("margin_" + side, 12)
	v.add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	body.add_child(col)
	var time_row := HBoxContainer.new()
	time_row.add_child(lab("06:00", 26))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; time_row.add_child(sp)
	time_row.add_child(lab("아침", 16, S.INK_DIM))
	col.add_child(time_row)
	var money := PanelContainer.new()
	money.add_theme_stylebox_override("panel", S.box(S.WHITE, S.LINE, 2, Vector4(8, 4, 8, 4)))
	var mr := HBoxContainer.new()
	var coin := TextureRect.new()
	coin.texture = load("res://art/ui/pixel_theme/icon_coin.png")
	coin.custom_minimum_size = Vector2(24, 24)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mr.add_child(coin)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mr.add_child(spacer)
	mr.add_child(lab("500,000 G", 22, S.INK))
	money.add_child(mr)
	col.add_child(money)
	p.custom_minimum_size = Vector2(250, 0)
	return p

func menu_buttons() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	for i in ["관리", "건설", "설정", "저장"]:
		v.add_child(btn(i, i == "관리", 150))
	return v

func slot_cell(icon_path: String, count: int, selected: bool = false) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(62, 62)
	p.add_theme_stylebox_override("panel", S.box(Color("fff6e0") if selected else S.PARCH_CELL, S.BRASS if selected else S.PARCH_LINE, 3 if selected else 2, Vector4(2, 2, 2, 2)) if hybrid else S.slot(selected))
	if icon_path != "":
		var t := TextureRect.new()
		t.texture = load(icon_path)
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p.add_child(t)
		var c := lab(str(count), 15, S.WHITE)
		c.add_theme_color_override("font_outline_color", S.BRAND_DEEP)
		c.add_theme_constant_override("outline_size", 4)
		c.size_flags_horizontal = Control.SIZE_SHRINK_END
		c.size_flags_vertical = Control.SIZE_SHRINK_END
		p.add_child(c)
	return p

func window() -> Control:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", S.box(S.PARCH, S.WOOD, 6, Vector4(0, 0, 0, 0), true) if hybrid else S.window())
	outer.custom_minimum_size = Vector2(760, 440)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	outer.add_child(v)
	var head := PanelContainer.new()
	var hs: StyleBoxFlat = S.header_bar()
	if hybrid:
		hs.border_color = S.BRASS
		hs.border_width_bottom = 3
	head.add_theme_stylebox_override("panel", hs)
	var hr := HBoxContainer.new()
	hr.add_child(lab("관리 · 인벤토리", 20, S.WHITE))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hr.add_child(sp)
	var close := btn("✕", false)
	hr.add_child(close)
	head.add_child(hr)
	v.add_child(head)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# 옆 탭
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var tm := MarginContainer.new()
	for side in ["left", "top", "bottom"]: tm.add_theme_constant_override("margin_" + side, 12)
	tm.add_theme_constant_override("margin_right", 0)
	tm.add_child(tabs)
	body.add_child(tm)
	var names := ["인벤토리", "생산", "직원", "설계도", "건설", "일정", "정보"]
	for i in range(names.size()):
		var tb := Button.new()
		tb.text = names[i]
		tb.custom_minimum_size = Vector2(112, 0)
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var ts: StyleBoxFlat = S.section_tab(i, i == 0)
			if hybrid:
				ts.bg_color = S.BRAND if i == 0 else S.PARCH
				ts.border_color = S.SECTION_COLORS[i]
				ts.border_width_top = 0; ts.border_width_right = 0; ts.border_width_bottom = 0
				ts.border_width_left = 10
			tb.add_theme_stylebox_override(st, ts)
		tb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			tb.add_theme_color_override(fc, S.WHITE if i == 0 else (S.INK_BROWN if hybrid else S.INK))
		tabs.add_child(tb)
	# 본문
	var content := MarginContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: content.add_theme_constant_override("margin_" + side, 14)
	body.add_child(content)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	content.add_child(cv)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 6)
	for n in ["진열", "가구", "원정", "냉장·냉동 보관"]:
		sub.add_child(btn(n, n == "진열"))
	cv.add_child(sub)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	cv.add_child(split)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	split.add_child(grid)
	var icons := ["res://art/items/pixel_v1/bread.png", "res://art/items/pixel_v1/water.png", "", "", "", "", "", "", "", "", "", "", "", "", ""]
	for i in range(icons.size()):
		grid.add_child(slot_cell(icons[i], 8 if i == 0 else 6, i == 0))
	var info := PanelContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_stylebox_override("panel", S.box(Color("fbf6ea") if hybrid else S.WHITE, S.PARCH_LINE if hybrid else S.LINE, 2, Vector4(14, 12, 14, 12)))
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 8)
	info.add_child(iv)
	iv.add_child(lab("바게트", 22, S.INK_BROWN if hybrid else S.INK))
	var price := PanelContainer.new()
	price.add_theme_stylebox_override("panel", S.tag())
	price.add_child(lab("● 개당 120 G" if hybrid else "개당 120 G", 16, S.INK))
	price.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	iv.add_child(price)
	var d := lab("갓 구운 빵. 진열대에 올려 손님에게 판매합니다.", 16, S.INK_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(d)
	var sp2 := Control.new(); sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL; iv.add_child(sp2)
	iv.add_child(btn("진열대로 옮기기", true))
	split.add_child(info)
	return outer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/ui_style"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in 10: await get_tree().process_frame
	world.get_node("DayManager").hour_timer.stop()
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	# 기존 UI 를 가리는 바탕(시안만 보이게)
	var cover := ColorRect.new()
	cover.color = Color(0.02, 0.05, 0.04, 0.55)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cover)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0)
	layer.add_child(back)
	var h := hud(); layer.add_child(h); h.position = Vector2(1152 - 270, 14)
	var mb := menu_buttons(); layer.add_child(mb); mb.position = Vector2(14, 90)
	var w := window(); layer.add_child(w); w.position = Vector2(190, 90)
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir + "/ui_style_preview.png")
	for n in [h, mb, w]: n.queue_free()
	hybrid = true
	var h2 := hud(); layer.add_child(h2); h2.position = Vector2(1152 - 270, 14)
	var mb2 := menu_buttons(); layer.add_child(mb2); mb2.position = Vector2(14, 90)
	var w2 := window(); layer.add_child(w2); w2.position = Vector2(190, 90)
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir + "/ui_style_hybrid.png")
	print("저장: ", dir)
	get_tree().quit()
