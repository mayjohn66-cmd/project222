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
	$UI/ResultPanel/VBoxContainer/ResultScroll/ResultInfoLabel
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
var expedition_room_controller := ExpeditionRoomController.new()

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

# 체크포인트 저장·복원. _ready에서 이 씬(host)과 연결한다.
var expedition_checkpoint_controller := (
	ExpeditionCheckpointController.new()
)

# 전투 시작·진행·결과 처리. _ready에서 이 씬(host)과 연결한다.
var expedition_battle_controller := (
	ExpeditionBattleController.new()
)

# 지도 표시, 노드 이동, 노드 완료. _ready에서 이 씬(host)과 연결한다.
var expedition_map_controller := (
	ExpeditionMapController.new()
)

# CSV 이벤트 결과 처리. _ready에서 이 씬(host)과 연결한다.
var expedition_event_controller := (
	ExpeditionEventController.new()
)

# 장비 능력치 계산과 표시. _ready에서 이 씬(host)과 연결한다.
var expedition_stats_controller := (
	ExpeditionStatsController.new()
)

# 진행 메시지 큐. _ready에서 이 씬(host)과 연결한다.
var expedition_message_controller := (
	ExpeditionMessageController.new()
)

# 가방 선택·드래그와 전리품 정리. _ready에서 이 씬(host)과 연결한다.
var expedition_bag_controller := (
	ExpeditionBagController.new()
)
var preparation_return_pending: bool = false





func _ready() -> void:
	expedition_room_controller.setup(self)
	expedition_checkpoint_controller.setup(self)
	expedition_battle_controller.setup(self)
	expedition_map_controller.setup(self)
	expedition_event_controller.setup(self)
	expedition_stats_controller.setup(self)
	expedition_message_controller.setup(self)
	expedition_bag_controller.setup(self)
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

# 현재 원정의 난이도 레벨. 지도가 없으면 기본 난이도.
func get_run_difficulty() -> int:
	if expedition_map == null:
		return ExpeditionDifficultyData.MIN_LEVEL

	return expedition_map.difficulty


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
	return expedition_bag_controller.get_active_bag_placements()

# =========================================================
# 원정 가방과 전리품 정리
# =========================================================
# 가방 선택·드래그 앤 드롭과 전리품 정리는 ExpeditionBagController가 처리한다.
# 그리드 뷰와 전리품 카드가 이 씬을 대상으로 호출하므로 같은 이름의 진입점을 유지한다.

func setup_bag_grid_view() -> void:
	expedition_bag_controller.setup_grid_view()

func refresh_bag_ui() -> void:
	expedition_bag_controller.refresh_bag_ui()

func select_grid_item(
	source: String,
	uid: int
) -> void:
	expedition_bag_controller.select_grid_item(
		source,
		uid
	)


func toggle_grid_item(
	source: String,
	uid: int
) -> void:
	expedition_bag_controller.toggle_grid_item(
		source,
		uid
	)


func is_grid_item_selected(
	source: String,
	uid: int
) -> bool:
	return expedition_bag_controller.is_grid_item_selected(
		source,
		uid
	)


func clear_grid_selection(
	source: String
) -> void:
	expedition_bag_controller.clear_grid_selection(
		source
	)


func can_drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> bool:
	return expedition_bag_controller.can_drop_grid_data(
		target_source,
		data,
		cursor_cell
	)

func drop_grid_data(
	target_source: String,
	data: Dictionary,
	cursor_cell: Vector2i
) -> void:
	expedition_bag_controller.drop_grid_data(
		target_source,
		data,
		cursor_cell
	)

func rotate_selected_bag_item() -> void:
	expedition_bag_controller.rotate_selected_bag_item()

func refresh_loot_ui():
	expedition_bag_controller.refresh_loot_ui()

func return_bag_item_to_loot(
	data: Dictionary
):
	expedition_bag_controller.return_bag_item_to_loot(
		data
	)

func confirm_loot_organization() -> void:
	expedition_bag_controller.confirm_loot_organization()

# =========================================================
# 전투 진행과 전리품 생성
# =========================================================

# 전투 진행은 ExpeditionBattleController가 처리한다.
# 아래 함수는 시그널 연결과 다른 원정 코드가 쓰는 진입점이다.
func start_test_battle(
	enemy_id: String = "field_slime"
):
	expedition_battle_controller.start_battle(
		enemy_id
	)

func process_battle_tick():
	expedition_battle_controller.process_tick()

func check_battle_result() -> void:
	expedition_battle_controller.check_result()

func update_battle_ui():
	expedition_battle_controller.update_ui()

