extends Node2D

# 원정의 준비(PREP), 진행(RUN), 결과(RESULT) 단계를 조정한다.
# 가방·전투·지도·이벤트·저장 서비스의 흐름만 연결하고,
# 세부 규칙과 데이터 로딩은 각 전용 클래스에 위임한다.


const Weekday = CalendarData.Weekday


enum ExpeditionPhase {
	PREP,
	RUN,
	RESULT
}

enum ExpeditionEndReason {
	RETREAT,
	BOSS_CLEAR,
	DEFEAT
}


const LOOT_ITEM_CARD_SCRIPT = preload(
	"res://script/ui/expedition/loot_item_card.gd"
)

@onready var day_label: Label = (
	$UI/Panel/VBoxContainer/DayLabel
)

@onready var status_label: Label = (
	$UI/Panel/VBoxContainer/StatusLabel
)

@onready var complete_button: Button = (
	$UI/Panel/VBoxContainer/CompleteButton
)

@onready var bag_grid_view: GridInventoryView = (
	$UI/RunPanel/BagPanel/VBoxContainer/BagGridView
)

@onready var loot_grid: GridContainer = (
	$UI/RunPanel/LootPanel/VBoxContainer/LootGrid
)

@onready var loot_panel = (
	$UI/RunPanel/LootPanel
)

@onready var loot_confirm_button: Button = (
	$UI/RunPanel/LootPanel/VBoxContainer/LootConfirmButton
)

@onready var player_hp_label: Label = (
	$UI/RunPanel/BattlePanel/VBoxContainer/PlayerHpLabel
)

@onready var enemy_hp_label: Label = (
	$UI/RunPanel/BattlePanel/VBoxContainer/EnemyHpLabel
)

@onready var battle_status_label: Label = (
	$UI/RunPanel/BattlePanel/VBoxContainer/BattleStatusLabel
)

@onready var start_battle_button: Button = (
	$UI/RunPanel/BattlePanel/VBoxContainer/StartBattleButton
)

@onready var battle_timer: Timer = (
	$BattleTimer
)

@onready var map_layers: VBoxContainer = (
	$UI/RunPanel/MapPanel/VBoxContainer/MapLayers
)

@onready var map_panel: PanelContainer = (
	$UI/RunPanel/MapPanel
)

@onready var battle_panel: PanelContainer = (
	$UI/RunPanel/BattlePanel
)

@onready var prep_panel: Control = (
	$UI/PrepPanel
)

@onready var prep_title_label: Label = (
	$UI/PrepPanel/Header/HeaderColumn/PrepTitleLabel
)

@onready var start_expedition_button: Button = (
	$UI/PrepPanel/StartExpeditionButton
)

@onready var cancel_preparation_button: Button = (
	$UI/PrepPanel/CancelPreparationButton
)


@onready var result_panel: PanelContainer = (
	$UI/ResultPanel
)

@onready var result_info_label: Label = (
	$UI/ResultPanel/VBoxContainer/ResultInfoLabel
)

@onready var result_confirm_button: Button = (
	$UI/ResultPanel/VBoxContainer/ResultConfirmButton
)

@onready var bag_panel: PanelContainer = (
	$UI/RunPanel/BagPanel
)

@onready var bag_content: PanelContainer = (
	$UI/PrepPanel/BagContent
)

@onready var map_content: Control = (
	$UI/PrepPanel/MapContent
)

@onready var player_stats_label: Label = (
	$UI/RunPanel/PlayerStatusPanel/VBoxContainer/PlayerStatsLabel
)

@onready var message_panel: PanelContainer = (
	$UI/RunPanel/MessagePanel
)

@onready var message_label: Label = (
	$UI/RunPanel/MessagePanel/VBoxContainer/MessageLabel
)

@onready var message_continue_button: Button = (
	$UI/RunPanel/MessagePanel/VBoxContainer/ContinueButton
)

@onready var discard_loot_dialog: ConfirmationDialog = (
	$UI/DiscardLootDialog
)

@onready var game_menu: GameMenu = (
	$UI/GameMenu
)

@onready var management_menu: Control = (
	$UI/ManagementMenu
)



const EXPEDITION_DEPARTURE_SERVICE_SCRIPT = preload(
	"res://script/expedition/services/expedition_departure_service.gd"
)

const EXPEDITION_RESULT_SERVICE_SCRIPT = preload(
	"res://script/expedition/services/expedition_result_service.gd"
)

const EXPEDITION_LOOT_SERVICE_SCRIPT = preload(
	"res://script/expedition/services/expedition_loot_service.gd"
)

const CHECKPOINT_FILE_SERVICE_SCRIPT = preload(
	"res://script/core/persistence/checkpoint_file_service.gd"
)


var temporary_loot: Array[Dictionary] = []

var current_day: int = Weekday.SATURDAY
var expedition_bag: ExpeditionBag
var selected_bag_uid: int = -1

var battle_active: bool = false

const BASE_PLAYER_ATTACK: int = 12
const BASE_PLAYER_DEFENSE: int = 3


var combat_player_hp: int = 100
var combat_player_max_hp: int = 100

var combat_player_attack: int = BASE_PLAYER_ATTACK
var combat_player_defense: int = BASE_PLAYER_DEFENSE

var combat_enemy_id: String = ""
var combat_enemy_name: String = ""
var combat_enemy_hp: int = 0
var combat_enemy_max_hp: int = 0
var combat_enemy_attack: int = 0
var combat_enemy_defense: int = 0

var expedition_map: ExpeditionMap
var current_map_node_id: String = ""
var selected_map_node_id: String = ""

var visited_map_node_ids: Array[String] = []

var current_expedition_phase: ExpeditionPhase = (
	ExpeditionPhase.PREP
)


var run_message_queue: Array[String] = []
var run_message_finish_action: Callable = Callable()

var current_region_id: String = GameConfig.DEFAULT_REGION_ID

var expedition_departure_service = (
	EXPEDITION_DEPARTURE_SERVICE_SCRIPT.new()
)

var expedition_loot_service = (
	EXPEDITION_LOOT_SERVICE_SCRIPT.new()
)

var expedition_result_service = (
	EXPEDITION_RESULT_SERVICE_SCRIPT.new()
)

var current_end_reason: ExpeditionEndReason = (
	ExpeditionEndReason.RETREAT
)

var expedition_gathering_service := (
	ExpeditionGatheringService.new()
)

var checkpoint_file_service = (
	CHECKPOINT_FILE_SERVICE_SCRIPT.new()
)

var save_failure_reason: String = ""
var preparation_return_pending: bool = false





