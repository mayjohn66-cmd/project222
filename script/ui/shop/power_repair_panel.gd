class_name PowerRepairPanel
extends AcceptDialog
signal repair_requested
var info: Label
var submit: Button
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	title = "계산대 개조 맡기기"
	ok_button_text = "돌아가기"
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f5e5c9")
	paper.set_content_margin_all(14)
	add_theme_stylebox_override("panel", paper)
	add_theme_color_override("title_color", Color("51382d"))
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		get_ok_button().add_theme_color_override(state, Color("51382d"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(440, 210)
	info.add_theme_color_override("font_color", Color("51382d"))
	column.add_child(info)
	submit = Button.new()
	submit.text = "재료와 개조비를 건네고 맡기기"
	submit.pressed.connect(func() -> void: repair_requested.emit())
	column.add_child(submit)
func display() -> void:
	info.text = PowerRepairFlow.information()
	submit.disabled = not PowerRepairFlow.blocked_reason().is_empty()
	popup_centered(Vector2i(490, 355))
