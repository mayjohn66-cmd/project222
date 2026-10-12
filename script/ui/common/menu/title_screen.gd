extends Control

@onready var new_game_button: Button = (
	$CenterContainer/VBoxContainer/NewGameButton
)

@onready var continue_button: Button = (
	$CenterContainer/VBoxContainer/ContinueButton
)

@onready var status_label: Label = (
	$CenterContainer/VBoxContainer/StatusLabel
)

@onready var delete_save_button: Button = (
	$CenterContainer/VBoxContainer/DeleteSaveButton
)

@onready var delete_save_dialog: ConfirmationDialog = (
	$DeleteSaveDialog
)

@onready var new_game_dialog: ConfirmationDialog = (
	$NewGameDialog
)

var entering_game: bool = false

@onready var load_slot_panel: PanelContainer = (
	$LoadSlotPanel
)

@onready var auto_save_button: Button = (
	$LoadSlotPanel/LoadSlotVBox/AutoSaveButton
)

@onready var load_slot_1_button: Button = (
	$LoadSlotPanel/LoadSlotVBox/LoadSlot1Button
)

@onready var load_slot_2_button: Button = (
	$LoadSlotPanel/LoadSlotVBox/LoadSlot2Button
)

@onready var load_slot_close_button: Button = (
	$LoadSlotPanel/LoadSlotVBox/LoadSlotCloseButton
)

@onready var title_menu_center: CenterContainer = (
	$CenterContainer
)

@onready var load_slot_title_label: Label = (
	$LoadSlotPanel/LoadSlotVBox/LoadSlotTitleLabel
)

var slot_panel_mode: String = "load"
var pending_delete_path: String = ""
var pending_delete_slot_name: String = ""



func _ready() -> void:
	new_game_button.pressed.connect(
		_on_new_game_pressed
	)

	continue_button.pressed.connect(
		_on_continue_pressed
	)

	delete_save_button.pressed.connect(
		_on_delete_save_pressed
	)

	delete_save_dialog.confirmed.connect(
		_on_delete_save_confirmed
	)

	delete_save_dialog.dialog_text = (
		"저장된 진행 기록을 삭제하시겠습니까?"
		+ "\n삭제한 기록은 되돌릴 수 없습니다."
	)

	delete_save_dialog.get_ok_button().text = "삭제"
	delete_save_dialog.get_cancel_button().text = "취소"

	new_game_dialog.title = "새 게임 시작"

	new_game_dialog.dialog_text = (
		"기존 저장 기록이 있습니다."
		+ "\n새 게임에서 저장하면 기존 기록을 덮어씁니다."
		+ "\n\n새 게임을 시작하시겠습니까?"
	)

	new_game_dialog.get_ok_button().text = "새 게임 시작"
	new_game_dialog.get_cancel_button().text = "취소"

	new_game_dialog.confirmed.connect(
		_ask_nickname
	)

	_build_nickname_dialog()

	refresh_continue_button()

	load_slot_panel.visible = false

	auto_save_button.pressed.connect(
		_on_slot_entry_pressed.bind(
			GameState.SAVE_PATH,
			"자동 저장"
		)
	)

	load_slot_1_button.pressed.connect(
		_on_slot_entry_pressed.bind(
			str(GameConfig.SAVE_SLOT_PATHS[0]),
			"세이브 슬롯 1"
		)
	)

	load_slot_2_button.pressed.connect(
		_on_slot_entry_pressed.bind(
			str(GameConfig.SAVE_SLOT_PATHS[1]),
			"세이브 슬롯 2"
		)
	)

	load_slot_close_button.pressed.connect(
		close_load_slot_panel
	)


func refresh_continue_button() -> void:
	status_label.text = ""

	_refresh_load_slot_buttons()

	continue_button.disabled = (
		not _has_any_valid_save()
	)

	# 기존 삭제 버튼은 일단 자동 저장만 삭제
	delete_save_button.disabled = (
		not _has_any_save_file()
	)