func _ready() -> void:
	call_deferred("_install_preparation_village")
	# =====================================================
	# 1. 공용 메뉴 초기화
	# =====================================================

	game_menu.visible = true
	game_menu.z_index = 1000


	game_menu.management_requested.connect(
		_on_management_requested
	)

	game_menu.info_requested.connect(
		_on_info_requested
	)

	game_menu.save_slot_requested.connect(
		_on_game_menu_save_slot_requested
	)

	game_menu.return_title_requested.connect(
		_on_game_menu_return_title_requested
	)

	if is_instance_valid(management_menu):
		management_menu.visible = false


	# =====================================================
	# 2. 공용 데이터 불러오기
	# =====================================================

	ExpeditionEventData.ensure_loaded()
	ExpeditionGatheringData.ensure_loaded()
	RecipeData.ensure_loaded()
	ExpeditionEquipmentData.ensure_loaded()


	# =====================================================
	# 3. 현재 원정 날짜 설정
	# =====================================================

	current_day = GameState.current_day



	# =====================================================
	# 4. 기본 버튼과 타이머 연결
	# =====================================================

	start_battle_button.pressed.connect(
		start_test_battle
	)

	battle_timer.timeout.connect(
		process_battle_tick
	)

	complete_button.pressed.connect(
		open_result_phase
	)

	start_expedition_button.pressed.connect(
		start_expedition_run
	)
	cancel_preparation_button.pressed.connect(
		cancel_expedition_preparation
	)

	result_confirm_button.pressed.connect(
		confirm_result_phase
	)

	loot_confirm_button.pressed.connect(
		confirm_loot_organization
	)

	message_continue_button.pressed.connect(
		_on_message_continue_pressed
	)


	# =====================================================
	# 5. 원정 준비 화면 신호 연결
	# =====================================================

	if map_content.has_signal(
		"region_changed"
	):
		map_content.connect(
			"region_changed",
			Callable(
				self,
				"_on_prep_region_changed"
			)
		)


	# =====================================================
	# 6. 확인창 설정
	# =====================================================

	discard_loot_dialog.title = (
		"남은 전리품 포기"
	)

	discard_loot_dialog.get_ok_button().text = (
		"포기하고 진행"
	)

	discard_loot_dialog.get_cancel_button().text = (
		"계속 정리"
	)


	# =====================================================
	# 7. 원정 가방 모델 준비
	# =====================================================

	# PREP 화면에서 사용하는 가방 모델을 가져온다.
	if prep_panel.has_method(
		"get_prepared_bag_model"
	):
		expedition_bag = prep_panel.call(
			"get_prepared_bag_model"
		)

	# 준비된 가방이 없다면 기본 크기로 생성한다.
	if expedition_bag == null:
		expedition_bag = ExpeditionBag.new(
			6,
			5
		)


	# =====================================================
	# 8. 이전 원정 가방 복원
	# =====================================================

	var saved_bag: Array[Dictionary] = (
		GameState.get_saved_expedition_bag()
	)

	if not saved_bag.is_empty():
		var bag_restored: bool = (
			expedition_bag.load_placements(
				saved_bag
			)
		)

		if not bag_restored:
			status_label.text = (
				"저장된 가방을 복원하지 못했습니다."
				+ "\n출력창의 오류 내용을 확인해주세요."
			)

			start_expedition_button.disabled = true
			complete_button.disabled = true
			result_confirm_button.disabled = true

			push_error(
				"[원정] 가방 복원 실패로 진행을 중단합니다."
			)
			return

		DebugLog.write(
			"[원정] 이전 가방 복원 / 아이템 수: ",
			expedition_bag.placements.size()
		)


	# =====================================================
	# 9. 가방 및 전리품 UI 준비
	# =====================================================

	setup_bag_grid_view()

	if bag_content.has_method(
		"refresh_all"
	):
		bag_content.call(
			"refresh_all"
		)

	loot_panel.controller = self


	# =====================================================
	# 10. 기본 화면 상태 설정
	# =====================================================

	message_panel.visible = false
	battle_panel.visible = false
	loot_panel.visible = false

	set_expedition_phase(
		ExpeditionPhase.PREP
	)

	refresh_start_expedition_button()
	update_battle_ui()
	update_ui()


	# =====================================================
	# 11. 저장된 원정 체크포인트 복원
	# =====================================================

	if GameState.has_expedition_checkpoint():
		var checkpoint_restored: bool = (
			restore_expedition_checkpoint()
		)

		if not checkpoint_restored:
			status_label.text = (
				"저장된 원정 상태를 복원하지 못했습니다."
			)

			push_error(
				"[원정] 체크포인트 복원 실패"
			)


	# =====================================================
	# 12. 초기화 완료
	# =====================================================

	DebugLog.write(
		"[원정] 시작: ",
		get_day_name()
	)


func _input(event) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_F5
	):
		var saved: bool = (
			save_expedition_checkpoint()
		)

		if saved:
			status_label.text = (
				"원정 퀵 세이브 완료"
			)

			DebugLog.write(
				"[원정 저장] 퀵 세이브 완료"
			)
		else:
			status_label.text = (
				save_failure_reason
			)

			DebugLog.write(
				"[원정 저장] 실패 / ",
				save_failure_reason
			)

		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(
		"bag_rotate"
	):
		rotate_selected_bag_item()


# =========================================================
# 공용 메뉴 - 관리 및 정보
# =========================================================

func _on_management_requested() -> void:
	if not is_instance_valid(
		management_menu
	):
		return

	if not management_menu.has_method(
		"open_menu"
	):
		push_warning(
			"[원정 메뉴] 관리 화면을 열 수 없습니다."
		)
		return

	management_menu.call(
		"open_menu"
	)


func _on_info_requested() -> void:
	if not is_instance_valid(
		management_menu
	):
		return

	if not management_menu.has_method(
		"open_menu"
	):
		push_warning(
			"[원정 메뉴] 정보 화면을 열 수 없습니다."
		)
		return

	management_menu.call(
		"open_menu",
		ManagementMenu.MenuTab.HISTORY
	)


# =========================================================
# 날짜 표시와 편의점 복귀
# =========================================================

func get_day_name() -> String:
	return ["월요일","화요일","수요일","목요일","금요일","토요일","일요일"][clampi(current_day-1,0,6)]

func update_ui():
	day_label.text = get_day_name()
	status_label.text = "원정 진행"
	complete_button.text = "편의점으로 복귀"


func finish_expedition() -> void:
	if expedition_bag == null:
		result_info_label.text = (
			"원정 가방을 찾지 못했습니다."
		)
		return

	result_confirm_button.disabled = true

	# 날짜를 변경하기 전에 복귀 씬을 먼저 검사한다.
	var main_scene: PackedScene = load(
		GameConfig.MAIN_SCENE_PATH
	) as PackedScene

	if main_scene == null:
		result_confirm_button.disabled = false

		result_info_label.text = (
			"편의점 씬을 불러오지 못했습니다."
			+ "\n복귀 버튼을 다시 눌러주세요."
		)

		push_error(
			"[원정 복귀] main.tscn 불러오기 실패"
		)
		return

	# 정산 후 가방에 남은 장비 등의 배치를 보관
	GameState.save_expedition_bag(
		expedition_bag.placements
	)

	# 씬 전환 요청이 성공한 뒤에만 날짜를 변경한다.
	var scene_error: Error = (
		get_tree().change_scene_to_packed(
			main_scene
		)
	)

	if scene_error != OK:
		result_confirm_button.disabled = false

		result_info_label.text = (
			"편의점으로 돌아가지 못했습니다."
			+ "\n복귀 버튼을 다시 눌러주세요."
		)

		push_error(
			"[원정 복귀] 씬 전환 실패: "
			+ str(scene_error)
		)
		return

	# 편의점 복귀가 확정됐으므로
	# 완료된 원정 체크포인트를 제거한다.
	GameState.clear_expedition_checkpoint()



# 관리 인벤토리 등 외부 UI에서 현재 원정 가방을
# 조회할 때 사용하는 읽기 전용 복사본이다.
func get_active_expedition_bag_placements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	DebugLog.write(
		"[통합 인벤토리 확인] 원정 가방 모델 존재: ",
		expedition_bag != null
	)

	if expedition_bag == null:
		return result

	for placement in expedition_bag.placements:
		result.append(
			placement.duplicate(true)
		)

	DebugLog.write(
		"[통합 인벤토리 확인] 실시간 가방 배치: ",
		result
	)

	return result

# =========================================================
# 원정 가방과 전리품 정리
# =========================================================

func setup_bag_grid_view() -> void:
	if expedition_bag == null:
		return

	if bag_grid_view == null:
		return

	bag_grid_view.setup(
		"bag",
		expedition_bag,
		self,
		expedition_bag.width,
		expedition_bag.height,
		52
	)

