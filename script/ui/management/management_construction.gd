class_name ManagementConstruction
extends Control


signal expansion_completed


enum ConstructionTab {
	STORE,
	PRODUCTION_ROOM,
	WAREHOUSE
}


@onready var store_button: Button = (
	$MainVBox/AreaTabs/StoreButton
)

@onready var production_room_button: Button = (
	$MainVBox/AreaTabs/ProductionRoomButton
)

@onready var warehouse_button: Button = (
	$MainVBox/AreaTabs/WarehouseButton
)

@onready var area_title_label: Label = (
	$MainVBox/ContentPanel/ContentMargin/ContentVBox/AreaTitleLabel
)

@onready var current_info_label: Label = (
	$MainVBox/ContentPanel/ContentMargin/ContentVBox/CurrentInfoLabel
)

@onready var next_info_label: Label = (
	$MainVBox/ContentPanel/ContentMargin/ContentVBox/NextInfoLabel
)

@onready var expand_button: Button = (
	$MainVBox/ContentPanel/ContentMargin/ContentVBox/ExpandButton
)

@onready var note_label: Label = (
	$MainVBox/ContentPanel/ContentMargin/ContentVBox/NoteLabel
)


var current_tab: ConstructionTab = (
	ConstructionTab.STORE
)


func _ready() -> void:
	store_button.pressed.connect(
		select_tab.bind(
			ConstructionTab.STORE
		)
	)

	production_room_button.pressed.connect(
		select_tab.bind(
			ConstructionTab.PRODUCTION_ROOM
		)
	)

	warehouse_button.pressed.connect(
		select_tab.bind(
			ConstructionTab.WAREHOUSE
		)
	)

	expand_button.pressed.connect(
		_on_expand_button_pressed
	)

	select_tab(
		ConstructionTab.STORE
	)


func select_tab(
	tab: ConstructionTab
) -> void:
	current_tab = tab

	store_button.disabled = (
		tab == ConstructionTab.STORE
	)

	production_room_button.disabled = (
		tab == ConstructionTab.PRODUCTION_ROOM
	)

	warehouse_button.disabled = (
		tab == ConstructionTab.WAREHOUSE
	)

	refresh_view()


func refresh_view() -> void:
	match current_tab:
		ConstructionTab.STORE:
			_refresh_store_expansion()

		ConstructionTab.PRODUCTION_ROOM:
			_refresh_production_room_expansion()

		ConstructionTab.WAREHOUSE:
			_refresh_warehouse_expansion()

func _refresh_production_room_expansion() -> void:
	var current_level: int = (
		GameState.get_production_room_expansion_level()
	)

	var current_size: Vector2i = (
		GameState.get_production_room_size()
	)

	area_title_label.text = "생산실 크기 확장"

	current_info_label.text = (
		"현재 단계: %d단계\n현재 크기: %d × %d"
		% [
			current_level,
			current_size.x,
			current_size.y
		]
	)

	if not GameState.can_expand_production_room():
		next_info_label.text = (
			"현재 생산실은 최대 크기입니다."
		)

		expand_button.text = "최대 확장 완료"
		expand_button.disabled = true

		note_label.text = (
			"현재 공간에 생산 설비를 자유롭게 배치할 수 있습니다."
		)
		return

	var next_level: int = (
		GameState.get_next_production_room_level()
	)

	var next_size: Vector2i = (
		GameState.get_next_production_room_size()
	)

	var expansion_cost: int = (
		GameState.get_production_room_expansion_cost()
	)

	next_info_label.text = (
		"다음 단계: %d단계\n확장 후 크기: %d × %d\n비용: %d G"
		% [
			next_level,
			next_size.x,
			next_size.y,
			expansion_cost
		]
	)

	expand_button.text = (
		"생산실 확장 · %d G"
		% expansion_cost
	)

	var can_expand_now: bool = (
		_can_expand_space_now()
	)

	var can_afford_expansion: bool = (
		GameState
		.can_afford_production_room_expansion()
	)

	expand_button.disabled = (
		not can_expand_now
		or not can_afford_expansion
	)

	if not can_expand_now:
		note_label.text = (
			"공간 확장은 오전 9시 영업 시작 전에만 가능합니다."
		)
	elif not can_afford_expansion:
		note_label.text = (
			"확장 비용이 부족합니다."
		)
	else:
		note_label.text = (
			"확장하면 생산 설비를 배치할 수 있는 공간이 증가합니다."
		)

