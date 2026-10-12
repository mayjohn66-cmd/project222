extends Control


enum PrepTab {
	MAP,
	BAG
}

var current_tab: PrepTab = PrepTab.MAP
var transition_tween: Tween



@onready var bag_tab_button: Button = (
	$ModeTabs/BagTabButton
)

@onready var map_tab_button: Button = (
	$ModeTabs/MapTabButton
)


@onready var bag_content: Control = (
	$BagContent
)

@onready var map_content: Control = (
	$MapContent
)

@onready var bag_scrim: ColorRect = $BagScrim


@onready var prep_info_label: Label = (
	$InfoPanel/PrepInfoLabel
)

@onready var info_panel: PanelContainer = $InfoPanel

@onready var destination_label: Label = (
	$Header/HeaderColumn/DestinationLabel
)
@onready var region_info_card: PanelContainer = $RegionInfoCard
@onready var region_name_label: Label = $RegionInfoCard/CardMargin/CardColumn/RegionNameLabel
@onready var difficulty_label: Label = $RegionInfoCard/CardMargin/CardColumn/DifficultyLabel
@onready var region_description_label: Label = $RegionInfoCard/CardMargin/CardColumn/RegionDescriptionLabel
@onready var region_requirement_label: Label = $RegionInfoCard/CardMargin/CardColumn/RegionRequirementLabel
@onready var back_to_map_button: Button = $RegionInfoCard/CardMargin/CardColumn/BackToMapButton
@onready var start_button: Button = $StartExpeditionButton
@onready var region_card_column: VBoxContainer = $RegionInfoCard/CardMargin/CardColumn

# 난이도 선택 줄(◀ 난이도 N ▶). 설명은 두지 않는다. 씬을 고치지 않고 코드로 만든다.
var selected_difficulty: int = ExpeditionDifficultyData.MIN_LEVEL
var difficulty_prev_button: Button
var difficulty_next_button: Button
var difficulty_level_label: Label


func _ready() -> void:
	bag_tab_button.pressed.connect(
		select_tab.bind(PrepTab.BAG)
	)

	map_tab_button.pressed.connect(
		select_tab.bind(PrepTab.MAP)
	)
	map_content.region_changed.connect(_on_region_changed)
	back_to_map_button.pressed.connect(select_tab.bind(PrepTab.MAP))
	_build_difficulty_selector()
	ExpeditionEnvironmentCard.install(self)
	ExpeditionSupplyAccess.install(self)
	ExpeditionLoadoutGuide.install(self)
	ExpeditionShopReadinessGuide.attach(self)

	select_tab(PrepTab.MAP)

func show_departure_choice() -> void:
	map_content.clear_selection()
	select_tab(PrepTab.MAP)