func refresh_bag_ui() -> void:
	if bag_grid_view == null:
		return

	if expedition_bag == null:
		return

	bag_grid_view.refresh()
	bag_grid_view.refresh_selection_visuals()

func select_grid_item(
	source: String,
	uid: int
) -> void:
	if source != "bag":
		return

	if uid < 0:
		return

	selected_bag_uid = uid

	if bag_grid_view != null:
		bag_grid_view.refresh_selection_visuals()


func toggle_grid_item(
	source: String,
	uid: int
) -> void:
	if source != "bag":
		return

	if uid < 0:
		return

	if selected_bag_uid == uid:
		selected_bag_uid = -1
	else:
		selected_bag_uid = uid

	if bag_grid_view != null:
		bag_grid_view.refresh_selection_visuals()


func is_grid_item_selected(
	source: String,
	uid: int
) -> bool:
	return (
		source == "bag"
		and selected_bag_uid == uid
	)


func clear_grid_selection(
	source: String
) -> void:
	if source != "bag":
		return

	selected_bag_uid = -1

	if bag_grid_view != null:
		bag_grid_view.refresh_selection_visuals()


func can_drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> bool:
	if target_source != "bag":
		return false

	if expedition_bag == null:
		return false

	var source: String = str(
		data.get(
			"source",
			""
		)
	)

	var grab_offset: Vector2i = data.get(
		"grab_offset_cell",
		Vector2i.ZERO
	)

	var target_cell: Vector2i = (
		cursor_cell - grab_offset
	)

	if source == "bag":
		var uid: int = int(
			data.get(
				"uid",
				-1
			)
		)

		var placement: Dictionary = (
			expedition_bag.get_placement(
				uid
			)
		)

		if placement.is_empty():
			return false

		var item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		var rotated: bool = bool(
			placement.get(
				"rotated",
				false
			)
		)

		return expedition_bag.can_place(
			item_id,
			target_cell,
			rotated,
			uid
		)

	if source == "loot":
		var loot_index: int = int(
			data.get(
				"loot_index",
				-1
			)
		)

		if (
			loot_index < 0
			or loot_index >= temporary_loot.size()
		):
			return false

		var loot: Dictionary = (
			temporary_loot[loot_index]
		)

		var item_id: String = str(
			loot.get(
				"item_id",
				""
			)
		)

		if item_id.is_empty():
			return false

		return expedition_bag.can_place(
			item_id,
			target_cell,
			false
		)

	return false

func drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> void:
	if not can_drop_grid_data(
		target_source,
		data,
		cursor_cell
	):
		return

	var source: String = str(
		data.get(
			"source",
			""
		)
	)

	var grab_offset: Vector2i = data.get(
		"grab_offset_cell",
		Vector2i.ZERO
	)

	var target_cell: Vector2i = (
		cursor_cell - grab_offset
	)

	# 원정 가방 내부 이동
	if source == "bag":
		var uid: int = int(
			data.get(
				"uid",
				-1
			)
		)

		if expedition_bag.move_item(
			uid,
			target_cell
		):
			selected_bag_uid = uid
			refresh_bag_ui()

		return

	# 임시 전리품 → 원정 가방
	if source == "loot":
		var loot_index: int = int(
			data.get(
				"loot_index",
				-1
			)
		)

		if (
			loot_index < 0
			or loot_index >= temporary_loot.size()
		):
			return

		var loot: Dictionary = (
			temporary_loot[loot_index]
		)

		var item_id: String = str(
			loot.get(
				"item_id",
				""
			)
		)

		var amount: int = int(
			loot.get(
				"amount",
				1
			)
		)

		var new_uid: int = (
			expedition_bag.add_item(
				item_id,
				target_cell,
				amount,
				false
			)
		)

		if new_uid < 0:
			return

		temporary_loot.remove_at(
			loot_index
		)

		selected_bag_uid = new_uid

		refresh_loot_ui()
		refresh_bag_ui()

func rotate_selected_bag_item() -> void:
	if selected_bag_uid < 0:
		return

	if expedition_bag == null:
		return

	if not expedition_bag.rotate_item(
		selected_bag_uid
	):
		return

	refresh_bag_ui()

func refresh_loot_ui():
	for child in loot_grid.get_children():
		child.queue_free()

	for index in range(
		temporary_loot.size()
	):
		var loot: Dictionary = (
			temporary_loot[index]
		)

		var item_id: String = str(
			loot.get(
				"item_id",
				""
			)
		)

		var amount: int = int(
			loot.get(
				"amount",
				1
			)
		)

		var card = LOOT_ITEM_CARD_SCRIPT.new()

		card.custom_minimum_size = Vector2(
			100,
			80
		)

		loot_grid.add_child(card)

		card.setup(
			index,
			item_id,
			amount,
			self
		)

func return_bag_item_to_loot(
	data: Dictionary
):
	var uid: int = int(
		data.get(
			"uid",
			-1
		)
	)

	if uid < 0:
		return

	var placement: Dictionary = (
		expedition_bag.remove_item(
			uid
		)
	)

	if placement.is_empty():
		return

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var amount: int = int(
		placement.get(
			"amount",
			1
		)
	)

	temporary_loot.append(
		{
			"item_id": item_id,
			"amount": amount
		}
	)

	selected_bag_uid = -1

	DebugLog.write(
		"[전리품] 가방 → 임시 보관함: ",
		ItemData.get_item_name(
			item_id
		),
		" ×",
		amount
	)

	refresh_bag_ui()
	refresh_loot_ui()

func confirm_loot_organization() -> void:
	if current_expedition_phase != ExpeditionPhase.RUN:
		return

	if not loot_panel.visible:
		return

	# 남은 전리품이 없다면 바로 완료
	if temporary_loot.is_empty():
		_finish_loot_organization()
		return

	var remaining_amount: int = 0

	for loot in temporary_loot:
		remaining_amount += maxi(
			int(loot.get("amount", 0)),
			0
		)

	discard_loot_dialog.dialog_text = (
		"가방에 넣지 않은 전리품이 %d개 남아 있습니다."
		% remaining_amount
		+ "\n남은 전리품을 포기하고 진행하시겠습니까?"
	)

	discard_loot_dialog.popup_centered()

# =========================================================
# 전투 진행과 전리품 생성
# =========================================================

func start_test_battle(
	enemy_id: String = "field_slime"
):
	if battle_active:
		return

	var enemy: Dictionary = (
		EnemyData.get_enemy(
			enemy_id
		)
	)

	if enemy.is_empty():
		return

	combat_enemy_id = enemy_id

	combat_enemy_name = str(
		enemy.get(
			"name",
			combat_enemy_id
		)
	)

	combat_enemy_max_hp = int(
		enemy.get(
			"max_hp",
			1
		)
	)

	combat_enemy_hp = combat_enemy_max_hp

	combat_enemy_attack = int(
		enemy.get(
			"attack",
			1
		)
	)

	combat_enemy_defense = int(
		enemy.get(
			"defense",
			0
		)
	)

	battle_active = true

	start_battle_button.disabled = true

	battle_status_label.text = (
		combat_enemy_name
		+ " 등장"
	)

	update_battle_ui()

	battle_timer.start()

