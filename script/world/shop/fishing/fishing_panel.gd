class_name FishingPanel
extends CanvasLayer
signal closed
var shade: ColorRect
var frame: PanelContainer
var root: Control
var body: VBoxContainer
var title: Label
var scroll: ScrollContainer
func _ready() -> void:
	layer = 25
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	shade = ColorRect.new()
	shade.color = Color(0,0,0,0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var panel := PanelContainer.new()
	frame = panel
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.88
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f1e5ce")
	style.border_color = Color("63513c")
	style.set_border_width_all(4)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	title = Label.new()
	title.add_theme_font_size_override("font_size",23)
	title.add_theme_color_override("font_color",Color("322f29"))
	column.add_child(title)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",10)
	scroll.add_child(body)
	var close := Button.new()
	close.text = "돌아가기 [Esc]"
	close.custom_minimum_size.y = 42
	close.pressed.connect(func(): root.hide(); closed.emit())
	column.add_child(close)
	root.hide()
func clear(caption: String) -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	shade.color.a = 0.6
	frame.anchor_left = 0.15
	frame.anchor_right = 0.85
	frame.anchor_top = 0.08
	frame.anchor_bottom = 0.88
	title.text = caption
	scroll.scroll_vertical = 0
	root.show()
func text(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color",Color("443c32"))
	label.add_theme_font_size_override("font_size",18)
	body.add_child(label)
	return label
func button(value: String, action: Callable, disabled: bool = false) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 44
	result.disabled = disabled
	result.pressed.connect(action)
	body.add_child(result)
	return result