func generate_enemy_loot(
	enemy_id: String
) -> void:
	expedition_battle_controller.generate_loot(
		enemy_id
	)

# =========================================================
# 원정 지도와 노드 이동
# =========================================================

# 지도 표시와 노드 이동은 ExpeditionMapController가 처리한다.
# 아래 함수는 다른 원정 코드와 컨트롤러가 쓰는 진입점이다.
func print_expedition_map():
	expedition_map_controller.print_map()

func get_map_node_display_name(
	node_type: String
) -> String:
	return expedition_map_controller.get_node_display_name(
		node_type
	)

func is_map_node_reachable(
	node_id: String
) -> bool:
	return expedition_map_controller.is_node_reachable(
		node_id
	)

func refresh_map_ui():
	expedition_map_controller.refresh_ui()

func _on_map_node_pressed(
	node_id: String
):
	expedition_map_controller.on_node_pressed(
		node_id
	)

func start_event_node(
	node_type: String
) -> void:
	expedition_map_controller.start_event_node(
		node_type
	)

func start_map_battle(
	enemy_id: String = "field_slime"
):
	expedition_map_controller.start_map_battle(
		enemy_id
	)

func complete_current_map_node():
	if expedition_room_controller.finish_retreat():
		return
	expedition_map_controller.complete_current_node()

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
		$PreparationVillage.clock_hud.visible = new_phase == ExpeditionPhase.PREP

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

	var selected_difficulty: int = ExpeditionDifficultyData.MIN_LEVEL

	if prep_panel.has_method(
		"get_selected_difficulty"
	):
		selected_difficulty = int(
			prep_panel.call(
				"get_selected_difficulty"
			)
		)

	var departure_result: Dictionary = (
		expedition_departure_service.prepare_departure(
			current_region_id,
			GameState.current_day,
			selected_difficulty
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
			expedition_bag,
			{"region":current_region_id,"explored":visited_map_node_ids.size() > 1}
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

	# 첫 원정을 다녀온 기록(스토리 NPC 등장 조건)
	PlayerProgress.record_expedition_completed()

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

# 장비 능력치 계산은 ExpeditionStatsController가 처리한다.
func apply_bag_equipment_stats() -> void:
	expedition_stats_controller.apply_bag_equipment_stats()

func update_player_stats_ui() -> void:
	expedition_stats_controller.update_player_stats_ui()


func _open_loot_after_message() -> void:
	refresh_loot_ui()

	if temporary_loot.is_empty():
		complete_current_map_node()
		return

	map_panel.visible = false
	battle_panel.visible = false
	loot_panel.visible = true


# 진행 메시지 큐는 ExpeditionMessageController가 처리한다.
# 컨트롤러가 타입 없는 배열 리터럴로 부르므로 여기서 Array[String]으로 바꿔 넘긴다.
func show_run_messages(
	messages: Array,
	finish_action: Callable = Callable()
) -> void:
	var typed_messages: Array[String] = []
	typed_messages.assign(messages)

	expedition_message_controller.show_messages(
		typed_messages,
		finish_action
	)


func _on_message_continue_pressed() -> void:
	expedition_message_controller.on_continue_pressed()

# =========================================================
# 원정 이벤트 처리
# =========================================================

# CSV 이벤트 결과 처리는 ExpeditionEventController가 담당한다.
func resolve_expedition_event(
	event: Dictionary
) -> void:
	expedition_event_controller.resolve(
		event
	)

func _finish_loot_organization() -> void:
	expedition_bag_controller.finish_loot_organization()


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

# 체크포인트 저장·복원은 ExpeditionCheckpointController가 처리한다.
# 아래 함수는 외부(day_manager, 점검 스크립트)가 쓰는 공개 진입점이다.
func can_save_expedition_checkpoint() -> bool:
	return expedition_checkpoint_controller.can_save()

func create_expedition_checkpoint_data() -> Dictionary:
	return expedition_checkpoint_controller.create_data()

func save_expedition_checkpoint(
	target_path: String = GameState.SAVE_PATH
) -> bool:
	return expedition_checkpoint_controller.save(
		target_path
	)

func restore_expedition_checkpoint() -> bool:
	return expedition_checkpoint_controller.restore()

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
	village.clock_hud.visible = current_expedition_phase == ExpeditionPhase.PREP
	if bool(GameState.get_meta("shop_expedition_prep",false)):
		GameState.remove_meta("shop_expedition_prep")
		prep_panel.call("show_departure_choice")
		prep_panel.show()
		village.hud.hide()
		village.clock_hud.hide()
		game_menu.hide()