func process_battle_tick():
	if not battle_active:
		return

	var damage_to_enemy: int = max(
		1,
		combat_player_attack
		- combat_enemy_defense
	)

	var damage_to_player: int = max(
		1,
		combat_enemy_attack
		- combat_player_defense
	)

	# 같은 1초 안에 서로 동시에 피해
	combat_enemy_hp -= damage_to_enemy
	combat_player_hp -= damage_to_player

	combat_enemy_hp = max(
		0,
		combat_enemy_hp
	)

	combat_player_hp = max(
		0,
		combat_player_hp
	)

	DebugLog.write(
		"[전투] 플레이어 → ",
		combat_enemy_name,
		" ",
		damage_to_enemy,
		" 피해"
	)

	DebugLog.write(
		"[전투] ",
		combat_enemy_name,
		" → 플레이어 ",
		damage_to_player,
		" 피해"
	)

	update_battle_ui()

	check_battle_result()

func check_battle_result() -> void:
	if (
		combat_player_hp > 0
		and combat_enemy_hp > 0
	):
		return

	battle_active = false
	battle_timer.stop()

	start_battle_button.disabled = false

	# 동시 전투 불능도 플레이어 패배로 처리
	if combat_player_hp <= 0:
		var defeat_message: String = (
			"체력이 모두 소진되어 원정을 종료합니다."
		)

		if combat_enemy_hp <= 0:
			battle_status_label.text = "동시 전투 불능"
		else:
			battle_status_label.text = "전투 패배"

		battle_panel.visible = false
		map_panel.visible = false

		DebugLog.write("[원정] 전투 불능 → 결과 안내")

		show_run_messages(
			[defeat_message],
		Callable(
			self,
			"open_result_phase"
		).bind(
			ExpeditionEndReason.DEFEAT
		)
		)

		return

	# 플레이어가 생존한 상태에서 적을 처치
	battle_status_label.text = (
		combat_enemy_name + " 처치"
	)

	DebugLog.write(
		"[전투] 승리 / 남은 HP: ",
		combat_player_hp
	)

	generate_enemy_loot(
		combat_enemy_id
	)

	battle_panel.visible = false

	if temporary_loot.is_empty():
		complete_current_map_node()
	else:
		loot_panel.visible = true



func update_battle_ui():
	player_hp_label.text = (
		"플레이어 HP: "
		+ str(combat_player_hp)
		+ " / "
		+ str(combat_player_max_hp)
	)

	if combat_enemy_name.is_empty():
		enemy_hp_label.text = "적 HP: -"

	else:
		enemy_hp_label.text = (
			combat_enemy_name
			+ " HP: "
			+ str(combat_enemy_hp)
			+ " / "
			+ str(combat_enemy_max_hp)
		)

	update_player_stats_ui()

func generate_enemy_loot(
	enemy_id: String
) -> void:
	temporary_loot.clear()
	refresh_loot_ui()

	var result: Dictionary = (
		expedition_loot_service.roll_enemy_loot(
			enemy_id
		)
	)

	if not bool(
		result.get(
			"success",
			false
		)
	):
		push_error(
			"[전투 전리품] "
			+ str(
				result.get(
					"message",
					"전리품 추첨 실패"
				)
			)
		)
		return

	var item_id: String = str(
		result.get(
			"item_id",
			""
		)
	)

	var amount: int = int(
		result.get(
			"amount",
			0
		)
	)

	temporary_loot.append(
		{
			"item_id": item_id,
			"amount": amount
		}
	)

	refresh_loot_ui()

	DebugLog.write(
		"[전투 전리품] ",
		ItemData.get_item_name(item_id),
		" ×",
		amount
	)

# =========================================================
# 원정 지도와 노드 이동
# =========================================================

func print_expedition_map():
	DebugLog.write("===== 원정 맵 =====")

	for layer_index in range(
		expedition_map.layers.size()
	):
		var layer: Array = (
			expedition_map.layers[
				layer_index
			]
		)

		var text: String = (
			"층 "
			+ str(layer_index)
			+ ": "
		)

		for node in layer:
			text += (
				"["
				+ str(node["type"])
				+ " / "
				+ str(node["id"])
				+ "] "
			)

		DebugLog.write(text)

	DebugLog.write("===================")

func get_map_node_display_name(
	node_type: String
) -> String:
	match node_type:
		ExpeditionMap.NODE_BATTLE:
			return "전투"

		ExpeditionMap.NODE_GATHER:
			return "채집"

		ExpeditionMap.NODE_UNKNOWN:
			return "미지"

		ExpeditionMap.NODE_TREASURE:
			return "보물"

		ExpeditionMap.NODE_BOSS:
			return "보스"

		"start":
			return "시작"

	return "?"

func is_map_node_reachable(
	node_id: String
) -> bool:
	var current_node: Dictionary = (
		expedition_map.get_node(
			current_map_node_id
		)
	)

	if current_node.is_empty():
		return false

	var next_nodes: Array = (
		current_node.get(
			"next",
			[]
		)
	)

	return next_nodes.has(
		node_id
	)

func refresh_map_ui():
	for child in map_layers.get_children():
		child.queue_free()

	# 화면에서는 보스가 위쪽,
	# 시작점이 아래쪽에 보이도록 역순 출력
	for layer_index in range(
		expedition_map.layers.size() - 1,
		-1,
		-1
	):
		var layer: Array = (
			expedition_map.layers[
				layer_index
			]
		)

		var row := HBoxContainer.new()

		row.alignment = (
			BoxContainer.ALIGNMENT_CENTER
		)

		row.add_theme_constant_override(
			"separation",
			25
		)

		map_layers.add_child(row)

		for node in layer:
			var node_id: String = str(
				node.get(
					"id",
					""
				)
			)

			var node_type: String = str(
				node.get(
					"type",
					""
				)
			)

			var button := Button.new()

			button.set_meta(
				"map_node_id",
				node_id
			)

			button.custom_minimum_size = Vector2(
				90,
				45
			)

			button.text = (
				get_map_node_display_name(
					node_type
				)
			)

			# 현재 위치
			if node_id == current_map_node_id:
				button.text = (
					"[현재]\n"
					+ button.text
				)

				button.disabled = true

			# 지나간 위치
			elif visited_map_node_ids.has(
				node_id
			):
				button.text = (
					"[지남]\n"
					+ button.text
				)

				button.disabled = true

			# 현재 위치에서 이동 가능한 곳
			elif is_map_node_reachable(
				node_id
			):
				button.disabled = false

				button.pressed.connect(
					_on_map_node_pressed.bind(
						node_id
					)
				)

			# 아직 갈 수 없는 곳
			else:
				button.disabled = true

			row.add_child(button)

		map_layers.call_deferred(
			"update_lines",
			expedition_map.layers,
			visited_map_node_ids
		)

func _on_map_node_pressed(
	node_id: String
):
	if not is_map_node_reachable(
		node_id
	):
		return

	var node: Dictionary = (
		expedition_map.get_node(
			node_id
		)
	)

	if node.is_empty():
		return

	selected_map_node_id = node_id

	var node_type: String = str(
		node.get(
			"type",
			""
		)
	)

	DebugLog.write(
		"[원정 맵] 진입: ",
		node_id,
		" / ",
		node_type
	)

	map_panel.visible = false

	match node_type:
		ExpeditionMap.NODE_BATTLE, \
		ExpeditionMap.NODE_GATHER, \
		ExpeditionMap.NODE_UNKNOWN, \
		ExpeditionMap.NODE_TREASURE, \
		ExpeditionMap.NODE_BOSS:
			start_event_node(
				node_type
			)

		_:
			push_warning(
				"[원정] 처리되지 않은 노드 타입: "
				+ node_type
			)

			complete_current_map_node()

