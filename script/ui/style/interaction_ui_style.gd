class_name InteractionUiStyle
extends RefCounted
## 전체 배경과 전용 연출을 보존하는 종이·갈색 조작부.
const PAPER := Color("#F3E3BD")
const INK := Color("#4A3024")
const MUTED := INK
const SELECTED := INK
const NEUTRAL := PAPER
const LIGHT := PAPER
const ICONS := {
	"check_off": preload("res://art/ui/controls/plain_icons/check_off.svg"),
	"check_on": preload("res://art/ui/controls/plain_icons/check_on.svg"),
	"check_off_disabled": preload("res://art/ui/controls/plain_icons/check_off_disabled.svg"),
	"check_on_disabled": preload("res://art/ui/controls/plain_icons/check_on_disabled.svg"),
	"radio_off": preload("res://art/ui/controls/plain_icons/radio_off.svg"),
	"radio_on": preload("res://art/ui/controls/plain_icons/radio_on.svg"),
	"radio_off_disabled": preload("res://art/ui/controls/plain_icons/radio_off_disabled.svg"),
	"radio_on_disabled": preload("res://art/ui/controls/plain_icons/radio_on_disabled.svg"),
	"toggle_off": preload("res://art/ui/controls/plain_icons/toggle_off.svg"),
	"toggle_on": preload("res://art/ui/controls/plain_icons/toggle_on.svg"),
	"toggle_off_disabled": preload("res://art/ui/controls/plain_icons/toggle_off_disabled.svg"),
	"toggle_on_disabled": preload("res://art/ui/controls/plain_icons/toggle_on_disabled.svg"),
	"close": preload("res://art/ui/controls/plain_icons/close.svg"),
	"up": preload("res://art/ui/controls/plain_icons/up.svg"),
	"down": preload("res://art/ui/controls/plain_icons/down.svg"),
	"left": preload("res://art/ui/controls/plain_icons/left.svg"),
	"right": preload("res://art/ui/controls/plain_icons/right.svg"),
	"spin": preload("res://art/ui/controls/plain_icons/spin.svg"),
	"knob": preload("res://art/ui/controls/plain_icons/knob.svg"),
	"knob_disabled": preload("res://art/ui/controls/plain_icons/knob_disabled.svg"),
	"indeterminate": preload("res://art/ui/controls/plain_icons/indeterminate.svg"),
	"indeterminate_disabled": preload("res://art/ui/controls/plain_icons/indeterminate_disabled.svg")
}

static func tone(base: Color,brightness: float = 1.0,alpha: float = 1.0) -> Color:
	return Color.from_hsv(base.h,base.s,clampf(base.v*brightness,0.0,1.0),alpha)

static func surface(fill: Color,edge: Color,border: int = 1,pad: Vector4 = Vector4(12,7,12,7)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border)
	style.content_margin_left = pad.x
	style.content_margin_top = pad.y
	style.content_margin_right = pad.z
	style.content_margin_bottom = pad.w
	style.anti_aliasing = false
	return style

static func patch(name: String,pad: Vector4 = Vector4(12,7,12,7)) -> StyleBoxFlat:
	var disabled := name.ends_with("disabled") or name.ends_with("readonly")
	var selected := name.ends_with("selected") or name.ends_with("focus")
	var brightness := 1.04 if name.ends_with("hover") or name.begins_with("input") else 1.0
	if disabled: brightness = 0.95
	var style := surface(tone(PAPER,brightness),tone(INK,1.0,0.48 if disabled else 0.8),2 if selected else 1,pad)
	if name == "tab_selected": style.border_width_bottom = 3
	return style

static func button(state: String) -> StyleBoxFlat:
	var image := "selected" if state in ["pressed","hover_pressed"] else state
	return patch("button_"+image)

static func focus() -> StyleBoxFlat:
	return surface(tone(PAPER,1.0,0.0),INK,2,Vector4.ZERO)

