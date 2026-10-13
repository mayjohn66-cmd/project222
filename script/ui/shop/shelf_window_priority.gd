class_name ShelfWindowPriority
extends Node
## 진열대/창고 창과 팝업의 표시 순서. 닫을 때 원래 HUD·입력 상태로 복귀한다.
const BACKDROP_Z := 1600
const WINDOW_Z := 1601
const ACTION_Z := 1602
const AMOUNT_BACKDROP_Z := 1603
const AMOUNT_Z := 1604

var host: Control
var backdrop: Control
var amount_backdrop: Control
var hidden_controls: Dictionary = {}
var player: Node2D
var player_was_processing := false

func _ready() -> void:
	host = get_parent()
	host.z_index = WINDOW_Z
	host.visibility_changed.connect(_sync)
	_install.call_deferred()

func _install() -> void:
	backdrop = Control.new()
	backdrop.name = "ShelfInputBackdrop"
	backdrop.z_index = BACKDROP_Z
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.get_parent().add_child(backdrop)
	# GUI 입력은 z_index가 아닌 트리 순서도 사용하므로 창 앞을 가로막지 않는다.
	host.get_parent().move_child(backdrop, host.get_index())
	var amount_window: Control = host.get("restock_panel")
	amount_backdrop = Control.new()
	amount_backdrop.name = "ShelfAmountInputBackdrop"
	amount_backdrop.z_index = AMOUNT_BACKDROP_Z
	amount_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	amount_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.get_parent().add_child(amount_backdrop)
	host.get_parent().move_child(amount_backdrop, amount_window.get_index())
	amount_window.visibility_changed.connect(_sync_amount)
	var summary := host.get_parent().get_node_or_null("DaySummaryCenter") as Control
	if summary != null:
		summary.visibility_changed.connect(func():
			if summary.visible and host.visible: host.close())
	_sync()
	_sync_amount()

func _sync_amount() -> void:
	if is_instance_valid(amount_backdrop):
		amount_backdrop.visible = host.visible and host.get("restock_panel").visible

func _sync() -> void:
	if is_instance_valid(backdrop): backdrop.visible = host.visible
	_sync_amount()
	if not host.visible:
		_restore()
		return
	if not hidden_controls.is_empty(): return
	for node_name in ["HUD", "GameMenu", "BuildQuickSlotBar"]:
		var control := host.get_parent().get_node_or_null(node_name) as Control
		if control == null: continue
		hidden_controls[control] = control.visible
		control.hide()
	player = host.get("current_player") as Node2D
	if is_instance_valid(player):
		player_was_processing = player.is_physics_processing()
		player.set_physics_process(false)
		player.set("velocity", Vector2.ZERO)

func _restore() -> void:
	for control in hidden_controls:
		if is_instance_valid(control): control.visible = hidden_controls[control]
	hidden_controls.clear()
	if is_instance_valid(player): player.set_physics_process(player_was_processing)
	player = null

func _exit_tree() -> void:
	_restore()
	if is_instance_valid(backdrop): backdrop.queue_free()
	if is_instance_valid(amount_backdrop): amount_backdrop.queue_free()

static func fit_action_popup(popup: Control, minimum: Vector2) -> void:
	if not is_instance_valid(popup) or not popup.visible: return
	popup.size = popup.get_combined_minimum_size().max(minimum)
	var viewport_size := popup.get_viewport_rect().size
	popup.global_position = Vector2(
		clampf(popup.global_position.x, 8.0, maxf(8.0, viewport_size.x - popup.size.x - 8.0)),
		clampf(popup.global_position.y, 8.0, maxf(8.0, viewport_size.y - popup.size.y - 8.0)))
