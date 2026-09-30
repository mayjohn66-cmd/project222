class_name GameMenu
extends Control

# 편의점과 원정에서 공통으로 사용하는 게임 메뉴다.
# 설정·저장 슬롯·시작 화면·종료 확인 UI를 소유하고,
# 실제 저장 및 화면별 관리 기능은 신호로 현재 씬에 요청한다.


signal management_requested
signal build_requested
signal info_requested
signal save_slot_requested(
	path: String,
	slot_index: int
)
signal return_title_requested


const GAME_SETTINGS_SERVICE_SCRIPT = preload(
	"res://script/core/settings/game_settings_service.gd"
)


@onready var menu_button: Button = (
	$MenuButton
)

@onready var main_menu_panel: PanelContainer = (
	$MainMenuPanel
)

@onready var management_button: Button = (
	$MainMenuPanel/MenuVBox/ManagementButton
)

@onready var info_button: Button = (
	$MainMenuPanel/MenuVBox/InfoButton
)

@onready var settings_button: Button = (
	$MainMenuPanel/MenuVBox/SettingsButton
)

@onready var save_button: Button = (
	$MainMenuPanel/MenuVBox/SaveButton
)

@onready var title_button: Button = (
	$MainMenuPanel/MenuVBox/TitleButton
)

@onready var quit_button: Button = (
	$MainMenuPanel/MenuVBox/QuitButton
)

@onready var quit_game_dialog: ConfirmationDialog = (
	$QuitGameDialog
)

@onready var settings_panel: PanelContainer = (
	$SettingsPanel
)

@onready var settings_close_button: Button = (
	$SettingsPanel/SettingsVBox/SettingsCloseButton
)

@onready var save_slot_panel: PanelContainer = (
	$SaveSlotPanel
)

@onready var save_slot_1_button: Button = (
	$SaveSlotPanel/SaveSlotVBox/SaveSlot1Button
)

@onready var save_slot_2_button: Button = (
	$SaveSlotPanel/SaveSlotVBox/SaveSlot2Button
)

@onready var save_slot_close_button: Button = (
	$SaveSlotPanel/SaveSlotVBox/SaveSlotCloseButton
)

@onready var return_title_dialog: ConfirmationDialog = (
	$ReturnTitleDialog
)

@onready var overwrite_save_dialog: ConfirmationDialog = (
	$OverwriteSaveDialog
)


@onready var master_volume_slider: HSlider = (
	$SettingsPanel/SettingsVBox/VolumeRow/MasterVolumeSlider
)

@onready var volume_value_label: Label = (
	$SettingsPanel/SettingsVBox/VolumeRow/VolumeValueLabel
)

@onready var fullscreen_button: CheckBox = (
	$SettingsPanel/SettingsVBox/FullscreenButton
)

@onready var speed_option_button: OptionButton = (
	$SettingsPanel/SettingsVBox/SpeedRow/SpeedOptionButton
)



var game_settings_service = (
	GAME_SETTINGS_SERVICE_SCRIPT.new()
)

var loading_settings: bool = false
var build_action_enabled := false
var menu_open := false
var menu_progress := 0.0
var menu_tween: Tween
var menu_clip: Control

var pending_save_slot_index: int = -1


func _ready() -> void:
	main_menu_panel.visible = false
	settings_panel.visible = false
	save_slot_panel.visible = false

	menu_button.text = "메뉴"

	menu_button.pressed.connect(
		toggle_main_menu
	)

	management_button.pressed.connect(
		_on_management_pressed
	)

	info_button.pressed.connect(
		_on_info_pressed
	)

	settings_button.pressed.connect(
		_on_settings_pressed
	)

	save_button.pressed.connect(
		_on_save_pressed
	)

	title_button.pressed.connect(
		_on_title_pressed
	)

	quit_button.pressed.connect(
		_on_quit_pressed
	)

	quit_game_dialog.title = (
		"게임 종료"
	)

	quit_game_dialog.dialog_text = (
		"게임을 종료하시겠습니까?"
		+ "\n저장하지 않은 진행 내용은 사라집니다."
	)

	quit_game_dialog.get_ok_button().text = (
		"종료"
	)

	quit_game_dialog.get_cancel_button().text = (
		"취소"
	)

	quit_game_dialog.confirmed.connect(
		_confirm_quit_game
	)

	settings_close_button.pressed.connect(
		close_settings
	)

	save_slot_1_button.pressed.connect(
		_on_save_slot_pressed.bind(0)
	)

	save_slot_2_button.pressed.connect(
		_on_save_slot_pressed.bind(1)
	)

	save_slot_close_button.pressed.connect(
		close_save_slots
	)

	overwrite_save_dialog.title = (
		"저장 데이터 덮어쓰기"
	)

	overwrite_save_dialog.get_ok_button().text = (
		"덮어쓰기"
	)

	overwrite_save_dialog.get_cancel_button().text = (
		"취소"
	)

	overwrite_save_dialog.confirmed.connect(
		_confirm_save_overwrite
	)

	return_title_dialog.title = (
		"시작 화면으로"
	)

	return_title_dialog.dialog_text = (
		"시작 화면으로 돌아가시겠습니까?"
		+ "\n저장하지 않은 진행 내용은 사라집니다."
	)

	return_title_dialog.get_ok_button().text = (
		"돌아가기"
	)

	return_title_dialog.get_cancel_button().text = (
		"취소"
	)

	return_title_dialog.confirmed.connect(
		_confirm_return_title
	)

	master_volume_slider.min_value = 0
	master_volume_slider.max_value = 100
	master_volume_slider.step = 1

	master_volume_slider.value_changed.connect(
		_on_master_volume_changed
	)

	fullscreen_button.toggled.connect(
		_on_fullscreen_toggled
	)

	for speed_option in GameConfig.GAME_SPEED_OPTIONS:
		speed_option_button.add_item(
			str(int(speed_option)) + "배속"
		)

	speed_option_button.item_selected.connect(
		_on_game_speed_selected
	)

	z_index = 1000

	_setup_menu_presentation()
	_load_game_settings()

	_refresh_save_slot_buttons()