func _on_new_game_pressed() -> void:
	if entering_game:
		return

	if _has_any_save_file():
		new_game_dialog.popup_centered()
		return

	_ask_nickname()


func _on_continue_pressed() -> void:
	if entering_game:
		return

	slot_panel_mode = "load"
	load_slot_title_label.text = "불러오기"

	_refresh_load_slot_buttons()

	title_menu_center.visible = false
	load_slot_panel.visible = true
	load_slot_panel.z_index = 200


func enter_store() -> void:
	entering_game = true
	new_game_button.disabled = true
	continue_button.disabled = true

	var scene_error: Error = (
		get_tree().change_scene_to_file(
			GameConfig.MAIN_SCENE_PATH
		)
	)

	if scene_error == OK:
		return

	entering_game = false
	new_game_button.disabled = false

	refresh_continue_button()
	status_label.text = "편의점 화면을 열지 못했습니다."

	push_error(
		"[시작 화면] 씬 전환 실패: "
		+ str(scene_error)
	)

func enter_expedition() -> void:
	entering_game = true

	new_game_button.disabled = true
	continue_button.disabled = true

	var scene_error: Error = (
		get_tree().change_scene_to_file(
			GameConfig.EXPEDITION_SCENE_PATH
		)
	)

	if scene_error == OK:
		return

	entering_game = false
	new_game_button.disabled = false

	refresh_continue_button()

	status_label.text = (
		"원정 화면을 열지 못했습니다."
	)

	push_error(
		"[시작 화면] 원정 씬 전환 실패: "
		+ str(scene_error)
	)


func _on_delete_save_pressed() -> void:
	if entering_game:
		return

	if not _has_any_save_file():
		refresh_continue_button()
		return

	slot_panel_mode = "delete"
	load_slot_title_label.text = "저장 기록 삭제"

	_refresh_load_slot_buttons()

	title_menu_center.visible = false
	load_slot_panel.visible = true
	load_slot_panel.z_index = 200


func _on_delete_save_confirmed() -> void:
	if entering_game:
		return

	if pending_delete_path.is_empty():
		return

	var global_path: String = (
		ProjectSettings.globalize_path(
			pending_delete_path
		)
	)

	var delete_error: Error = (
		DirAccess.remove_absolute(
			global_path
		)
	)

	var deleted_slot_name: String = (
		pending_delete_slot_name
	)

	pending_delete_path = ""
	pending_delete_slot_name = ""

	if delete_error != OK:
		status_label.text = (
			"저장 기록을 삭제하지 못했습니다."
		)
		return

	status_label.text = (
		deleted_slot_name
		+ " 데이터를 삭제했습니다."
	)

	refresh_continue_button()
	_refresh_load_slot_buttons()

# ---------------------------------------------------------------- 닉네임(새 게임 시작 전에 짓는다)

var nickname_dialog: ConfirmationDialog
var nickname_edit: LineEdit
var gender_preview: TextureRect
var chosen_gender: String = PlayerProgress.DEFAULT_GENDER
const GENDER_LABELS := {"male": "남성 점장", "female": "여성 점장"}


