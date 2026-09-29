extends Control

signal region_changed(region_id: String)

@onready var forest_button: Button = (
	$ForestButton
)

@onready var mine_button: Button = (
	$MineButton
)

@onready var swamp_button: Button = (
	$SwampButton
)

@onready var special_button: Button = (
	$SpecialButton
)

@onready var selected_region_label: Label = (
	$SelectedRegionPanel/SelectedRegionLabel
)

var selected_region_id: String = GameConfig.DEFAULT_REGION_ID
var region_buttons: Dictionary = {}


func _ready() -> void:
	# 기존 씬의 버튼과 지역 ID 연결
	region_buttons = {
		"forest": forest_button,
		"mine": mine_button,
		"swamp": swamp_button,
		"hidden_ruins": special_button
	}
	for region_id in region_buttons:
		var button: Button = region_buttons[region_id]
		button.material = button.material.duplicate()

		button.pressed.connect(
			_select_region.bind(str(region_id))
		)

	refresh_availability()


func _select_region(
	region_id: String
) -> void:
	selected_region_id = region_id

	_refresh_ui()

	region_changed.emit(
		selected_region_id
	)

	print(
		"[원정 준비] 지역 선택: ",
		selected_region_id
	)


func refresh_availability() -> void:
	if not ExpeditionMapData.can_enter_region(selected_region_id):
		selected_region_id = ""

	_refresh_ui()


func clear_selection() -> void:
	selected_region_id = ""
	_refresh_ui()


func _refresh_ui() -> void:
	for region_id in region_buttons:
		var button: Button = region_buttons[region_id]

		var data: Dictionary = (
			ExpeditionMapData.get_region_data(region_id)
		)

		if data.is_empty():
			button.text = ""
			button.tooltip_text = ""
			button.disabled = true
			continue

		var available: bool = (
			ExpeditionMapData.can_enter_region(region_id)
		)

		button.text = ""
		button.tooltip_text = str(data["name"])

		var item_id: String = str(data["entry_item_id"])

		if not item_id.is_empty():
			var amount: int = int(data["entry_amount"])

			var requirement: String = "%s ×%d" % [
				ItemData.get_item_name(item_id),
				amount
			]

			button.tooltip_text += "\n" + (
				"필요: " + requirement
				+ "\n보유: "
				+ str(GameState.get_item_count(item_id))
			)

			if bool(data["consume_on_entry"]):
				button.tooltip_text += "\n출발 시 소비"

		button.disabled = false
		button.modulate.a = 1.0 if available else 0.83
		(button.material as ShaderMaterial).set_shader_parameter(
			"outline_color",
			Color(1.0, 0.77, 0.3) if selected_region_id == str(region_id)
			else Color(0.98, 0.88, 0.63)
		)

	_refresh_selected_region_info()


func get_selected_region_id() -> String:
	return selected_region_id

func set_map_overlays_visible(value: bool) -> void:
	for button in region_buttons.values():
		(button as Button).visible = value
	selected_region_label.get_parent().visible = false

func _refresh_selected_region_info() -> void:
	var data: Dictionary = (
		ExpeditionMapData.get_region_data(
			selected_region_id
		)
	)

	if data.is_empty():
		selected_region_label.text = (
			"입장 가능한 지역이 없습니다."
		)
		return

	var lines: Array[String] = [
		str(data["name"]) + "  ·  " + str(data.get("difficulty", "")),
		str(data.get("description", ""))
	]
	var item_id: String = str(data.get("entry_item_id", ""))
	if not item_id.is_empty():
		lines.append("입장 조건: %s ×%d  ·  보유 %d개" % [
			ItemData.get_item_name(item_id),
			int(data.get("entry_amount", 0)),
			GameState.get_item_count(item_id)
		])
	selected_region_label.text = "\n".join(lines)