func select_tab(tab: PrepTab) -> void:
	if transition_tween and transition_tween.is_running():
		transition_tween.kill()
	current_tab = tab

	bag_content.hide()
	bag_scrim.hide()
	region_info_card.hide()
	start_button.hide()
	bag_content.modulate.a = 1.0
	bag_scrim.modulate.a = 1.0
	region_info_card.modulate.a = 1.0
	start_button.modulate.a = 1.0
	map_content.set_map_overlays_visible(true)
	info_panel.hide()

	bag_tab_button.disabled = false
	map_tab_button.disabled = false
	bag_tab_button.button_pressed = tab == PrepTab.BAG
	map_tab_button.button_pressed = tab == PrepTab.MAP

	match tab:
		PrepTab.BAG:
			if get_selected_region_id().is_empty():
				select_tab(PrepTab.MAP)
				return
			bag_scrim.show()
			bag_content.show()
			region_info_card.show()
			start_button.show()
			for panel in [bag_scrim, bag_content, region_info_card, start_button]:
				panel.modulate.a = 0.0
			transition_tween = create_tween().set_parallel(true)
			for panel in [bag_scrim, bag_content, region_info_card, start_button]:
				transition_tween.tween_property(panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_refresh_region_card()

			if bag_content.has_method(
				"refresh_all"
			):
				bag_content.call(
					"refresh_all"
				)

		PrepTab.MAP:
			prep_info_label.text = "지도에서 목적지를 선택하세요."

			if map_content.has_method(
				"refresh_availability"
			):
				map_content.call(
					"refresh_availability"
				)

	_refresh_destination_label()

func _on_region_changed(_region_id: String) -> void:
	_refresh_destination_label()
	select_tab(PrepTab.BAG)


func _refresh_region_card() -> void:
	var data: Dictionary = ExpeditionMapData.get_region_data(get_selected_region_id())
	region_name_label.text = str(data.get("name", "지역 선택"))
	_refresh_difficulty_selector()
	region_description_label.text = ExpeditionEnvironment.preparation(get_selected_region_id()) + "\n" + str(data.get("description", ""))
	region_requirement_label.hide()
	var item_id: String = str(data.get("entry_item_id", ""))
	if not item_id.is_empty():
		var required_amount: int = int(data.get("entry_amount", 0))
		var owned_amount: int = GameState.get_item_count(item_id)
		region_requirement_label.text = "입장 조건  %s ×%d  ·  보유 %d" % [
			ItemData.get_item_name(item_id), required_amount, owned_amount
		]
		region_requirement_label.show()

func show_preparation_message(message: String) -> void:
	prep_info_label.text = message
	info_panel.show()

func _refresh_destination_label() -> void:
	var region_id := get_selected_region_id()
	var region: Dictionary = ExpeditionMapData.get_region_data(region_id)
	destination_label.text = "이번 원정: " + str(region.get("name","지역을 선택하세요"))

func refresh_current_tab() -> void:
	select_tab(current_tab)


func get_prepared_bag_model():
	if bag_content.has_method(
		"get_prepared_bag_model"
	):
		return bag_content.call(
			"get_prepared_bag_model"
		)

	return null

func prepare_for_departure() -> void:
	if (
		bag_content != null
		and bag_content.has_method(
			"prepare_for_departure"
		)
	):
		bag_content.call(
			"prepare_for_departure"
		)

func get_selected_region_id() -> String:
	if map_content.has_method(
		"get_selected_region_id"
	):
		return str(
			map_content.call(
				"get_selected_region_id"
			)
		)

	return GameConfig.DEFAULT_REGION_ID


# =========================================================
# 난이도 선택
# =========================================================

func get_selected_difficulty() -> int:
	return _clamp_to_unlocked(selected_difficulty)


func _build_difficulty_selector() -> void:
	# 지역 등급 글자(쉬움/보통 …)는 더 이상 쓰지 않으므로 숨긴다.
	var insert_index: int = difficulty_label.get_index()
	difficulty_label.hide()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	region_card_column.add_child(row)
	region_card_column.move_child(row, insert_index)

	difficulty_prev_button = Button.new()
	difficulty_prev_button.text = "◀"
	difficulty_prev_button.custom_minimum_size = Vector2(40, 32)
	difficulty_prev_button.pressed.connect(_step_difficulty.bind(-1))
	row.add_child(difficulty_prev_button)

	difficulty_level_label = Label.new()
	difficulty_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_level_label.add_theme_font_size_override("font_size", UiTypography.size(20))
	difficulty_level_label.add_theme_color_override(
		"font_color",
		Color(0.96, 0.76, 0.39, 1)
	)
	row.add_child(difficulty_level_label)

	difficulty_next_button = Button.new()
	difficulty_next_button.text = "▶"
	difficulty_next_button.custom_minimum_size = Vector2(40, 32)
	difficulty_next_button.pressed.connect(_step_difficulty.bind(1))
	row.add_child(difficulty_next_button)

	# 화면 아래쪽 메뉴 버튼·안내 문구와 겹치지 않게 카드를 위로 올린다.
	region_info_card.offset_top -= 60.0
	region_info_card.offset_bottom -= 60.0


func _step_difficulty(direction: int) -> void:
	selected_difficulty = _clamp_to_unlocked(selected_difficulty + direction)
	_refresh_difficulty_selector()


# 선택한 지역에서 열려 있는 난이도(1 ~ 클리어한 난이도 + 1) 안으로 보정한다.
func _clamp_to_unlocked(level: int) -> int:
	var highest: int = PlayerProgress.get_highest_unlocked_difficulty(
		get_selected_region_id()
	)

	return clampi(level, ExpeditionDifficultyData.MIN_LEVEL, highest)


func _refresh_difficulty_selector() -> void:
	if difficulty_level_label == null:
		return

	var region_id: String = get_selected_region_id()
	selected_difficulty = _clamp_to_unlocked(selected_difficulty)

	var highest: int = PlayerProgress.get_highest_unlocked_difficulty(region_id)

	difficulty_level_label.text = "난이도 %d" % selected_difficulty
	difficulty_prev_button.disabled = (
		selected_difficulty <= ExpeditionDifficultyData.MIN_LEVEL
	)
	difficulty_next_button.disabled = selected_difficulty >= highest
