extends RefCounted

static func box(color: String) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color(color)
	result.content_margin_left = 0
	result.content_margin_right = 0
	result.content_margin_top = 0
	result.content_margin_bottom = 0
	return result

static func apply(button: Button) -> void:
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		var color: String = {"normal":"d8b47c","hover":"edcc94","pressed":"88aaa0","hover_pressed":"9bbbb0","disabled":"c5b290","focus":"e5c48b"}[state]
		button.add_theme_stylebox_override(state,box(color))
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func content(button: Button) -> void:
	apply(button)
	var icon: TextureRect = button.get_node("IconRect")
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 8
	icon.offset_top = 6
	icon.offset_right = -8
	icon.offset_bottom = -10
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count: Label = button.get_node("CountLabel")
	count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	count.offset_left = 4
	count.offset_top = 4
	count.offset_right = -5
	count.offset_bottom = -3
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.add_theme_font_size_override("font_size",16)
	count.add_theme_color_override("font_color",Color("fff4d6"))
	count.add_theme_color_override("font_outline_color",Color("593e28"))
	count.add_theme_constant_override("outline_size",3)