func _build_nickname_dialog() -> void:
	nickname_dialog = ConfirmationDialog.new()
	nickname_dialog.title = "이름 짓기"
	nickname_dialog.min_size = Vector2i(480, 460)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("fff5df")
	paper.border_color = Color("9f7444")
	paper.set_border_width_all(2)
	paper.set_content_margin_all(20)
	nickname_dialog.add_theme_stylebox_override("panel", paper)
	nickname_dialog.get_ok_button().text = "이 이름으로 시작"
	nickname_dialog.get_ok_button().custom_minimum_size = Vector2(180,42)
	nickname_dialog.get_cancel_button().text = "취소"
	nickname_dialog.get_cancel_button().custom_minimum_size = Vector2(96,42)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	var hint := Label.new()
	hint.text = "이세계의 편의점을 이끌 점장의 이름을 지어 주세요.\n영업 일지(관리 창) 표지에 적힙니다."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 420
	hint.add_theme_color_override("font_color", Color("51382d"))
	box.add_child(hint)
	nickname_edit = LineEdit.new()
	nickname_edit.max_length = PlayerProgress.PLAYER_NAME_MAX
	nickname_edit.placeholder_text = "이름 (최대 %d자)" % PlayerProgress.PLAYER_NAME_MAX
	nickname_edit.custom_minimum_size = Vector2(420,44)
	nickname_edit.text_changed.connect(_on_nickname_changed)
	nickname_edit.text_submitted.connect(func(_text: String) -> void:
		if not nickname_dialog.get_ok_button().disabled: nickname_dialog.get_ok_button().pressed.emit())
	box.add_child(nickname_edit)
	box.add_child(_build_gender_picker())
	nickname_dialog.add_child(box)
	nickname_dialog.confirmed.connect(_start_new_game)
	add_child(nickname_dialog)


# 주인공 외형(남·여) 고르기. 고르면 아래 초상화가 바뀐다.
func _build_gender_picker() -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()

	for gender in PlayerProgress.GENDERS:
		var button := Button.new()
		button.text = str(GENDER_LABELS.get(gender, gender))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = gender == chosen_gender
		button.custom_minimum_size = Vector2(144, 44)
		button.pressed.connect(_on_gender_chosen.bind(gender))
		buttons.add_child(button)

	holder.add_child(buttons)
	gender_preview = TextureRect.new()
	gender_preview.custom_minimum_size = Vector2(160, 192)
	gender_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gender_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gender_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gender_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(gender_preview)
	_on_gender_chosen(chosen_gender)
	return holder


func _on_gender_chosen(gender: String) -> void:
	chosen_gender = gender
	gender_preview.texture = PlayerPortraits.find_for(gender)


func _on_nickname_changed(_text: String) -> void:
	nickname_dialog.get_ok_button().disabled = PlayerProgress.clean_player_name(nickname_edit.text).is_empty()


func _ask_nickname() -> void:
	if entering_game:
		return

	nickname_edit.text = ""
	nickname_dialog.get_ok_button().disabled = true
	nickname_dialog.popup_centered()
	nickname_edit.grab_focus()


func _start_new_game() -> void:
	if entering_game:
		return

	var chosen_name := PlayerProgress.clean_player_name(nickname_edit.text if nickname_edit != null else "")
	GameState.initialize_new_game()
	PlayerProgress.player_gender = chosen_gender
	PlayerProgress.player_name = chosen_name  # 새 게임 초기화가 진행 기록을 비우므로 그 뒤에 넣는다

	GameState.set_build_quick_slot(
		0,
		"shelf_1x1"
	)

	GameState.set_build_quick_slot(
		1,
		"drink_machine"
	)

	enter_store()

func _refresh_load_slot_buttons() -> void:
	_update_load_slot_button(
		auto_save_button,
		"자동 저장",
		GameState.SAVE_PATH
	)

	_update_load_slot_button(
		load_slot_1_button,
		"세이브 슬롯 1",
		str(GameConfig.SAVE_SLOT_PATHS[0])
	)

	_update_load_slot_button(
		load_slot_2_button,
		"세이브 슬롯 2",
		str(GameConfig.SAVE_SLOT_PATHS[1])
	)