func start_event_node(
	node_type: String
) -> void:
	var allow_heal_event: bool = (
		combat_player_hp
		< combat_player_max_hp
	)

	var event: Dictionary = (
		ExpeditionEventData.get_random_event(
			current_region_id,
			node_type,
			GameState.current_day,
			allow_heal_event
		)
	)
	if event.is_empty():
		push_error(
			"[원정] 사용할 이벤트가 없습니다."
			+ " / 지역: "
			+ current_region_id
			+ " / 노드: "
			+ node_type
			+ " / 요일: "
			+ str(GameState.current_day)
		)

		complete_current_map_node()
		return

	DebugLog.write(
		"[원정 이벤트] 선택"
		+ " / 노드: ",
		node_type,
		" / 이벤트: ",
		event.get(
			"event_id",
			""
		)
	)

	resolve_expedition_event(
		event
	)

func start_map_battle(
	enemy_id: String = "field_slime"
):
	battle_panel.visible = true
	loot_panel.visible = false

	start_test_battle(
		enemy_id
	)

func complete_current_map_node():
	if selected_map_node_id.is_empty():
		return

	current_map_node_id = (
		selected_map_node_id
	)

	selected_map_node_id = ""

	if not visited_map_node_ids.has(
		current_map_node_id
	):
		visited_map_node_ids.append(
			current_map_node_id
		)

	battle_panel.visible = false
	loot_panel.visible = false
	map_panel.visible = true

	refresh_map_ui()

	DebugLog.write(
		"[원정 맵] 노드 완료: ",
		current_map_node_id
	)

	DebugLog.write(
		"[원정 맵] 지나온 경로: ",
		visited_map_node_ids
	)

	# =========================
	# 보스 완료 → 원정 결과
	# =========================

	var completed_node: Dictionary = (
		expedition_map.get_node(
			current_map_node_id
		)
	)

	if not completed_node.is_empty():
		var completed_node_type: String = str(
			completed_node.get(
				"type",
				""
			)
		)

		if completed_node_type == ExpeditionMap.NODE_BOSS:
			DebugLog.write(
				"[원정] 보스 완료 → RESULT"
			)

			open_result_phase(
				ExpeditionEndReason.BOSS_CLEAR
			)
			return

# =========================================================
# 원정 단계 전환과 결과 정산
# =========================================================

func set_expedition_phase(
	new_phase: ExpeditionPhase
):
	current_expedition_phase = new_phase

	prep_panel.visible = (
		new_phase == ExpeditionPhase.PREP
	)

	result_panel.visible = (
		new_phase == ExpeditionPhase.RESULT
	)

	player_stats_label.visible = (
		new_phase == ExpeditionPhase.RUN
	)

	# RUN에서 기본적으로 보이는 것
	bag_panel.visible = (
		new_phase == ExpeditionPhase.RUN
	)

	map_panel.visible = (
		new_phase == ExpeditionPhase.RUN
	)

	# 전투/전리품은 RUN 중 필요할 때만 별도로 연다.
	battle_panel.visible = false
	loot_panel.visible = false

	# 기존 원정 종료 버튼
	complete_button.visible = (
		new_phase == ExpeditionPhase.RUN
	)

	if new_phase == ExpeditionPhase.PREP:
		prep_title_label.text = "원정 목적지"

		if prep_panel.has_method("refresh_current_tab"):
			prep_panel.call("refresh_current_tab")


	if new_phase == ExpeditionPhase.RESULT:
		result_confirm_button.text = "편의점으로 복귀"

	if is_instance_valid(game_menu):
		game_menu.visible = true
		game_menu.z_index = 1000

	if has_node("PreparationVillage"):
		$PreparationVillage.sync_phase()
		$PreparationVillage.clock_hud.show()

func start_expedition_run() -> void:
	if (
		current_expedition_phase
		!= ExpeditionPhase.PREP
	):
		return

	# =========================
	# PREP 가방 가져오기
	# =========================

	if not prep_panel.has_method(
		"get_prepared_bag_model"
	):
		status_label.text = (
			"준비된 가방을 확인할 수 없습니다."
		)
		prep_panel.call("show_preparation_message",status_label.text)

		push_error(
			"[원정] PrepPanel에서 가방을 가져올 수 없습니다."
		)
		return

	var prepared_bag: Variant = (
		prep_panel.call(
			"get_prepared_bag_model"
		)
	)

	if prepared_bag == null:
		status_label.text = (
			"준비된 가방 데이터가 없습니다."
		)
		prep_panel.call("show_preparation_message",status_label.text)

		push_error(
			"[원정] 준비된 가방 데이터가 없습니다."
		)
		return

	expedition_bag = prepared_bag

	var loadout_result: Dictionary = (
		ExpeditionLoadoutService.validate_loadout(
			expedition_bag
		)
	)

	if not bool(
		loadout_result.get(
			"success",
			false
		)
	):
		status_label.text = str(
			loadout_result.get(
				"message",
				"장착 구성을 확인해주세요."
			)
		)
		prep_panel.call("show_preparation_message",status_label.text)

		push_warning(
			"[원정 출발] 장착 구성 오류: "
			+ status_label.text
		)

		return

	apply_bag_equipment_stats()
	update_player_stats_ui()

	setup_bag_grid_view()

	# =========================
	# 선택 지역 가져오기
	# =========================

	current_region_id = GameConfig.DEFAULT_REGION_ID

	if prep_panel.has_method(
		"get_selected_region_id"
	):
		current_region_id = str(
			prep_panel.call(
				"get_selected_region_id"
			)
		)

	# =========================
	# 출발 검사와 맵 준비
	# =========================

	var departure_result: Dictionary = (
		expedition_departure_service.prepare_departure(
			current_region_id,
			GameState.current_day
		)
	)

	if not bool(
		departure_result.get(
			"success",
			false
		)
	):
		status_label.text = str(
			departure_result.get(
				"message",
				"원정을 시작하지 못했습니다."
			)
		)
		prep_panel.call("show_preparation_message",status_label.text)

		var debug_message: String = str(
			departure_result.get(
				"debug_message",
				""
			)
		)

		if not debug_message.is_empty():
			push_error(debug_message)

		if prep_panel.has_method(
			"refresh_current_tab"
		):
			prep_panel.call(
				"refresh_current_tab"
			)

		refresh_start_expedition_button()
		return

	var prepared_map := (
		departure_result.get(
			"map",
			null
		) as ExpeditionMap
	)

	if prepared_map == null:
		status_label.text = (
			"준비된 원정 지도를 확인할 수 없습니다."
		)
		prep_panel.call("show_preparation_message",status_label.text)

		push_error(
			"[원정] 서비스 결과에 맵이 없습니다."
		)
		return

	expedition_map = prepared_map

	current_map_node_id = str(
		departure_result.get(
			"start_node_id",
			""
		)
	)

	# =========================
	# PREP 종료
	# =========================

	if prep_panel.has_method(
		"prepare_for_departure"
	):
		prep_panel.call(
			"prepare_for_departure"
		)

	selected_map_node_id = ""
	visited_map_node_ids.clear()

	visited_map_node_ids.append(
		current_map_node_id
	)

	# 원정 하루를 시작할 때 체력 회복
	combat_player_hp = combat_player_max_hp

	DebugLog.write(
		"[원정] 출발 / 지역: ",
		current_region_id,
		" / 가방 배치: ",
		expedition_bag.placements.size()
	)

	print_expedition_map()

	# =========================
	# RUN 시작
	# =========================

	set_expedition_phase(
		ExpeditionPhase.RUN
	)

	update_battle_ui()
	refresh_map_ui()
	refresh_bag_ui()

func cancel_expedition_preparation() -> void:
	if current_expedition_phase != ExpeditionPhase.PREP or preparation_return_pending:
		return
	if expedition_bag != null:
		GameState.save_expedition_bag(expedition_bag.placements)
	preparation_return_pending = true
	call_deferred("_commit_preparation_return")

