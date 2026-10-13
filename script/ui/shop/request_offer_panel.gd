class_name RequestOfferPanel
extends CanvasLayer
## 한 가지 부탁을 듣고 답한다. 수락은 재료 전달과 별개의 행동이다.
signal answered(accepted: bool)
var root: PanelContainer
var backdrop: ColorRect
var title_label: Label
var description: Label
var accept_button: Button
var decline_button: Button
var scroll: ScrollContainer

func _ready() -> void:
	layer = 26
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = InteractionUiStyle.tone(InteractionUiStyle.INK, 0.5, 0.35)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	root = PanelContainer.new()
	root.theme = preload("res://art/ui/pixel_theme/pixel_ui_theme.tres")
	add_child(root)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	title_label = _label(UiTypography.DEFAULT_SIZE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)
	column.add_child(HSeparator.new())
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	description = _label(UiTypography.DEFAULT_SIZE)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(description)
	var responses := HBoxContainer.new()
	responses.add_theme_constant_override("separation", 16)
	column.add_child(responses)
	accept_button = _button("수락")
	decline_button = _button("거절")
	responses.add_child(accept_button)
	responses.add_child(decline_button)
	accept_button.pressed.connect(func(): _answer(true))
	decline_button.pressed.connect(func(): _answer(false))
	get_viewport().size_changed.connect(_fit_screen)
	root.minimum_size_changed.connect(func(): call_deferred("_fit_screen"))
	dismiss()

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", InteractionUiStyle.INK)
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", UiTypography.DEFAULT_SIZE)
	InteractionUiStyle.apply_button(button)
	return button

func display(proposal: Dictionary) -> void:
	title_label.text = str(proposal.get("title", "주민의 부탁"))
	description.text = RequestProposalData.description(proposal)
	scroll.scroll_vertical = 0
	root.show()
	backdrop.show()
	_fit_screen()
	call_deferred("_fit_screen")
	decline_button.grab_focus()

func _fit_screen() -> void:
	if not is_instance_valid(root): return
	var screen := get_viewport().get_visible_rect().size
	root.size = Vector2(minf(640, screen.x - 48), minf(460, screen.y - 48))
	root.position = (screen - root.size) * 0.5

func dismiss() -> void:
	if is_instance_valid(root): root.hide()
	if is_instance_valid(backdrop): backdrop.hide()

func _answer(accepted: bool) -> void:
	if not root.visible: return
	dismiss()
	answered.emit(accepted)

func _input(event: InputEvent) -> void:
	if root.visible and not event.is_echo() and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		_answer(false)
