extends Control
## 실제 공용 테마의 옵션 팝업·체크·선택 상태와 글씨 대비를 검증한다.
var checks := 0
var failures := 0
var choices: OptionButton
var check_button: CheckButton
var tabs: TabBar
var line: LineEdit
var selected_id := -1

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func contrast(a: Color,b: Color) -> float:
	var x := a.srgb_to_linear().get_luminance()
	var y := b.srgb_to_linear().get_luminance()
	return (maxf(x,y)+0.05)/(minf(x,y)+0.05)

func frames(count: int = 8) -> void:
	for index in count: await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = load("res://art/ui/pixel_theme/pixel_ui_theme.tres")
	_build()
	run.call_deferred()

func _button(parent: Control,text: String,disabled: bool = false,toggle: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260,42)
	button.disabled = disabled
	button.toggle_mode = toggle
	button.button_pressed = toggle
	parent.add_child(button)
	return button

func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(78,56)
	panel.size = Vector2(996,536)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	panel.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 292
	left.add_theme_constant_override("separation",10)
	row.add_child(left)
	var title := Label.new()
	title.text = "종이색 · 갈색 조작 UI"
	left.add_child(title)
	_button(left,"기본 버튼")
	_button(left,"선택된 버튼",false,true)
	_button(left,"비활성 버튼",true)
	check_button = CheckButton.new()
	check_button.text = "자동 정리"
	check_button.custom_minimum_size.y = 42
	left.add_child(check_button)
	for caption in ["체크 항목","비활성 체크"]:
		var box := CheckBox.new()
		box.text = caption
		box.button_pressed = true
		box.disabled = caption.begins_with("비활성")
		left.add_child(box)
	choices = OptionButton.new()
	choices.custom_minimum_size.y = 42
	choices.add_item("물품 정렬",10)
	choices.add_item("이름순",11)
	choices.add_item("가격순",12)
	choices.add_item("사용할 수 없는 옵션",13)
	choices.set_item_disabled(3,true)
	choices.item_selected.connect(func(index: int) -> void: selected_id = choices.get_item_id(index))
	left.add_child(choices)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation",12)
	row.add_child(right)
	line = LineEdit.new()
	line.placeholder_text = "이름을 입력하세요"
	line.custom_minimum_size.y = 44
	right.add_child(line)
	var readonly := LineEdit.new()
	readonly.text = "읽기 전용 입력란"
	readonly.editable = false
	readonly.custom_minimum_size.y = 44
	right.add_child(readonly)
	tabs = TabBar.new()
	for caption in ["기본 정보","상세 정보","잠긴 탭"]: tabs.add_tab(caption)
	tabs.set_tab_disabled(2,true)
	right.add_child(tabs)
	var text := TextEdit.new()
	text.text = "기본 글씨와 선택된 글씨 모두 갈색입니다.\n선택 항목은 밝기와 테두리로 구분합니다."
	text.custom_minimum_size.y = 110
	right.add_child(text)
	var tree := Tree.new()
	tree.custom_minimum_size.y = 115
	right.add_child(tree)
	var root := tree.create_item()
	root.set_text(0,"펼칠 수 있는 항목")
	var child := tree.create_item(root)
	child.set_cell_mode(0,TreeItem.CELL_MODE_CHECK)
	child.set_text(0,"체크 항목")
	child.set_checked(0,true)
	var slider := HSlider.new()
	slider.value = 40
	right.add_child(slider)
	var progress := ProgressBar.new()
	progress.value = 50
	progress.custom_minimum_size.y = 28
	right.add_child(progress)

func run() -> void:
	check(OS.get_user_data_dir().contains("foodbag_checks"),"isolated UI saves")
	await frames()
	for type in ["Button","CheckBox","CheckButton","MenuButton","OptionButton","PopupMenu","Tree","ItemList"]:
		var foreground := theme.get_color("font_color",type)
		check(contrast(foreground,InteractionUiStyle.PAPER)>=4.5,"readable normal text "+type)
		check(contrast(theme.get_color("font_disabled_color",type),InteractionUiStyle.tone(InteractionUiStyle.PAPER,0.95))>=4.5,"readable disabled text "+type)
	for key in ["font_selected_color","font_unselected_color","font_disabled_color"]:
		check(contrast(theme.get_color(key,"TabBar"),InteractionUiStyle.PAPER)>=4.5,"readable tab "+key)
	var normal = theme.get_stylebox("normal","Button")
	var selected = theme.get_stylebox("pressed","Button")
	check(normal is StyleBoxFlat and selected is StyleBoxFlat,"stable code-native button geometry")
	check(normal.bg_color.is_equal_approx(selected.bg_color),"selected button preserves paper base")
	check(selected.border_width_left > normal.border_width_left,"selected button has visible border")
	for type in ["LineEdit","TextEdit"]:
		check(contrast(theme.get_color("font_color",type),theme.get_stylebox("normal",type).bg_color)>=4.5,"readable input "+type)
	check(contrast(theme.get_color("font_uneditable_color","LineEdit"),theme.get_stylebox("read_only","LineEdit").bg_color)>=4.5,"read-only input stays readable")
	line.grab_focus()
	for character in "가게":
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = character.unicode_at(0)
		Input.parse_input_event(key)
		await frames(1)
	check(line.text == "가게","real keyboard input")
	var rect := check_button.get_global_rect()
	for down in [true,false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = rect.get_center()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = down
		get_viewport().push_input(mouse,true)
	await frames()
	check(check_button.button_pressed,"real check-button click")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0]+"-controls.png")
	choices.show_popup()
	await frames()
	var popup := choices.get_popup()
	check(popup.visible,"actual option popup visible")
	check(contrast(popup.get_theme_color("font_color"),InteractionUiStyle.PAPER)>=4.5,"popup normal text readable")
	check(contrast(popup.get_theme_color("font_disabled_color"),InteractionUiStyle.PAPER)>=4.5,"popup disabled text readable")
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0]+"-popup.png")
	for code in [KEY_DOWN,KEY_DOWN,KEY_ENTER]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = true
		Input.parse_input_event(event)
		await frames(2)
	check(selected_id >= 0 and selected_id != 13,"keyboard selects enabled popup item")
	print("PLAIN_UI checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)