func _commit_preparation_return() -> void:
	if not preparation_return_pending or not is_inside_tree():
		return
	var scene_error: Error = get_tree().change_scene_to_file(GameConfig.MAIN_SCENE_PATH)
	if scene_error != OK:
		preparation_return_pending = false
		prep_panel.call("show_preparation_message","마을로 돌아가지 못했습니다. 다시 시도해주세요.")
		push_error("[원정 준비] 마을 복귀 실패: " + str(scene_error))

func open_result_phase(
	end_reason: ExpeditionEndReason = (
		ExpeditionEndReason.RETREAT
	)
) -> void:
	if current_expedition_phase != ExpeditionPhase.RUN:
		return

	if battle_active:
		status_label.text = "전투를 마친 뒤 종료할 수 있습니다."
		return

	if (
		message_panel.visible
		or not run_message_queue.is_empty()
		or run_message_finish_action.is_valid()
	):
		status_label.text = "이벤트 안내를 먼저 완료해주세요."
		return

	# 빈 전리품 창도 확인 버튼으로 정리를 마쳐야 한다.
	if (
		loot_panel.visible
		or not temporary_loot.is_empty()
	):
		status_label.text = "전리품 정리를 먼저 완료해주세요."
		return

	current_end_reason = end_reason

	update_ui()

	result_info_label.text = (
		get_expedition_end_reason_text(
			current_end_reason
		)
		+ "\n\n"
		+ expedition_result_service.build_result_text(
			expedition_bag,
			get_day_name()
		)
	)

	DebugLog.write("[원정] 원정 종료 → 결과")

	set_expedition_phase(
		ExpeditionPhase.RESULT
	)

func confirm_result_phase() -> void:
	if (
		current_expedition_phase
		!= ExpeditionPhase.RESULT
	):
		return

	var settlement: Dictionary = (
		expedition_result_service.deposit_items(
			expedition_bag
		)
	)

	if not bool(
		settlement.get(
			"success",
			false
		)
	):
		result_info_label.text = (
			"아이템 정산을 완료하지 못했습니다."
			+ "\n"
			+ str(
				settlement.get(
					"message",
					"오류 내용을 확인해주세요."
				)
			)
		)
		return

	selected_bag_uid = -1
	refresh_bag_ui()

	DebugLog.write(
		"[원정 정산] 자동 보관 수량: ",
		settlement.get(
			"deposited_amount",
			0
		)
	)

	finish_expedition()

func reset_for_next_expedition_day():
	temporary_loot.clear()

	selected_bag_uid = -1
	selected_map_node_id = ""
	current_map_node_id = ""
	current_region_id = GameConfig.DEFAULT_REGION_ID

	visited_map_node_ids.clear()

	battle_active = false
	battle_timer.stop()

	current_end_reason = (
		ExpeditionEndReason.RETREAT
	)


	# =========================
	# 가방은 새로 만들지 않는다
	# =========================

	refresh_bag_ui()
	refresh_loot_ui()

	if bag_content.has_method(
		"refresh_all"
	):
		bag_content.call(
			"refresh_all"
	)

	DebugLog.write(
		"[원정] 가방 유지 / 남은 아이템: ",
		expedition_bag.placements.size()
	)

	# 다음 원정 맵은 지역을 선택하고 출발할 때 생성한다.
	expedition_map = null

	DebugLog.write(
		"[원정] 정비 준비 완료"
	)

# =========================================================
# 장비 능력치와 진행 메시지
# =========================================================

func apply_bag_equipment_stats() -> void:
	var bonus_attack: int = 0
	var bonus_defense: int = 0

	if expedition_bag == null:
		combat_player_attack = BASE_PLAYER_ATTACK
		combat_player_defense = BASE_PLAYER_DEFENSE
		return

	for placement in expedition_bag.placements:
		var item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		if item_id.is_empty():
			continue

		if not ExpeditionEquipmentData.has_equipment(
			item_id
		):
			continue

		var equipment_type: String = (
			ExpeditionEquipmentData.get_equipment_type(
				item_id
			)
		)

		# 전투 능력치에는 무기와 방어구만 반영한다.
		if (
			equipment_type
			!= ExpeditionEquipmentData.TYPE_WEAPON
			and equipment_type
			!= ExpeditionEquipmentData.TYPE_ARMOR
		):
			continue

		var effect_id: String = (
			ExpeditionEquipmentData.get_effect_id(
				item_id
			)
		)

		var effective_value: int = int(
			EquipmentEnhancementService.get_effective_value(
				placement
			)
		)

		match effect_id:
			"attack":
				bonus_attack += effective_value

			"defense":
				bonus_defense += effective_value

			_:
				push_warning(
					"[원정 능력치] 처리되지 않은 장비 효과"
					+ " / 아이템: "
					+ item_id
					+ " / 효과: "
					+ effect_id
				)

	combat_player_attack = (
		BASE_PLAYER_ATTACK
		+ bonus_attack
	)

	combat_player_defense = (
		BASE_PLAYER_DEFENSE
		+ bonus_defense
	)

	DebugLog.write(
		"[원정 능력치]"
		+ " / 기본 공격: ",
		BASE_PLAYER_ATTACK,
		" / 장비 공격: ",
		bonus_attack,
		" / 최종 공격: ",
		combat_player_attack,
		" / 기본 방어: ",
		BASE_PLAYER_DEFENSE,
		" / 장비 방어: ",
		bonus_defense,
		" / 최종 방어: ",
		combat_player_defense
	)

func update_player_stats_ui() -> void:
	player_stats_label.text = (
		"HP %d/%d | 공격 %d | 방어 %d"
		% [
			combat_player_hp,
			combat_player_max_hp,
			combat_player_attack,
			combat_player_defense
		]
	)


func _open_loot_after_message() -> void:
	refresh_loot_ui()

	if temporary_loot.is_empty():
		complete_current_map_node()
		return

	map_panel.visible = false
	battle_panel.visible = false
	loot_panel.visible = true


func show_run_messages(
	messages: Array[String],
	finish_action: Callable = Callable()
) -> void:
	run_message_queue.clear()

	for message in messages:
		run_message_queue.append(
			message
		)

	run_message_finish_action = (
		finish_action
	)

	message_panel.visible = true

	_show_next_run_message()


func _show_next_run_message() -> void:
	if run_message_queue.is_empty():
		message_panel.visible = false

		var finish_action := (
			run_message_finish_action
		)

		run_message_finish_action = (
			Callable()
		)

		if finish_action.is_valid():
			finish_action.call()

		return

	message_label.text = (
		run_message_queue.pop_front()
	)


func _on_message_continue_pressed() -> void:
	if current_expedition_phase != ExpeditionPhase.RUN:
		return

	if not message_panel.visible:
		return

	_show_next_run_message()

	# 종료 제한 안내를 원래 상태 문구로 복구
	if not message_panel.visible:
		update_ui()

# =========================================================
# 원정 이벤트 처리
# =========================================================

func resolve_expedition_event(
	event: Dictionary
) -> void:
	var message := str(
		event.get(
			"message",
			""
		)
	)

	var result_type := str(
		event.get(
			"result_type",
			"none"
		)
	)

	var target_id := str(
		event.get(
			"target_id",
			""
		)
	)

	var value := int(
		event.get(
			"value",
			0
		)
	)

	match result_type:
		"battle":
			show_run_messages(
				[
					message
				],
				Callable(
					self,
					"_start_csv_event_battle"
				).bind(
					target_id
				)
			)

		"loot":
			_resolve_csv_loot_event(
				message,
				target_id
			)

		"heal":
			_resolve_csv_heal_event(
				message,
				value
			)

		"none":
			show_run_messages(
				[
					message
				],
				Callable(
					self,
					"complete_current_map_node"
				)
			)

		_:
			push_warning(
				"[원정] 알 수 없는 result_type: "
				+ result_type
			)

			complete_current_map_node()

