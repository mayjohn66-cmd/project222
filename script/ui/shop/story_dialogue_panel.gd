class_name StoryDialoguePanel
extends CanvasLayer


# 스토리 NPC와의 대화 창. 왼쪽에 NPC 그림, 오른쪽에 이름과 대사.
# E 키나 마우스 클릭으로 다음 줄로 넘기고, 마지막 줄 뒤에 finished 신호를 보낸다.

signal finished

var lines: Array[String] = []
var line_index: int = 0
var open: bool = false
var typing_tween: Tween = null

var root: Control
var portrait: TextureRect
# 줄 맨 앞에 "*" 가 붙으면 말이 아니라 서술(독백·행동 묘사)이다: 이름 칸 없이 괄호로 감싼 흐린 글씨로 나온다. 붙지 않은 줄은 화자가 소리 내어 하는 말이다.
const NARRATION_MARK := "*"   # 표시 해석은 DialogueMarks 가 한다(서술 *, 표정 {이름})
const SPEECH_COLOR := Color(0.96, 0.93, 0.85)
const NARRATION_COLOR := Color(0.72, 0.78, 0.86)
var _speaker: String = ""
var _speaker_is_player: bool = false
var _base_portrait: Texture2D
var name_label: Label
var text_label: Label
var hint_label: Label
var hint_tween: Tween = null
# 대사 한 줄을 다 읽고 다음 줄로 넘어가기 직전에 부르는 동작(예: 주인공이 걸어간다). 기다릴 수 있다. 비워 두면 바로 넘어간다.
# 인자는 방금 읽은 줄 번호(0부터).
var beat_handler: Callable = Callable()
var _beat_busy: bool = false

const HINT_HOLDER_HEIGHT := 44.0   # 움찔거리는 범위와 테두리 사이 여유까지 포함
const HINT_MARGIN_RIGHT := 22.0    # 오른쪽 테두리에서 띄우는 거리
const HINT_REST_Y := 6.0
const HINT_BOB_PIXELS := 5.0      # ▼가 아래로 움찔하는 거리
const HINT_BOB_SECONDS := 0.45
const PLAYER_SPEAKER := "나"      # 이 이름으로 시작한 대화는 플레이어 닉네임으로 보여 준다


func _ready() -> void:
	layer = 30

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40.0
	panel.offset_right = -40.0
	panel.offset_top = -250.0
	panel.offset_bottom = -30.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.12, 0.08, 0.97)
	style.border_color = Color(0.85, 0.65, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(160, 190)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	row.add_child(column)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(0.97, 0.85, 0.55))
	column.add_child(name_label)

	text_label = Label.new()
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 21)
	text_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.85))
	column.add_child(text_label)

	# 컨테이너 안에서는 위치를 움직일 수 없어서, 고정 높이 칸 안에 표시를 넣고 그 칸 안에서 위아래로 움직인다.
	var hint_holder := Control.new()
	hint_holder.custom_minimum_size = Vector2(0, HINT_HOLDER_HEIGHT)
	column.add_child(hint_holder)

	hint_label = Label.new()
	hint_label.text = "▼"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.3))
	# 오른쪽 위에 붙이고, 폭은 글자 크기대로 둔다(오른쪽 여백만큼 안쪽으로).
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint_label.offset_right = -HINT_MARGIN_RIGHT
	_show_hint(false)
	hint_holder.add_child(hint_label)


func start(
	npc_name: String,
	portrait_texture: Texture2D,
	new_lines: Array[String]
) -> void:
	if new_lines.is_empty():
		push_warning("[스토리] 대사가 없는 NPC 장면을 건너뜁니다.")
		finished.emit()
		return

	lines = new_lines
	line_index = 0
	var is_player: bool = npc_name == PLAYER_SPEAKER
	_speaker_is_player = is_player
	_speaker = PlayerProgress.display_player_name() if is_player else npc_name
	name_label.text = _speaker
	portrait_texture = PlayerPortraits.find() if is_player else NpcPortraits.resolve(_speaker, portrait_texture)
	_base_portrait = portrait_texture
	portrait.texture = portrait_texture
	portrait.visible = portrait_texture != null
	root.visible = true
	open = true
	_show_line()


