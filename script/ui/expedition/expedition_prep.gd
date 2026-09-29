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


func _ready() -> void:
	bag_tab_button.pressed.connect(
		select_tab.bind(PrepTab.BAG)
	)

	map_tab_button.pressed.connect(
		select_tab.bind(PrepTab.MAP)
	)
	map_content.region_changed.connect(_on_region_changed)
	back_to_map_button.pressed.connect(select_tab.bind(PrepTab.MAP))

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
	difficulty_label.text = "난이도  |  " + str(data.get("difficulty", ""))
	region_description_label.text = str(data.get("description", ""))
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

	return "forest"