static func window_border() -> StyleBoxFlat:
	var style := surface(tone(PAPER,0.96),INK,2,Vector4.ZERO)
	style.expand_margin_top = 40
	style.expand_margin_left = 2
	style.expand_margin_right = 2
	style.expand_margin_bottom = 2
	style.shadow_color = tone(INK,0.65,0.22)
	style.shadow_size = 4
	return style

static func apply(theme: Theme) -> void:
	for type in ["Label","RichTextLabel"]: theme.set_color("font_color",type,INK)
	theme.set_color("default_color","RichTextLabel",INK)
	for type in ["Button","OptionButton","CheckBox","CheckButton","MenuButton","LinkButton"]:
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			theme.set_stylebox(state,type,button(state))
		theme.set_stylebox("focus",type,focus())
		for key in ["font_color","font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color"]:
			theme.set_color(key,type,INK)
		theme.set_color("font_disabled_color",type,tone(INK,1.35))
	for type in ["LineEdit","TextEdit"]:
		for pair in [["normal","input_normal"],["focus","input_focus"],["read_only","input_readonly"]]:
			theme.set_stylebox(pair[0],type,patch(pair[1],Vector4(10,7,10,7)))
		for key in ["font_color","font_selected_color","font_readonly_color","font_uneditable_color","caret_color"]:
			theme.set_color(key,type,INK)
		for key in ["font_placeholder_color","placeholder_color"]:
			theme.set_color(key,type,tone(INK,1.35))
		theme.set_color("selection_color",type,tone(INK,1.0,0.18))
		theme.set_icon("clear",type,ICONS["close"])
	for type in ["TabBar","TabContainer"]:
		for pair in [["tab_unselected","normal"],["tab_hovered","hover"],["tab_selected","selected"],["tab_disabled","disabled"]]:
			theme.set_stylebox(pair[0],type,patch("tab_"+pair[1]))
		theme.set_stylebox("tab_focus",type,focus())
		for key in ["font_selected_color","font_unselected_color","font_hovered_color","font_hovered_selected_color","font_focus_color"]:
			theme.set_color(key,type,INK)
		theme.set_color("font_disabled_color",type,tone(INK,1.35))
		theme.set_icon("close",type,ICONS["close"])
		for key in ["decrement","decrement_highlight"]: theme.set_icon(key,type,ICONS["left"])
		for key in ["increment","increment_highlight"]: theme.set_icon(key,type,ICONS["right"])
		theme.set_icon("drop_mark",type,ICONS["down"])
	for type in ["PopupMenu","Tree","ItemList"]:
		for key in ["font_color","font_hover_color","font_selected_color","font_accelerator_color","font_accelerator_hover_color","font_separator_color"]:
			theme.set_color(key,type,INK)
		theme.set_color("font_disabled_color",type,tone(INK,1.35))
		if type != "PopupMenu" or not theme.has_stylebox("panel",type):
			theme.set_stylebox("panel",type,patch("input_normal",Vector4(8,8,8,8)))
		for key in ["hover","selected","selected_focus","cursor","cursor_unfocused"]:
			theme.set_stylebox(key,type,patch("tab_selected",Vector4(8,5,8,5)))
		for key in ["separator","labeled_separator_left","labeled_separator_right"]:
			theme.set_stylebox(key,type,surface(tone(PAPER,1,0),tone(INK,1,0.3),1,Vector4(0,1,0,1)))
	for type in ["CheckBox","PopupMenu","Tree"]:
		for pair in [["checked","check_on"],["unchecked","check_off"],["checked_disabled","check_on_disabled"],["unchecked_disabled","check_off_disabled"],["radio_checked","radio_on"],["radio_unchecked","radio_off"],["radio_checked_disabled","radio_on_disabled"],["radio_unchecked_disabled","radio_off_disabled"],["indeterminate","indeterminate"],["indeterminate_disabled","indeterminate_disabled"]]:
			theme.set_icon(pair[0],type,ICONS[pair[1]])
	for pair in [["checked","toggle_on"],["unchecked","toggle_off"],["checked_disabled","toggle_on_disabled"],["unchecked_disabled","toggle_off_disabled"]]:
		theme.set_icon(pair[0],"CheckButton",ICONS[pair[1]])
	theme.set_icon("arrow","OptionButton",ICONS["down"])
	theme.set_icon("submenu","PopupMenu",ICONS["right"])
	theme.set_icon("submenu_mirrored","PopupMenu",ICONS["left"])
	theme.set_icon("arrow","Tree",ICONS["down"])
	theme.set_icon("arrow_collapsed","Tree",ICONS["right"])
	theme.set_icon("arrow_collapsed_mirrored","Tree",ICONS["left"])
	theme.set_icon("select_arrow","Tree",ICONS["right"])
	theme.set_icon("updown","Tree",ICONS["spin"])
	theme.set_icon("updown","SpinBox",ICONS["spin"])
	for type in ["VScrollBar","HScrollBar","ScrollBar"]:
		for key in ["scroll","scroll_focus"]: theme.set_stylebox(key,type,surface(tone(PAPER,0.96),tone(INK,1,0.35),1,Vector4(5,5,5,5)))
		for key in ["grabber","grabber_highlight","grabber_pressed"]:
			theme.set_stylebox(key,type,surface(tone(PAPER,0.87 if key == "grabber" else 0.95),INK,1,Vector4(6,6,6,6)))
		for key in ["decrement","decrement_disabled","decrement_highlight","decrement_pressed"]:
			theme.set_icon(key,type,ICONS["up" if type == "VScrollBar" else "left"])
		for key in ["increment","increment_disabled","increment_highlight","increment_pressed"]:
			theme.set_icon(key,type,ICONS["down" if type == "VScrollBar" else "right"])
	for type in ["Slider","HSlider","VSlider"]:
		theme.set_stylebox("slider",type,surface(tone(PAPER,0.96),tone(INK,1,0.6),1,Vector4(0,3,0,3)))
		for key in ["grabber_area","grabber_area_highlight"]:
			theme.set_stylebox(key,type,surface(tone(PAPER,0.84),INK,1,Vector4(0,3,0,3)))
		theme.set_icon("grabber",type,ICONS["knob"])
		theme.set_icon("grabber_highlight",type,ICONS["knob"])
		theme.set_icon("grabber_disabled",type,ICONS["knob_disabled"])
	theme.set_stylebox("background","ProgressBar",surface(PAPER,INK,1,Vector4(0,0,0,0)))
	theme.set_stylebox("fill","ProgressBar",surface(tone(PAPER,0.82),INK,1,Vector4(0,0,0,0)))
	theme.set_color("font_color","ProgressBar",INK)
	theme.set_color("font_outline_color","ProgressBar",PAPER)
	theme.set_constant("outline_size","ProgressBar",1)
	theme.set_stylebox("embedded_border","Window",window_border())
	theme.set_stylebox("embedded_unfocused_border","Window",window_border())
	theme.set_color("title_color","Window",INK)
	theme.set_constant("title_height","Window",40)
	theme.set_constant("title_outline_size","Window",0)
	theme.set_constant("close_h_offset","Window",28)
	theme.set_constant("close_v_offset","Window",32)
	theme.set_font("title_font","Window",UiTypography.FONT)
	theme.set_font_size("title_font_size","Window",28)
	theme.set_icon("close","Window",ICONS["close"])
	theme.set_icon("close_pressed","Window",ICONS["close"])
	theme.set_icon("close","CloseAction",ICONS["close"])

static func apply_button(control: Button) -> void:
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		control.add_theme_stylebox_override(state,button(state))
	control.add_theme_stylebox_override("focus",focus())
	for key in ["font_color","font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color"]:
		control.add_theme_color_override(key,INK)
	control.add_theme_color_override("font_disabled_color",tone(INK,1.35))

static func select_tab(control: Button,selected: bool) -> void:
	# 현재 쪽의 클릭 차단과 전용 책갈피 연출은 유지한다.
	control.disabled = selected
	control.add_theme_stylebox_override("disabled",patch("tab_selected" if selected else "tab_disabled"))
	control.add_theme_color_override("font_disabled_color",INK if selected else tone(INK,1.35))