func _start_csv_event_battle(
	enemy_id: String
) -> void:
	if enemy_id.is_empty():
		push_warning(
			"[원정] 적 ID가 비어 있습니다."
		)

		complete_current_map_node()
		return

	start_map_battle(
		enemy_id
	)

func _resolve_csv_heal_event(
	message: String,
	heal_amount: int
) -> void:
	var before_hp: int = (
		combat_player_hp
	)

	var safe_heal_amount: int = max(
		heal_amount,
		0
	)

	combat_player_hp = min(
		combat_player_hp + safe_heal_amount,
		combat_player_max_hp
	)

	var healed: int = (
		combat_player_hp
		- before_hp
	)

	update_battle_ui()

	var result_message: String

	if healed <= 0:
		result_message = (
			"이미 체력이 가득 차 있다."
		)
	else:
		result_message = (
			"HP를 %d 회복했다!"
			% healed
		)

	show_run_messages(
		[
			message,
			result_message
		],
		Callable(
			self,
			"complete_current_map_node"
		)
	)

func _resolve_csv_loot_event(
	message: String,
	table_id: String
) -> void:
	temporary_loot.clear()

	var gathering_result: Dictionary = (
		expedition_gathering_service.resolve_gathering(
			table_id,
			expedition_bag,
			expedition_loot_service
		)
	)

	var gathering_handled: bool = bool(
		gathering_result.get(
			"handled",
			false
		)
	)

	# =========================
	# 도구 채집 규칙이 있는 전리품
	# =========================

	if gathering_handled:
		var gathering_success: bool = bool(
			gathering_result.get(
				"success",
				false
			)
		)

		if not gathering_success:
			var error_message: String = str(
				gathering_result.get(
					"message",
					"채집 정보를 확인할 수 없습니다."
				)
			)

			push_error(
				"[원정 채집] " + error_message
			)

			show_run_messages(
				[
					message,
					error_message
				],
				Callable(
					self,
					"complete_current_map_node"
				)
			)
			return

		var gathered: bool = bool(
			gathering_result.get(
				"gathered",
				false
			)
		)

		var gathering_message: String = str(
			gathering_result.get(
				"message",
				""
			)
		)

		# 도구 부족 또는 확률 판정 실패
		if not gathered:
			show_run_messages(
				[
					message,
					gathering_message
				],
				Callable(
					self,
					"complete_current_map_node"
				)
			)
			return

		var gathered_item_id: String = str(
			gathering_result.get(
				"item_id",
				""
			)
		)

		var gathered_amount: int = int(
			gathering_result.get(
				"amount",
				0
			)
		)

		temporary_loot.append(
			{
				"item_id": gathered_item_id,
				"amount": gathered_amount
			}
		)

		map_panel.visible = false
		battle_panel.visible = false
		loot_panel.visible = false

		show_run_messages(
			[
				message,
				gathering_message,
				"%s ×%d 획득!"
				% [
					ItemData.get_item_name(
						gathered_item_id
					),
					gathered_amount
				]
			],
			Callable(
				self,
				"_open_loot_after_message"
			)
		)
		return

	# =========================
	# 기존 일반 전리품 처리
	# =========================

	var result: Dictionary = (
		expedition_loot_service.roll_loot_table(
			table_id
		)
	)

	if not bool(
		result.get(
			"success",
			false
		)
	):
		push_error(
			"[원정 전리품] "
			+ str(
				result.get(
					"message",
					"전리품 추첨 실패"
				)
			)
		)

		show_run_messages(
			[
				message,
				"전리품 정보를 확인할 수 없습니다."
			],
			Callable(
				self,
				"complete_current_map_node"
			)
		)
		return

	var item_id: String = str(
		result.get(
			"item_id",
			""
		)
	)

	var amount: int = int(
		result.get(
			"amount",
			0
		)
	)

	temporary_loot.append(
		{
			"item_id": item_id,
			"amount": amount
		}
	)

	map_panel.visible = false
	battle_panel.visible = false
	loot_panel.visible = false

	show_run_messages(
		[
			message,
			"%s ×%d 발견!"
			% [
				ItemData.get_item_name(item_id),
				amount
			]
		],
		Callable(
			self,
			"_open_loot_after_message"
		)
	)

func _finish_loot_organization() -> void:
	if current_expedition_phase != ExpeditionPhase.RUN:
		return

	if not loot_panel.visible:
		return

	if not temporary_loot.is_empty():
		DebugLog.write(
			"[전리품] 포기한 아이템: ",
			temporary_loot
		)

	temporary_loot.clear()
	selected_bag_uid = -1

	refresh_loot_ui()
	refresh_bag_ui()

	loot_panel.visible = false

	update_ui()

	DebugLog.write("[전리품] 정리 완료 / 가방 아이템 유지")

	complete_current_map_node()


func _on_prep_region_changed(
	region_id: String
) -> void:
	refresh_start_expedition_button(
		region_id
	)

func refresh_start_expedition_button(
	region_id: String = ""
) -> void:
	if region_id.is_empty():
		if prep_panel.has_method(
			"get_selected_region_id"
		):
			region_id = str(
				prep_panel.call(
					"get_selected_region_id"
				)
			)

	var region_data: Dictionary = (
		ExpeditionMapData.get_region_data(
			region_id
		)
	)

	if region_data.is_empty():
		start_expedition_button.text = (
			"출발할 지역을 선택하세요"
		)

		start_expedition_button.disabled = true
		return

	var available: bool = (
		ExpeditionMapData.can_enter_region(
			region_id
		)
	)
	start_expedition_button.text = (
		"원정 출발" if available else "입장 조건 부족"
	)

	start_expedition_button.disabled = (
		not available
	)

func get_expedition_end_reason_text(
	end_reason: ExpeditionEndReason
) -> String:
	match end_reason:
		ExpeditionEndReason.RETREAT:
			return "원정을 중단하고 귀환했습니다."

		ExpeditionEndReason.BOSS_CLEAR:
			return "지역의 보스를 처치했습니다!"

		ExpeditionEndReason.DEFEAT:
			return "전투 불능이 되어 원정이 종료되었습니다."

	return ""

# =========================================================
# 원정 체크포인트 저장과 복원
# =========================================================

func can_save_expedition_checkpoint() -> bool:
	if expedition_bag == null:
		return false

	# 원정 준비 화면에서는 저장 가능
	if current_expedition_phase == ExpeditionPhase.PREP:
		return true

	# 결과 정산 화면에서는 저장하지 않는다.
	if current_expedition_phase != ExpeditionPhase.RUN:
		return false

	if battle_active:
		return false

	if not battle_timer.is_stopped():
		return false

	if message_panel.visible:
		return false

	if not run_message_queue.is_empty():
		return false

	if run_message_finish_action.is_valid():
		return false

	if loot_panel.visible:
		return false

	if not temporary_loot.is_empty():
		return false

	if not selected_map_node_id.is_empty():
		return false

	if discard_loot_dialog.visible:
		return false

	# 다음 경로를 선택하는 지도 화면에서만 저장 가능
	return map_panel.visible

func _get_map_layers_for_save() -> Array:
	var saved_layers: Array = []

	if expedition_map == null:
		return saved_layers

	for raw_layer in expedition_map.layers:
		if not raw_layer is Array:
			continue

		saved_layers.append(
			raw_layer.duplicate(true)
		)

	return saved_layers

