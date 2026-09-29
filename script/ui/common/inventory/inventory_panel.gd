extends PanelContainer


# I 키로 여는 빠른 통합 인벤토리 창을 관리한다.
# 실제 아이템 목록과 분류 처리는
# UnifiedInventory(management_inventory.gd)가 담당한다.


@onready var close_button: Button = (
	$VBoxContainer/TitleHBox/CloseButton
)

@onready var unified_inventory: Control = (
	$VBoxContainer/UnifiedInventory
)


func _ready() -> void:
	visible = false

	if not close_button.pressed.is_connected(
		close_inventory
	):
		close_button.pressed.connect(
			close_inventory
		)

	DebugLog.write(
		"[빠른 인벤토리] 준비 완료"
	)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed:
		return

	if event.echo:
		return

	if event.keycode != KEY_I:
		return

	toggle_inventory()

	get_viewport().set_input_as_handled()


func toggle_inventory() -> void:
	visible = not visible

	if visible:
		open_inventory()
	else:
		DebugLog.write(
			"[빠른 인벤토리] 닫기"
		)


func open_inventory() -> void:
	visible = true

	# 창을 열 때 최신 보유 상태를 다시 읽는다.
	if unified_inventory.has_method(
		"refresh_inventory"
	):
		unified_inventory.call(
			"refresh_inventory"
		)

	await get_tree().process_frame

	center_inventory_panel()

	DebugLog.write(
		"[빠른 인벤토리] 열기"
	)


func close_inventory() -> void:
	visible = false

	DebugLog.write(
		"[빠른 인벤토리] 닫기"
	)


func center_inventory_panel() -> void:
	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	position = (
		viewport_size - size
	) * 0.5

	z_index = 200