func _show_line() -> void:
	var marks: Dictionary = DialogueMarks.parse(lines[line_index])
	var narration: bool = marks["narration"]
	var line: String = marks["text"]
	# 서술은 행동 묘사처럼 괄호로 감싸 이름 칸 없이 흐리게 보여 준다: (뺨을 꼬집어 봤다.)
	text_label.text = "(%s)" % line if narration else line
	# ">" 표시 줄은 NPC 장면 안에서도 주인공이 말한다.
	var player_line: bool = _speaker_is_player or bool(marks.get("player", false))
	if player_line:
		# 표정 표시가 없는 줄은 기본 표정으로 돌아간다(앞 줄 표정이 남지 않게).
		var expression: String = marks["expression"] if not str(marks["expression"]).is_empty() else PlayerPortraits.DEFAULT_EXPRESSION
		portrait.texture = PlayerPortraits.find(expression)
		portrait.visible = portrait.texture != null
	else:
		# NPC: 표정 그림이 있으면 쓰고, 없거나 표시가 없으면 기본 초상화.
		var npc_face: Texture2D = NpcPortraits.find_expression(_speaker, marks["expression"])
		portrait.texture = npc_face if npc_face != null else _base_portrait
		portrait.visible = portrait.texture != null
	name_label.visible = not narration
	name_label.text = PlayerProgress.display_player_name() if player_line else _speaker
	text_label.add_theme_color_override("font_color", NARRATION_COLOR if narration else SPEECH_COLOR)
	text_label.visible_ratio = 0.0
	_show_hint(false)

	if typing_tween != null:
		typing_tween.kill()

	typing_tween = create_tween()
	typing_tween.tween_property(
		text_label,
		"visible_ratio",
		1.0,
		maxf(0.2, 0.025 * text_label.text.length())
	)
	typing_tween.tween_callback(
		func() -> void:
			_show_hint(true)
	)


# 대사가 다 나오면 ▼가 아래로 움찔거려 "다음으로 넘기라"고 알려 준다.
func _show_hint(shown: bool) -> void:
	if hint_tween != null:
		hint_tween.kill()
		hint_tween = null

	hint_label.visible = shown
	hint_label.position.y = HINT_REST_Y

	if not shown:
		return

	hint_tween = create_tween().set_loops()
	hint_tween.tween_property(hint_label, "position:y", HINT_REST_Y + HINT_BOB_PIXELS, HINT_BOB_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hint_tween.tween_property(hint_label, "position:y", HINT_REST_Y, HINT_BOB_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _advance() -> void:
	if _beat_busy:
		return

	# 글자가 나오는 중이면 먼저 전부 보여 준다.
	if text_label.visible_ratio < 1.0:
		if typing_tween != null:
			typing_tween.kill()

		text_label.visible_ratio = 1.0
		_show_hint(true)
		return

	var read_index: int = line_index
	line_index += 1

	if line_index >= lines.size():
		close()
		return

	if beat_handler.is_valid():
		_beat_busy = true
		_show_hint(false)
		root.visible = false  # 걷는 동안에는 대사창을 잠깐 숨긴다
		await beat_handler.call(read_index)
		_beat_busy = false

		if not open:
			return

		root.visible = true

	_show_line()


func close() -> void:
	open = false
	_beat_busy = false
	root.visible = false

	if typing_tween != null:
		typing_tween.kill()

	_show_hint(false)
	finished.emit()


func _input(event: InputEvent) -> void:
	if not open:
		return

	var pressed: bool = (
		event.is_action_pressed("interact")
		or (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		)
	)

	if event is InputEventKey and event.is_echo():
		return

	if pressed:
		get_viewport().set_input_as_handled()
		_advance()