func _refresh_store_expansion() -> void:
	var current_level: int = (
		GameState.get_store_expansion_level()
	)

	var current_size: Vector2i = (
		GameState.get_store_size()
	)

	area_title_label.text = "편의점 크기 확장"

	current_info_label.text = (
		"현재 단계: %d단계\n현재 크기: %d × %d"
		% [
			current_level,
			current_size.x,
			current_size.y
		]
	)

	if not GameState.can_expand_store():
		next_info_label.text = (
			"현재 편의점은 최대 크기입니다."
		)

		expand_button.text = "최대 확장 완료"
		expand_button.disabled = true

		note_label.text = (
			"추가 지점 시스템은 본점 최대 확장 이후 연결할 수 있습니다."
		)
		return

	var next_level: int = (
		GameState.get_next_store_expansion_level()
	)

	var next_size: Vector2i = (
		GameState.get_next_store_size()
	)

	var expansion_cost: int = (
		GameState.get_store_expansion_cost()
	)

	next_info_label.text = (
		"다음 단계: %d단계\n확장 후 크기: %d × %d\n비용: %d G"
		% [
			next_level,
			next_size.x,
			next_size.y,
			expansion_cost
		]
	)

	expand_button.text = (
		"편의점 확장 · %d G"
		% expansion_cost
	)

	var can_expand_now: bool = (
		_can_expand_space_now()
	)

	var can_afford_expansion: bool = (
		GameState.can_afford_store_expansion()
	)

	expand_button.disabled = (
		not can_expand_now
		or not can_afford_expansion
	)

	if not can_expand_now:
		note_label.text = (
			"공간 확장은 오전 9시 영업 시작 전에만 가능합니다."
		)
	elif not can_afford_expansion:
		note_label.text = (
			"확장 비용이 부족합니다."
		)
	else:
		note_label.text = (
			"확장하면 건축 가능한 편의점 내부 공간이 증가합니다."
		)


func _on_expand_button_pressed() -> void:
	match current_tab:
		ConstructionTab.STORE:
			_request_store_expansion()

		ConstructionTab.PRODUCTION_ROOM:
			_request_production_room_expansion()

		ConstructionTab.WAREHOUSE:
			_request_warehouse_expansion()


func _request_store_expansion() -> void:
	if not _can_expand_space_now():
		refresh_view()
		return

	if not GameState.can_expand_store():
		refresh_view()
		return

	if not GameState.can_afford_store_expansion():
		refresh_view()
		return

	var next_size: Vector2i = (
		GameState.get_next_store_size()
	)

	var expansion_cost: int = (
		GameState.get_store_expansion_cost()
	)

	var confirm_dialog := ConfirmationDialog.new()

	confirm_dialog.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)

	confirm_dialog.title = "편의점 확장"

	confirm_dialog.dialog_text = (
		"편의점을 %d × %d 크기로 확장하시겠습니까?\n"
		+ "비용: %d G"
	) % [
		next_size.x,
		next_size.y,
		expansion_cost
	]

	confirm_dialog.confirmed.connect(
		_confirm_store_expansion.bind(
			confirm_dialog
		)
	)

	confirm_dialog.canceled.connect(
		confirm_dialog.queue_free
	)

	add_child(confirm_dialog)

	confirm_dialog.popup_centered(
		Vector2i(
			440,
			190
		)
	)

func _refresh_warehouse_expansion() -> void:
	var current_level: int = (
		GameState.get_warehouse_expansion_level()
	)

	var current_size: Vector2i = (
		GameState.get_warehouse_size()
	)

	area_title_label.text = "창고 크기 확장"

	current_info_label.text = (
		"현재 단계: %d단계\n현재 크기: %d × %d"
		% [
			current_level,
			current_size.x,
			current_size.y
		]
	)

	if not GameState.can_expand_warehouse():
		next_info_label.text = (
			"현재 창고는 최대 크기입니다."
		)

		expand_button.text = "최대 확장 완료"
		expand_button.disabled = true

		note_label.text = (
			"현재 공간에 창고 설비를 자유롭게 배치할 수 있습니다."
		)
		return

	var next_level: int = (
		GameState.get_next_warehouse_level()
	)

	var next_size: Vector2i = (
		GameState.get_next_warehouse_size()
	)

	var expansion_cost: int = (
		GameState.get_warehouse_expansion_cost()
	)

	next_info_label.text = (
		"다음 단계: %d단계\n"
		+ "확장 후 크기: %d × %d\n"
		+ "비용: %d G"
	) % [
		next_level,
		next_size.x,
		next_size.y,
		expansion_cost
	]

	expand_button.text = (
		"창고 확장 · %d G"
		% expansion_cost
	)

	var can_expand_now: bool = (
		_can_expand_space_now()
	)

	var can_afford_expansion: bool = (
		GameState.can_afford_warehouse_expansion()
	)

	expand_button.disabled = (
		not can_expand_now
		or not can_afford_expansion
	)

	if not can_expand_now:
		note_label.text = (
			"공간 확장은 오전 9시 영업 시작 전에만 가능합니다."
		)

	elif not can_afford_expansion:
		note_label.text = (
			"확장 비용이 부족합니다."
		)

	else:
		note_label.text = (
			"확장하면 창고 설비를 배치할 수 있는 공간이 증가합니다."
		)