func create_expedition_checkpoint_data() -> Dictionary:
	if not can_save_expedition_checkpoint():
		return {}

	var saved_region_id: String = (
		current_region_id
	)

	if (
		current_expedition_phase
		== ExpeditionPhase.PREP
		and prep_panel.has_method(
			"get_selected_region_id"
		)
	):
		saved_region_id = str(
			prep_panel.call(
				"get_selected_region_id"
			)
		)

	return {
		"checkpoint_version": 1,
		"shop_return_context": GameState.get_meta("shop_return_context",{}).duplicate(true),
		"current_day": current_day,
		"phase": int(current_expedition_phase),
		"region_id": saved_region_id,

		"bag_placements": (
			expedition_bag.placements.duplicate(true)
		),

		"map_layers": (
			_get_map_layers_for_save()
		),

		"current_map_node_id": (
			current_map_node_id
		),

		"visited_map_node_ids": (
			visited_map_node_ids.duplicate()
		),

		"combat_player_hp": combat_player_hp,
		"combat_player_max_hp": combat_player_max_hp,
	}

func save_expedition_checkpoint(
	target_path: String = GameState.SAVE_PATH
) -> bool:
	save_failure_reason = ""

	if not can_save_expedition_checkpoint():
		save_failure_reason = (
			"현재 진행을 마친 뒤 저장해주세요."
		)
		return false

	var checkpoint_data: Dictionary = (
		create_expedition_checkpoint_data()
	)

	if checkpoint_data.is_empty():
		save_failure_reason = (
			"원정 저장 정보를 만들지 못했습니다."
		)
		return false

	# 현재 원정 가방도 공통 저장 데이터에 반영
	GameState.save_expedition_bag(
		expedition_bag.placements
	)

	GameState.current_day = current_day

	GameState.set_expedition_checkpoint(
		checkpoint_data
	)

	var save_data: Dictionary = (
		GameState.create_save_data()
	)

	var save_result: Dictionary = (
		checkpoint_file_service.write_verified_checkpoint(
			save_data,
			target_path
		)
	)

	if not bool(
		save_result.get(
			"success",
			false
		)
	):
		save_failure_reason = str(
			save_result.get(
				"message",
				"원정 데이터를 저장하지 못했습니다."
			)
		)
		return false

	return true

func restore_expedition_checkpoint() -> bool:
	if not GameState.has_expedition_checkpoint():
		return false

	var checkpoint: Dictionary = (
		GameState.expedition_checkpoint.duplicate(true)
	)

	GameState.set_meta("shop_return_context",checkpoint.get("shop_return_context",{}).duplicate(true))

	var saved_phase: int = int(
		checkpoint.get(
			"phase",
			ExpeditionPhase.PREP
		)
	)

	current_day = int(
		checkpoint.get(
			"current_day",
			GameState.current_day
		)
	)

	GameState.current_day = current_day

	current_region_id = str(
		checkpoint.get(
			"region_id",
			GameConfig.DEFAULT_REGION_ID
		)
	)

	var saved_bag: Variant = (
		checkpoint.get(
			"bag_placements",
			[]
		)
	)

	if saved_bag is Array:
		if not expedition_bag.load_placements(
			saved_bag
		):
			push_error(
				"[원정 복원] 가방 배치를 복원하지 못했습니다."
			)
			return false

	combat_player_max_hp = maxi(
		int(
			checkpoint.get(
				"combat_player_max_hp",
				100
			)
		),
		1
	)

	combat_player_hp = clampi(
		int(
			checkpoint.get(
				"combat_player_hp",
				combat_player_max_hp
			)
		),
		0,
		combat_player_max_hp
	)

	# 준비 화면 저장 복원
	if saved_phase == ExpeditionPhase.PREP:
		set_expedition_phase(
			ExpeditionPhase.PREP
		)

		setup_bag_grid_view()
		refresh_bag_ui()
		update_ui()

		DebugLog.write(
			"[원정 복원] 준비 화면 복원 완료"
		)

		return true

	# 현재는 PREP와 안전한 RUN만 저장한다.
	if saved_phase != ExpeditionPhase.RUN:
		push_error(
			"[원정 복원] 지원하지 않는 원정 단계입니다."
		)
		return false

	var saved_layers: Variant = (
		checkpoint.get(
			"map_layers",
			[]
		)
	)

	if (
		not saved_layers is Array
		or saved_layers.is_empty()
	):
		push_error(
			"[원정 복원] 저장된 지도 정보가 없습니다."
		)
		return false

	var restored_map := ExpeditionMap.new()

	restored_map.region_id = current_region_id
	restored_map.layers.clear()

	for raw_layer in saved_layers:
		if not raw_layer is Array:
			continue

		restored_map.layers.append(
			raw_layer.duplicate(true)
		)

	if restored_map.layers.is_empty():
		push_error(
			"[원정 복원] 지도 층을 복원하지 못했습니다."
		)
		return false

	restored_map.layer_count = (
		restored_map.layers.size()
	)

	expedition_map = restored_map

	current_map_node_id = str(
		checkpoint.get(
			"current_map_node_id",
			""
		)
	)

	selected_map_node_id = ""
	visited_map_node_ids.clear()

	var saved_visited_nodes: Variant = (
		checkpoint.get(
			"visited_map_node_ids",
			[]
		)
	)

	if saved_visited_nodes is Array:
		for raw_node_id in saved_visited_nodes:
			visited_map_node_ids.append(
				str(raw_node_id)
			)

	if current_map_node_id.is_empty():
		push_error(
			"[원정 복원] 현재 지도 위치가 없습니다."
		)
		return false

	temporary_loot.clear()
	run_message_queue.clear()
	run_message_finish_action = Callable()

	battle_active = false
	battle_timer.stop()

	message_panel.visible = false
	battle_panel.visible = false
	loot_panel.visible = false

	apply_bag_equipment_stats()
	setup_bag_grid_view()

	set_expedition_phase(
		ExpeditionPhase.RUN
	)

	update_ui()
	update_battle_ui()
	refresh_bag_ui()
	refresh_map_ui()

	DebugLog.write(
		"[원정 복원] 진행 상태 복원 완료"
		+ " / 위치: ",
		current_map_node_id
	)

	return true

func _on_game_menu_save_slot_requested(
	path: String,
	slot_index: int
) -> void:
	var success: bool = (
		save_expedition_checkpoint(
			path
		)
	)

	game_menu.notify_save_finished(
		success
	)

	if success:
		status_label.text = (
			"세이브 슬롯 "
			+ str(slot_index + 1)
			+ " 저장 완료"
		)

		DebugLog.write(
			"[원정 저장] 슬롯 ",
			slot_index + 1,
			" 저장 완료"
		)
	else:
		status_label.text = (
			save_failure_reason
		)

		DebugLog.write(
			"[원정 저장] 실패 / ",
			save_failure_reason
		)

func _on_game_menu_return_title_requested() -> void:
	battle_active = false
	battle_timer.stop()

	var scene_error: Error = (
		get_tree().change_scene_to_file(
			GameConfig.TITLE_SCENE_PATH
		)
	)

	if scene_error != OK:
		status_label.text = (
			"시작 화면으로 돌아가지 못했습니다."
		)

		push_error(
			"[원정 메뉴] 시작 화면 전환 실패: "
			+ str(scene_error)
		)

func _install_preparation_village() -> void:
	var village = preload("res://script/expedition/preparation_village.gd").new()
	village.name = "PreparationVillage"
	add_child(village)
	village.sync_phase()
	if bool(GameState.get_meta("shop_expedition_prep",false)):
		GameState.remove_meta("shop_expedition_prep")
		prep_panel.call("show_departure_choice")
		prep_panel.show()
		village.hud.hide()
		village.clock_hud.hide()
		game_menu.hide()