# =========================================================
# 메뉴 열기와 공통 화면 전환
# =========================================================

func toggle_main_menu() -> void:
	menu_open = not menu_open
	if menu_tween and menu_tween.is_valid(): menu_tween.kill()
	main_menu_panel.show()
	menu_clip.show()
	menu_button.text = "닫기" if menu_open else "메뉴"
	menu_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	menu_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	menu_tween.tween_method(_set_menu_progress,menu_progress,1.0 if menu_open else 0.0,0.34)
	if not menu_open: menu_tween.tween_callback(menu_clip.hide)

func _set_menu_progress(value: float) -> void:
	menu_progress = value
	menu_clip.offset_top = -86.0 - 348.0*value
	main_menu_panel.modulate.a = 1.0
	for i in range(main_menu_panel.get_node("MenuVBox").get_child_count()):
		var button = main_menu_panel.get_node("MenuVBox").get_child(i)
		var reveal := clampf(value*7.0-float(5-i)*0.55,0.0,1.0)
		button.modulate.a = reveal

func _hide_main_menu() -> void:
	if menu_tween and menu_tween.is_valid(): menu_tween.kill()
	menu_open = false
	menu_button.text = "메뉴"
	if is_instance_valid(menu_clip):
		_set_menu_progress(0.0)
		menu_clip.hide()
	main_menu_panel.hide()

func _setup_menu_presentation() -> void:
	var style = preload("res://script/ui/common/build/build_ui_style.gd")
	style.button(menu_button)
	menu_button.custom_minimum_size = Vector2(180,54)
	menu_button.offset_right = 204
	_steam_button(menu_button)
	main_menu_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	main_menu_panel.get_node("MenuVBox").add_theme_constant_override("separation",4)
	for button in main_menu_panel.get_node("MenuVBox").get_children():
		style.button(button)
		button.custom_minimum_size = Vector2(180,54)
		_steam_button(button)
	menu_clip = Control.new()
	menu_clip.name = "MenuReveal"
	menu_clip.clip_contents = true
	menu_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_clip)
	menu_clip.anchor_top = 1.0
	menu_clip.anchor_bottom = 1.0
	menu_clip.offset_left = 24
	menu_clip.offset_right = 204
	menu_clip.offset_bottom = -86
	main_menu_panel.reparent(menu_clip)
	main_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	main_menu_panel.size = Vector2(180,348)
	_hide_main_menu()


func close_all() -> void:
	_hide_main_menu()
	settings_panel.visible = false
	save_slot_panel.visible = false
	pending_save_slot_index = -1


func _on_management_pressed() -> void:
	_hide_main_menu()
	management_requested.emit()


func _on_info_pressed() -> void:
	_hide_main_menu()
	if build_action_enabled: build_requested.emit()
	else: info_requested.emit()


func _on_settings_pressed() -> void:
	_hide_main_menu()
	settings_panel.visible = true
	settings_panel.z_index = 310


func close_settings() -> void:
	settings_panel.visible = false


func _on_save_pressed() -> void:
	_hide_main_menu()
	save_slot_panel.visible = true
	save_slot_panel.z_index = 300

	_refresh_save_slot_buttons()


func close_save_slots() -> void:
	save_slot_panel.visible = false
	pending_save_slot_index = -1


# =========================================================
# 저장 슬롯 표시와 요청
# =========================================================

func _refresh_save_slot_buttons() -> void:
	_update_save_slot_button(
		save_slot_1_button,
		0
	)

	_update_save_slot_button(
		save_slot_2_button,
		1
	)


func _update_save_slot_button(
	button: Button,
	slot_index: int
) -> void:
	var path: String = str(
		GameConfig.SAVE_SLOT_PATHS[
			slot_index
		]
	)

	if FileAccess.file_exists(path):
		button.text = (
			"세이브 슬롯 "
			+ str(slot_index + 1)
			+ "\n저장 데이터 있음"
		)
	else:
		button.text = (
			"세이브 슬롯 "
			+ str(slot_index + 1)
			+ "\n저장 데이터 없음"
		)


