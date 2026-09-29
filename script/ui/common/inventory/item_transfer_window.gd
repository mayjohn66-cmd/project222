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


func set_left_view(
	view: Control
) -> void:
	_replace_view(
		left_view_host,
		view
	)

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