func _update_load_slot_button(
	button: Button,
	slot_name: String,
	path: String
) -> void:
	if not FileAccess.file_exists(path):
		button.text = (
			slot_name
			+ "\n저장 데이터 없음"
		)

		button.disabled = true
		return

	var data: Dictionary = (
		GameState.read_save_file(path)
	)

	if (
		data.is_empty()
		or not GameState.is_save_data_valid(data)
	):
		button.text = (
			slot_name
			+ "\n사용할 수 없는 저장 데이터"
		)

		# 삭제 화면에서는 손상된 파일도 선택 가능
		button.disabled = (
			slot_panel_mode != "delete"
		)

		return

	var modified_time := FileAccess.get_modified_time(path)
	if SaveSlotSummary.ENABLED:
		button.text = slot_name + "\n" + SaveSlotSummary.describe(data, modified_time)
	else:
		button.text = slot_name + "\n" + _get_saved_day_name(int(data.get("current_day", 1))) + " | 보유금 " + str(data.get("money", 0)) + "G\n저장 일시: " + _format_save_datetime(modified_time)

	button.disabled = false


func _has_any_valid_save() -> bool:
	var paths: Array = [
		GameState.SAVE_PATH,
		GameConfig.SAVE_SLOT_PATHS[0],
		GameConfig.SAVE_SLOT_PATHS[1]
	]

	for raw_path in paths:
		var path: String = str(raw_path)

		if not FileAccess.file_exists(path):
			continue

		var data: Dictionary = (
			GameState.read_save_file(path)
		)

		if (
			not data.is_empty()
			and GameState.is_save_data_valid(data)
		):
			return true

	return false


func _has_any_save_file() -> bool:
	if FileAccess.file_exists(
		GameState.SAVE_PATH
	):
		return true

	for raw_path in GameConfig.SAVE_SLOT_PATHS:
		if FileAccess.file_exists(
			str(raw_path)
		):
			return true

	return false


func _on_load_slot_pressed(
	path: String
) -> void:
	if entering_game:
		return

	var data: Dictionary = (
		GameState.read_save_file(path)
	)

	if data.is_empty():
		status_label.text = (
			"저장 파일을 읽지 못했습니다."
		)

		_refresh_load_slot_buttons()
		return

	if not GameState.apply_save_data(data):
		status_label.text = (
			"저장 데이터를 복원하지 못했습니다."
		)

		_refresh_load_slot_buttons()
		return

	load_slot_panel.visible = false

	if GameState.has_expedition_checkpoint():
		enter_expedition()
	else:
		enter_store()


func close_load_slot_panel() -> void:
	load_slot_panel.visible = false
	title_menu_center.visible = true

	slot_panel_mode = "load"
	pending_delete_path = ""
	pending_delete_slot_name = ""

	status_label.text = ""


func _on_slot_entry_pressed(
	path: String,
	slot_name: String
) -> void:
	if slot_panel_mode == "load":
		_on_load_slot_pressed(path)
		return

	if not FileAccess.file_exists(path):
		_refresh_load_slot_buttons()
		return

	pending_delete_path = path
	pending_delete_slot_name = slot_name

	delete_save_dialog.dialog_text = (
		slot_name
		+ " 데이터를 삭제하시겠습니까?"
		+ "\n삭제한 기록은 되돌릴 수 없습니다."
	)

	delete_save_dialog.popup_centered()

func _get_saved_day_name(
	day: int
) -> String:
	match day:
		1:
			return "월요일"
		2:
			return "화요일"
		3:
			return "수요일"
		4:
			return "목요일"
		5:
			return "금요일"
		6:
			return "토요일"
		7:
			return "일요일"

	return "요일 정보 없음"


func _format_save_datetime(
	unix_time: int
) -> String:
	if unix_time <= 0:
		return "알 수 없음"

	var timezone: Dictionary = (
		Time.get_time_zone_from_system()
	)

	var bias_minutes: int = int(
		timezone.get("bias", 0)
	)

	var local_unix_time: int = (
		unix_time
		+ bias_minutes * 60
	)

	var datetime: Dictionary = (
		Time.get_datetime_dict_from_unix_time(
			local_unix_time
		)
	)

	return (
		"%04d-%02d-%02d %02d:%02d"
		% [
			int(datetime.get("year", 0)),
			int(datetime.get("month", 0)),
			int(datetime.get("day", 0)),
			int(datetime.get("hour", 0)),
			int(datetime.get("minute", 0))
		]
	)
