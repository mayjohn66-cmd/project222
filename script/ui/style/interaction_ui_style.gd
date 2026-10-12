class_name InteractionUiStyle
extends RefCounted
## 배경 장식과 분리한 조작 UI. 기본은 중립색, 선택·포커스만 청록색이다.
const INK := Color("343c3b")
const MUTED := Color("69706c")
const SELECTED := Color("356a63")
const NEUTRAL := Color("e9e7df")
const LIGHT := Color("fffaf0")
const ART := {
	"button_normal": preload("res://art/ui/controls/button_normal.png"),
	"button_hover": preload("res://art/ui/controls/button_hover.png"),
	"button_selected": preload("res://art/ui/controls/button_selected.png"),
	"button_disabled": preload("res://art/ui/controls/button_disabled.png"),
	"input_normal": preload("res://art/ui/controls/input_normal.png"),
	"input_focus": preload("res://art/ui/controls/input_focus.png"),
	"input_readonly": preload("res://art/ui/controls/input_readonly.png"),
	"tab_normal": preload("res://art/ui/controls/tab_normal.png"),
	"tab_hover": preload("res://art/ui/controls/tab_hover.png"),
	"tab_selected": preload("res://art/ui/controls/tab_selected.png"),
	"tab_disabled": preload("res://art/ui/controls/tab_disabled.png"),
	"close": preload("res://art/ui/controls/close.png")
}

static func patch(name: String, pad: Vector4 = Vector4(12,7,12,7)) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = ART[name]
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,3.0)
	style.content_margin_left = pad.x
	style.content_margin_top = pad.y
	style.content_margin_right = pad.z
	style.content_margin_bottom = pad.w
	return style

static func button(state: String) -> StyleBoxTexture:
	var image := "selected" if state in ["pressed","hover_pressed"] else state
	return patch("button_" + image)

static func focus() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = SELECTED
	style.set_border_width_all(2)
	return style

static func window_border() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = NEUTRAL
	style.border_color = Color("707b76")
	style.set_border_width_all(2)
	# Godot는 embedded_border를 본문에만 그린다. 제목줄까지 명시적으로 확장한다.
	style.expand_margin_top = 40
	style.expand_margin_left = 2
	style.expand_margin_right = 2
	style.expand_margin_bottom = 2
	style.shadow_color = Color(0,0,0,0.22)
	style.shadow_size = 4
	return style

static func apply(theme: Theme) -> void:
	for type in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			theme.set_stylebox(state,type,button(state))
		theme.set_stylebox("focus",type,focus())
		for key in ["font_color","font_hover_color","font_focus_color"]:
			theme.set_color(key,type,INK)
		for key in ["font_pressed_color","font_hover_pressed_color"]:
			theme.set_color(key,type,LIGHT)
		theme.set_color("font_disabled_color",type,MUTED)
	for type in ["LineEdit","TextEdit"]:
		theme.set_stylebox("normal",type,patch("input_normal",Vector4(10,7,10,7)))
		theme.set_stylebox("focus",type,patch("input_focus",Vector4(10,7,10,7)))
		theme.set_stylebox("read_only",type,patch("input_readonly",Vector4(10,7,10,7)))
		theme.set_color("font_color",type,INK)
		theme.set_color("font_placeholder_color",type,MUTED)
		theme.set_color("placeholder_color",type,MUTED)
		theme.set_color("caret_color",type,SELECTED)
		theme.set_color("selection_color",type,Color("bad6cd"))
		theme.set_color("font_selected_color",type,INK)
	for type in ["TabBar","TabContainer"]:
		for pair in [["tab_unselected","normal"],["tab_hovered","hover"],["tab_selected","selected"],["tab_disabled","disabled"]]:
			theme.set_stylebox(pair[0],type,patch("tab_"+pair[1]))
		theme.set_stylebox("tab_focus",type,focus())
		theme.set_color("font_selected_color",type,LIGHT)
		theme.set_color("font_unselected_color",type,INK)
		theme.set_color("font_hovered_color",type,INK)
		theme.set_color("font_disabled_color",type,MUTED)
	for type in ["VScrollBar","HScrollBar"]:
		for key in ["grabber","grabber_highlight","grabber_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("8c9690") if key == "grabber" else SELECTED
			style.set_content_margin_all(6)
			theme.set_stylebox(key,type,style)
	theme.set_stylebox("embedded_border","Window",window_border())
	theme.set_stylebox("embedded_unfocused_border","Window",window_border())
	theme.set_color("title_color","Window",INK)
	theme.set_constant("title_height","Window",40)
	theme.set_constant("title_outline_size","Window",0)
	theme.set_constant("close_h_offset","Window",28)
	theme.set_constant("close_v_offset","Window",32)
	theme.set_font("title_font","Window",UiTypography.FONT)
	theme.set_font_size("title_font_size","Window",28)
	theme.set_icon("close","Window",ART["close"])
	theme.set_icon("close_pressed","Window",ART["close"])

static func apply_button(control: Button) -> void:
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		control.add_theme_stylebox_override(state,button(state))
	control.add_theme_stylebox_override("focus",focus())
	for key in ["font_color","font_hover_color","font_focus_color"]:
		control.add_theme_color_override(key,INK)
	for key in ["font_pressed_color","font_hover_pressed_color"]:
		control.add_theme_color_override(key,LIGHT)
	control.add_theme_color_override("font_disabled_color",MUTED)

static func select_tab(control: Button,selected: bool) -> void:
	# 현재 탭의 클릭 차단은 유지하되, 잠긴 기능과는 외형을 구분한다.
	control.disabled = selected
	control.add_theme_stylebox_override("disabled",patch("tab_selected" if selected else "tab_disabled"))
	control.add_theme_color_override("font_disabled_color",LIGHT if selected else MUTED)