func _request_warehouse_expansion() -> void:
	if not _can_expand_space_now():
		refresh_view()
		return

	if not GameState.can_expand_warehouse():
		refresh_view()
		return

	if not GameState.can_afford_warehouse_expansion():
		refresh_view()
		return

	var next_size: Vector2i = (
		GameState.get_next_warehouse_size()
	)

	var expansion_cost: int = (
		GameState.get_warehouse_expansion_cost()
	)

	var confirm_dialog := ConfirmationDialog.new()

	confirm_dialog.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)

	confirm_dialog.title = "창고 확장"

	confirm_dialog.dialog_text = (
		"창고를 %d × %d 크기로 확장하시겠습니까?\n"
		+ "비용: %d G"
	) % [
		next_size.x,
		next_size.y,
		expansion_cost
	]

	confirm_dialog.confirmed.connect(
		_confirm_warehouse_expansion.bind(
			confirm_dialog
		)
	)

	confirm_dialog.canceled.connect(
		confirm_dialog.queue_free
	)

	add_child(confirm_dialog)

	confirm_dialog.popup_centered(
		Vector2i(
			440,
			190
		)
	)


func _confirm_warehouse_expansion(
	confirm_dialog: ConfirmationDialog
) -> void:
	var succeeded: bool = (
		GameState.upgrade_warehouse()
	)

	if is_instance_valid(confirm_dialog):
		confirm_dialog.queue_free()

	if not succeeded:
		refresh_view()
		return

	refresh_view()
	expansion_completed.emit()

func _confirm_store_expansion(
	confirm_dialog: ConfirmationDialog
) -> void:
	var succeeded: bool = (
		GameState.upgrade_store()
	)

	if is_instance_valid(confirm_dialog):
		confirm_dialog.queue_free()

	if not succeeded:
		refresh_view()
		return

	refresh_view()
	expansion_completed.emit()

func _request_production_room_expansion() -> void:
	if not _can_expand_space_now():
		refresh_view()
		return

	if not GameState.can_expand_production_room():
		refresh_view()
		return

	if not GameState.can_afford_production_room_expansion():
		refresh_view()
		return

	var next_size: Vector2i = (
		GameState.get_next_production_room_size()
	)

	var expansion_cost: int = (
		GameState.get_production_room_expansion_cost()
	)

	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)

	confirm_dialog.title = "생산실 확장"

	confirm_dialog.dialog_text = (
		"생산실을 %d × %d 크기로 확장하시겠습니까?\n비용: %d G"
		% [
			next_size.x,
			next_size.y,
			expansion_cost
		]
	)

	confirm_dialog.confirmed.connect(
		_confirm_production_room_expansion.bind(
			confirm_dialog
		)
	)

	confirm_dialog.canceled.connect(
		confirm_dialog.queue_free
	)

	add_child(
		confirm_dialog
	)

	confirm_dialog.popup_centered(
		Vector2i(
			440,
			190
		)
	)

func _confirm_production_room_expansion(
	confirm_dialog: ConfirmationDialog
) -> void:
	var succeeded: bool = (
		GameState.upgrade_production_room()
	)

	if is_instance_valid(confirm_dialog):
		confirm_dialog.queue_free()

	if not succeeded:
		refresh_view()
		return

	refresh_view()
	expansion_completed.emit()

# 공간 확장은 오전 9시 영업 시작 전 준비 시간에만 허용한다.
func _can_expand_space_now() -> bool:
	var current_scene: Node = (
		get_tree().current_scene
	)

	if not is_instance_valid(current_scene):
		return false

	var day_manager: Node = (
		current_scene.get_node_or_null(
			"DayManager"
		)
	)

	if not is_instance_valid(day_manager):
		return false

	var build_manager: Node = (
		current_scene.get_node_or_null(
			"BuildManager"
		)
	)

	if is_instance_valid(build_manager):
		if bool(
			build_manager.get(
				"build_mode"
			)
		):
			return false

	return (
		int(day_manager.get("current_hour")) == 9
		and not bool(day_manager.get("shop_open"))
		and not bool(day_manager.get("summary_open"))
		and not bool(day_manager.get("closing_shop"))
		and not bool(day_manager.get("night_closed"))
		and not bool(
			day_manager.get(
				"fast_forwarding_to_morning"
			)
		)
		and not bool(
			day_manager.get(
				"night_auto_running"
			)
		)
	)
