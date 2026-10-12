extends RefCounted

static func paper() -> StyleBoxFlat:
 var s := StyleBoxFlat.new()
 s.bg_color = Color("f3d6a0")
 s.border_color = Color("8f623e")
 s.set_border_width_all(2)
 s.set_content_margin_all(12)
 s.shadow_color = Color(0.15,0.09,0.04,0.22)
 s.shadow_size = 3
 return s

static func button(b: Button) -> void:
 for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
  var s := StyleBoxFlat.new()
  s.bg_color = Color({"normal":"e6c18a","hover":"f9dfac","pressed":"aa7547","hover_pressed":"aa7547","disabled":"cdbb9a","focus":"00000000"}[state])
  s.set_content_margin_all(8)
  if state == "focus":
   s.border_color = Color("a26a3b")
   s.set_border_width_all(1)
  b.add_theme_stylebox_override(state,s)
 for state in ["font_color","font_hover_color","font_focus_color"]:
  b.add_theme_color_override(state,Color("513923"))
 for state in ["font_pressed_color","font_hover_pressed_color"]:
  b.add_theme_color_override(state,Color("fff6df"))
 b.add_theme_font_size_override("font_size",UiTypography.size(18))
