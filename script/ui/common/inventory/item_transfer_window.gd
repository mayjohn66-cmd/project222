class_name ItemTransferWindow
extends Control


signal window_closed

const WAREHOUSE_INVENTORY_VIEW_SCENE: PackedScene = preload(
	"res://scenes/shop/warehouse/warehouse_inventory_view.tscn"
)

@onready var title_label: Label = (
	$CenterContainer/WindowPanel/ContentMargin/MainVBox/Header/TitleLabel
)

@onready var close_button: Button = (
	$CenterContainer/WindowPanel/ContentMargin/MainVBox/Header/CloseButton
)

@onready var left_view_host: MarginContainer = (
	$CenterContainer/WindowPanel/ContentMargin/MainVBox/Body/LeftViewHost
)

@onready var right_view_host: MarginContainer = (
	$CenterContainer/WindowPanel/ContentMargin/MainVBox/Body/RightViewHost
)

@onready var player_inventory_view: Control = (
	$CenterContainer/WindowPanel/ContentMargin/MainVBox/Body/RightViewHost/PlayerInventoryView
)

var current_warehouse_storage: Node = null
var warehouse_inventory_view: WarehouseInventoryView = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 300

	if not close_button.pressed.is_connected(
		close_window
	):
		close_button.pressed.connect(
			close_window
		)

	if player_inventory_view.has_method(
		"set_item_transfer_mode"
	):
		player_inventory_view.call(
			"set_item_transfer_mode",
			true,
			"player"
		)

	hide()


func open_warehouse_storage(
	target_storage: Node
) -> void:
	if not is_instance_valid(
		target_storage
	):
		return

	if target_storage.is_queued_for_deletion():
		return

	var created_view: WarehouseInventoryView = (
		WAREHOUSE_INVENTORY_VIEW_SCENE.instantiate()
		as WarehouseInventoryView
	)

	if created_view == null:
		push_error(
			"[아이템 이동 창] 창고 인벤토리 UI 생성 실패"
		)
		return

	current_warehouse_storage = target_storage
	warehouse_inventory_view = created_view

	set_left_view(
		warehouse_inventory_view
	)

	warehouse_inventory_view.bind_storage(
		current_warehouse_storage
	)

	if not warehouse_inventory_view.contents_changed.is_connected(
		_on_warehouse_contents_changed
	):
		warehouse_inventory_view.contents_changed.connect(
			_on_warehouse_contents_changed
		)

	open_window(
		"창고 선반"
	)

func open_window(
	window_title: String
) -> void:
	title_label.text = window_title

	if player_inventory_view.has_method(
		"refresh_inventory"
	):
		player_inventory_view.call(
			"refresh_inventory"
		)

	show()

	if get_parent() != null:
		get_parent().move_child(
			self,
			-1
		)

func _on_warehouse_contents_changed() -> void:
	if (
		is_instance_valid(
			warehouse_inventory_view
		)
		and not warehouse_inventory_view.is_queued_for_deletion()
	):
		warehouse_inventory_view.refresh_view()

	if player_inventory_view.has_method(
		"refresh_inventory"
	):
		player_inventory_view.call(
			"refresh_inventory"
		)

func close_window() -> void:
	if not visible:
		return

	hide()

	window_closed.emit()


func is_window_open() -> bool:
	return visible


func set_left_view(
	view: Control
) -> void:
	_replace_view(
		left_view_host,
		view
	)

func clear_left_view() -> void:
	_clear_view_host(
		left_view_host
	)

	current_warehouse_storage = null
	warehouse_inventory_view = null

func _replace_view(
	host: MarginContainer,
	view: Control
) -> void:
	_clear_view_host(
		host
	)

	if not is_instance_valid(view):
		return

	var previous_parent: Node = (
		view.get_parent()
	)

	if previous_parent != null:
		previous_parent.remove_child(
			view
		)

	host.add_child(
		view
	)

	view.set_h_size_flags(
		Control.SIZE_EXPAND_FILL
	)

	view.set_v_size_flags(
		Control.SIZE_EXPAND_FILL
	)


func _clear_view_host(
	host: MarginContainer
) -> void:
	for child in host.get_children():
		host.remove_child(
			child
		)

		child.queue_free()


func _unhandled_input(
	event: InputEvent
) -> void:
	if not visible:
		return

	if event.is_action_pressed(
		"ui_cancel"
	):
		close_window()

		get_viewport().set_input_as_handled()