func _on_save_slot_pressed(
	slot_index: int
) -> void:
	if (
		slot_index < 0
		or slot_index
		>= GameConfig.SAVE_SLOT_PATHS.size()
	):
		return

	var path: String = str(
		GameConfig.SAVE_SLOT_PATHS[
			slot_index
		]
	)

	if FileAccess.file_exists(path):
		pending_save_slot_index = (
			slot_index
		)

		overwrite_save_dialog.dialog_text = (
			"세이브 슬롯 "
			+ str(slot_index + 1)
			+ "의 데이터를 덮어쓰시겠습니까?"
		)

		overwrite_save_dialog.popup_centered()
		return

	save_slot_requested.emit(
		path,
		slot_index
	)


func _confirm_save_overwrite() -> void:
	if pending_save_slot_index < 0:
		return

	var slot_index: int = (
		pending_save_slot_index
	)

	pending_save_slot_index = -1

	var path: String = str(
		GameConfig.SAVE_SLOT_PATHS[
			slot_index
		]
	)

	save_slot_requested.emit(
		path,
		slot_index
	)


func notify_save_finished(
	success: bool
) -> void:
	if success:
		save_slot_panel.visible = false

	_refresh_save_slot_buttons()


func _on_title_pressed() -> void:
	_hide_main_menu()
	return_title_dialog.popup_centered()


func _on_quit_pressed() -> void:
	_hide_main_menu()
	quit_game_dialog.popup_centered()


func _confirm_quit_game() -> void:
	get_tree().quit()


func _confirm_return_title() -> void:
	return_title_requested.emit()

func _on_master_volume_changed(
	value: float
) -> void:
	game_settings_service.apply_master_volume(
		value
	)

	_update_volume_value_label()

	if not loading_settings:
		_save_game_settings()


func _on_fullscreen_toggled(
	enabled: bool
) -> void:
	game_settings_service.apply_fullscreen(
		enabled
	)

	if not loading_settings:
		_save_game_settings()


func _on_game_speed_selected(
	index: int
) -> void:
	GameSpeed.set_current(
		float(GameConfig.GAME_SPEED_OPTIONS[index]),
		get_tree()
	)

	if not loading_settings:
		_save_game_settings()


func _update_volume_value_label() -> void:
	volume_value_label.text = (
		str(
			roundi(
				master_volume_slider.value
			)
		)
		+ "%"
	)


func _save_game_settings() -> void:
	game_settings_service.save_settings(
		master_volume_slider.value,
		fullscreen_button.button_pressed,
		GameSpeed.get_current()
	)


func _load_game_settings() -> void:
	var settings: Dictionary = (
		game_settings_service.load_settings()
	)

	loading_settings = true

	var saved_volume: float = float(
		settings.get(
			"master_volume",
			100.0
		)
	)

	var saved_fullscreen: bool = bool(
		settings.get(
			"fullscreen",
			false
		)
	)

	master_volume_slider.set_value_no_signal(
		clampf(
			saved_volume,
			0.0,
			100.0
		)
	)

	fullscreen_button.set_pressed_no_signal(
		saved_fullscreen
	)

	game_settings_service.apply_master_volume(
		master_volume_slider.value
	)

	game_settings_service.apply_fullscreen(
		saved_fullscreen
	)

	GameSpeed.set_current(
		float(settings.get("game_speed", 1.0)),
		get_tree()
	)

	speed_option_button.select(
		GameConfig.GAME_SPEED_OPTIONS.find(
			GameSpeed.get_current()
		)
	)

	loading_settings = false

	_update_volume_value_label()

func _steam_button(button: Button) -> void:
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color("604832" if state=="normal" else ("916b41" if state=="hover" else "41352b"))
		plate.border_color = Color("c09a58")
		plate.set_border_width_all(2)
		plate.set_content_margin_all(8)
		plate.shadow_color = Color("241b17")
		plate.shadow_size = 2
		if state=="focus": plate.bg_color = Color.TRANSPARENT
		button.add_theme_stylebox_override(state,plate)
	for color in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		button.add_theme_color_override(color,Color("f7dfac"))
	var trim := BrassTrim.new()
	trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(trim)
	trim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trim.resized.connect(trim.queue_redraw)

class BrassTrim extends Control:
	func _draw() -> void:
		for x in [7.0,size.x-7.0]:
			for y in [7.0,size.y-7.0]:
				draw_circle(Vector2(x,y),2.2,Color("d6b374"))
				draw_line(Vector2(x-1,y),Vector2(x+1,y),Color("695037"),1)
		draw_line(Vector2(15,5),Vector2(size.x-15,5),Color("ad8549"),1)
		draw_line(Vector2(15,size.y-5),Vector2(size.x-15,size.y-5),Color("30271f"),1)
