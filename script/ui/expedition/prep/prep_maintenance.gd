extends PanelContainer


enum MaintenanceMode {
	CRAFT,
	ENHANCEMENT,
	DISMANTLE
}


@onready var title_label: Label = (
	$MainVBox/TitleLabel
)

@onready var craft_mode_button: Button = (
	$MainVBox/ModeButtons/CraftModeButton
)

@onready var enhancement_mode_button: Button = (
	$MainVBox/ModeButtons/EnhancementModeButton
)

@onready var recipe_list: VBoxContainer = (
	$MainVBox/Body/RecipePanel/RecipeScroll/RecipeList
)

@onready var result_label: Label = (
	$MainVBox/Body/DetailPanel/DetailVBox/ResultLabel
)

@onready var materials_label: Label = (
	$MainVBox/Body/DetailPanel/DetailVBox/MaterialsLabel
)

@onready var status_label: Label = (
	$MainVBox/Body/DetailPanel/DetailVBox/StatusLabel
)

@onready var action_button: Button = (
	$MainVBox/Body/DetailPanel/DetailVBox/CraftButton
)

@onready var hint_label: Label = (
	$MainVBox/HintLabel
)

@onready var dismantle_mode_button: Button = (
	$MainVBox/ModeButtons/DismantleModeButton
)

@onready var dismantle_confirm_dialog: ConfirmationDialog = (
	$DismantleConfirmDialog
)


var current_mode: MaintenanceMode = (
	MaintenanceMode.CRAFT
)

var selected_recipe_id: String = ""
var selected_equipment_instance_id: int = -1

var bag_content: Node = null


func _ready() -> void:
	bag_content = get_parent().get_node_or_null(
		"BagContent"
	)

	craft_mode_button.pressed.connect(
		_set_mode.bind(
			MaintenanceMode.CRAFT
		)
	)

	enhancement_mode_button.pressed.connect(
		_set_mode.bind(
			MaintenanceMode.ENHANCEMENT
		)
	)

	action_button.pressed.connect(
		_on_action_pressed
	)

	dismantle_mode_button.pressed.connect(
		_set_mode.bind(
			MaintenanceMode.DISMANTLE
		)
	)

	dismantle_confirm_dialog.title = (
		"장비 분해"
	)

	dismantle_confirm_dialog.get_ok_button().text = (
		"분해"
	)

	dismantle_confirm_dialog.get_cancel_button().text = (
		"취소"
	)

	dismantle_confirm_dialog.confirmed.connect(
		_confirm_dismantle_selected
	)

	refresh_all()


func refresh_all() -> void:
	RecipeData.ensure_loaded()
	ExpeditionEquipmentData.ensure_loaded()

	match current_mode:
		MaintenanceMode.CRAFT:
			_refresh_recipe_list()
			_refresh_craft_detail()

		MaintenanceMode.ENHANCEMENT:
			_refresh_equipment_list()
			_refresh_equipment_detail()

		MaintenanceMode.DISMANTLE:
			_refresh_dismantle_list()
			_refresh_dismantle_detail()

	_refresh_mode_display()


func _set_mode(
	new_mode: MaintenanceMode
) -> void:
	current_mode = new_mode

	selected_recipe_id = ""
	selected_equipment_instance_id = -1

	status_label.text = ""

	refresh_all()


func _refresh_mode_display() -> void:
	craft_mode_button.disabled = (
		current_mode == MaintenanceMode.CRAFT
	)

	enhancement_mode_button.disabled = (
		current_mode == MaintenanceMode.ENHANCEMENT
	)

	craft_mode_button.disabled = (
		current_mode == MaintenanceMode.CRAFT
	)

	enhancement_mode_button.disabled = (
		current_mode == MaintenanceMode.ENHANCEMENT
	)

	dismantle_mode_button.disabled = (
		current_mode == MaintenanceMode.DISMANTLE
	)

	match current_mode:
		MaintenanceMode.CRAFT:
			title_label.text = "제작"
			action_button.text = "제작"
			hint_label.text = (
				"원정에서 획득한 재료로 장비를 제작합니다."
			)

		MaintenanceMode.ENHANCEMENT:
			title_label.text = "장비 강화"
			action_button.text = "강화"
			hint_label.text = (
				"보관함 또는 원정 가방의 장비를 강화합니다."
			)

		MaintenanceMode.DISMANTLE:
			title_label.text = "장비 분해"
			action_button.text = "분해"
			hint_label.text = (
				"보관함의 장비를 분해해 제작 재료 일부를 회수합니다."
			)

# =========================================================
# 제작
# =========================================================

func _refresh_recipe_list() -> void:
	_clear_item_list()

	var recipes: Array[Dictionary] = (
		RecipeData.get_all_recipes()
	)

	for recipe in recipes:
		var recipe_id: String = str(
			recipe.get("recipe_id", "")
		)

		var result_item_id: String = str(
			recipe.get("result_item_id", "")
		)

		var result_amount: int = int(
			recipe.get("result_amount", 1)
		)

		var button := Button.new()

		button.text = (
			ItemData.get_item_name(result_item_id)
			+ " ×"
			+ str(result_amount)
		)

		button.pressed.connect(
			_select_recipe.bind(
				recipe_id
			)
		)

		recipe_list.add_child(button)


func _select_recipe(
	recipe_id: String
) -> void:
	selected_recipe_id = recipe_id
	status_label.text = ""

	_refresh_craft_detail()


func _refresh_craft_detail() -> void:
	if selected_recipe_id.is_empty():
		result_label.text = (
			"제작할 아이템을 선택하세요."
		)

		materials_label.text = ""
		status_label.text = ""
		action_button.disabled = true
		return

	var recipe: Dictionary = (
		RecipeData.get_recipe(
			selected_recipe_id
		)
	)

	if recipe.is_empty():
		result_label.text = (
			"제작법을 확인할 수 없습니다."
		)

		materials_label.text = ""
		action_button.disabled = true
		return

	var result_item_id: String = str(
		recipe.get("result_item_id", "")
	)

	var result_amount: int = int(
		recipe.get("result_amount", 1)
	)

	result_label.text = (
		"결과: "
		+ ItemData.get_item_name(
			result_item_id
		)
		+ " ×"
		+ str(result_amount)
	)

	var material_lines: Array[String] = []

	var materials: Array = recipe.get(
		"materials",
		[]
	)

	for material_data in materials:
		if not material_data is Dictionary:
			continue

		var item_id: String = str(
			material_data.get(
				"item_id",
				""
			)
		)

		var required_amount: int = int(
			material_data.get(
				"amount",
				0
			)
		)

		var owned_amount: int = (
			GameState.get_item_count(item_id)
		)

		material_lines.append(
			"%s %d / %d"
			% [
				ItemData.get_item_name(item_id),
				owned_amount,
				required_amount
			]
		)

	if material_lines.is_empty():
		materials_label.text = "필요 재료 없음"
	else:
		materials_label.text = (
			"필요 재료\n"
			+ "\n".join(material_lines)
		)

	var can_craft: bool = (
		RecipeData.can_craft(
			selected_recipe_id
		)
	)

	action_button.disabled = not can_craft

	if can_craft:
		status_label.text = "제작 가능"
	else:
		status_label.text = "재료 부족"


func _craft_selected_recipe() -> void:
	if selected_recipe_id.is_empty():
		return

	var recipe: Dictionary = (
		RecipeData.get_recipe(
			selected_recipe_id
		)
	)

	if recipe.is_empty():
		return

	var result_item_id: String = str(
		recipe.get("result_item_id", "")
	)

	var result_amount: int = int(
		recipe.get("result_amount", 1)
	)

	var success: bool = (
		RecipeData.craft(
			selected_recipe_id
		)
	)

	if not success:
		_refresh_craft_detail()

		status_label.text = (
			"제작하지 못했습니다."
		)
		return

	var item_name: String = (
		ItemData.get_item_name(
			result_item_id
		)
	)

	DebugLog.write(
		"[정비] 제작 완료 / ",
		item_name,
		" ×",
		result_amount
	)

	_refresh_recipe_list()
	_refresh_craft_detail()

	status_label.text = (
		item_name + " 제작 완료"
	)


# =========================================================
# 장비 강화 목록
# =========================================================

func _refresh_equipment_list() -> void:
	_clear_item_list()

	if not is_instance_valid(bag_content):
		var warning_label := Label.new()
		warning_label.text = (
			"가방 화면을 찾을 수 없습니다."
		)

		recipe_list.add_child(warning_label)
		return

	if not bag_content.has_method(
		"get_equipment_entries_for_maintenance"
	):
		var warning_label := Label.new()
		warning_label.text = (
			"가방의 장비 조회 기능이 없습니다."
		)

		recipe_list.add_child(warning_label)
		return

	var raw_entries: Variant = bag_content.call(
		"get_equipment_entries_for_maintenance"
	)

	if not raw_entries is Array:
		return

	var entries: Array = raw_entries

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = (
			"강화할 장비가 없습니다."
		)

		recipe_list.add_child(empty_label)
		return

	for raw_entry in entries:
		if not raw_entry is Dictionary:
			continue

		var entry: Dictionary = raw_entry

		var instance_id: int = int(
			entry.get("instance_id", -1)
		)

		var item_id: String = str(
			entry.get("item_id", "")
		)

		var enhancement_level: int = int(
			entry.get(
				"enhancement_level",
				0
			)
		)

		var source_name: String = str(
			entry.get(
				"source_name",
				""
			)
		)

		var button := Button.new()

		button.text = (
			"%s +%d\n[%s · ID %d]"
			% [
				ItemData.get_item_name(item_id),
				enhancement_level,
				source_name,
				instance_id
			]
		)

		button.pressed.connect(
			_select_equipment.bind(
				instance_id
			)
		)

		recipe_list.add_child(button)


func _select_equipment(
	instance_id: int
) -> void:
	selected_equipment_instance_id = (
		instance_id
	)

	status_label.text = ""

	_refresh_equipment_detail()


func _get_selected_equipment_placement() -> Dictionary:
	if selected_equipment_instance_id < 0:
		return {}

	if not is_instance_valid(bag_content):
		return {}

	if not bag_content.has_method(
		"get_equipment_placement_for_maintenance"
	):
		return {}

	var raw_placement: Variant = bag_content.call(
		"get_equipment_placement_for_maintenance",
		selected_equipment_instance_id
	)

	if raw_placement is Dictionary:
		return raw_placement

	return {}


# =========================================================
# 장비 강화 상세
# =========================================================

func _refresh_equipment_detail() -> void:
	var placement: Dictionary = (
		_get_selected_equipment_placement()
	)

	if placement.is_empty():
		result_label.text = (
			"강화할 장비를 선택하세요."
		)

		materials_label.text = ""
		status_label.text = ""
		action_button.disabled = true
		return

	var item_id: String = str(
		placement.get("item_id", "")
	)

	var current_level: int = int(
		placement.get(
			"enhancement_level",
			0
		)
	)

	var equipment_data: Dictionary = (
		ExpeditionEquipmentData.get_equipment_data(
			item_id
		)
	)

	if equipment_data.is_empty():
		result_label.text = (
			"장비 정보를 확인할 수 없습니다."
		)

		materials_label.text = ""
		action_button.disabled = true
		return

	var max_level: int = int(
		equipment_data.get(
			"max_enhancement_level",
			0
		)
	)

	var equipment_type: String = str(
		equipment_data.get(
			"equipment_type",
			""
		)
	)

	result_label.text = (
		"%s\n종류: %s\n강화: +%d / +%d"
		% [
			ItemData.get_item_name(item_id),
			_get_equipment_type_name(
				equipment_type
			),
			current_level,
			max_level
		]
	)

	if current_level >= max_level:
		materials_label.text = ""
		status_label.text = (
			"최대 강화 단계입니다."
		)

		action_button.disabled = true
		return

	var check: Dictionary = (
		EquipmentEnhancementService.get_enhancement_check(
			placement
		)
	)

	var cost: Dictionary = check.get(
		"cost",
		{}
	)

	materials_label.text = (
		_build_enhancement_cost_text(
			cost,
			current_level + 1
		)
	)

	var can_enhance: bool = bool(
		check.get(
			"success",
			false
		)
	)

	action_button.disabled = not can_enhance

	if can_enhance:
		status_label.text = "강화 가능"
	else:
		status_label.text = str(
			check.get(
				"message",
				"강화할 수 없습니다."
			)
		)


func _build_enhancement_cost_text(
	cost: Dictionary,
	target_level: int
) -> String:
	var lines: Array[String] = [
		"+%d 강화 필요 재료"
		% target_level
	]

	if cost.is_empty():
		lines.append(
			"강화 비용 정보를 확인할 수 없습니다."
		)

		return "\n".join(lines)

	for raw_item_id in cost.keys():
		var item_id: String = str(
			raw_item_id
		)

		var required_amount: int = int(
			cost[raw_item_id]
		)

		var owned_amount: int = (
			GameState.get_item_count(
				item_id
			)
		)

		lines.append(
			"%s %d / %d"
			% [
				ItemData.get_item_name(item_id),
				owned_amount,
				required_amount
			]
		)

	return "\n".join(lines)


func _enhance_selected_equipment() -> void:
	var placement: Dictionary = (
		_get_selected_equipment_placement()
	)

	if placement.is_empty():
		status_label.text = (
			"강화할 장비를 다시 선택해주세요."
		)
		return

	var result: Dictionary = (
		EquipmentEnhancementService.enhance_equipment(
			placement
		)
	)

	if not bool(
		result.get(
			"success",
			false
		)
	):
		_refresh_equipment_detail()

		status_label.text = str(
			result.get(
				"message",
				"장비 강화에 실패했습니다."
			)
		)
		return

	if (
		is_instance_valid(bag_content)
		and bag_content.has_method(
			"refresh_after_equipment_enhancement"
		)
	):
		bag_content.call(
			"refresh_after_equipment_enhancement"
		)

	var item_id: String = str(
		placement.get("item_id", "")
	)

	var new_level: int = int(
		placement.get(
			"enhancement_level",
			0
		)
	)

	DebugLog.write(
		"[정비] 장비 강화 완료 / ",
		item_id,
		" / ID: ",
		selected_equipment_instance_id,
		" / 강화: +",
		new_level
	)

	_refresh_equipment_list()
	_refresh_equipment_detail()

	status_label.text = (
		"%s +%d 강화 완료"
		% [
			ItemData.get_item_name(item_id),
			new_level
		]
	)


# =========================================================
# 공통
# =========================================================

func _on_action_pressed() -> void:
	match current_mode:
		MaintenanceMode.CRAFT:
			_craft_selected_recipe()

		MaintenanceMode.ENHANCEMENT:
			_enhance_selected_equipment()

		MaintenanceMode.DISMANTLE:
			_request_dismantle_selected()


func _clear_item_list() -> void:
	for child in recipe_list.get_children():
		child.queue_free()


func _get_equipment_type_name(
	equipment_type: String
) -> String:
	match equipment_type:
		ExpeditionEquipmentData.TYPE_WEAPON:
			return "무기"

		ExpeditionEquipmentData.TYPE_ARMOR:
			return "방어구"

		ExpeditionEquipmentData.TYPE_TOOL:
			return "도구"

		ExpeditionEquipmentData.TYPE_MISC:
			return "기타"

	return equipment_type


# =============================
# 분해
#==============================

func _refresh_dismantle_list() -> void:
	_clear_item_list()

	if not is_instance_valid(
		bag_content
	):
		return

	if not bag_content.has_method(
		"get_equipment_entries_for_maintenance"
	):
		return

	var raw_entries: Variant = bag_content.call(
		"get_equipment_entries_for_maintenance"
	)

	if not raw_entries is Array:
		return

	var added_count: int = 0

	for raw_entry in raw_entries:
		if not raw_entry is Dictionary:
			continue

		var entry: Dictionary = raw_entry

		var source_name: String = str(
			entry.get(
				"source_name",
				""
			)
		)

		# 원정 가방 장비는 분해하지 않는다.
		if source_name != "보관함":
			continue

		var instance_id: int = int(
			entry.get(
				"instance_id",
				-1
			)
		)

		var item_id: String = str(
			entry.get(
				"item_id",
				""
			)
		)

		var enhancement_level: int = int(
			entry.get(
				"enhancement_level",
				0
			)
		)

		# 제작 레시피가 있는 장비만 분해 가능
		if RecipeData.get_recipe_by_result_item(
			item_id
		).is_empty():
			continue

		var button := Button.new()

		button.text = (
			"%s +%d\n[보관함 · ID %d]"
			% [
				ItemData.get_item_name(
					item_id
				),
				enhancement_level,
				instance_id
			]
		)

		button.pressed.connect(
			_select_dismantle_equipment.bind(
				instance_id
			)
		)

		recipe_list.add_child(
			button
		)

		added_count += 1

	if added_count <= 0:
		var empty_label := Label.new()

		empty_label.text = (
			"분해할 수 있는 장비가 없습니다."
			+ "\n장비는 보관함에 있어야 하며,"
			+ "\n제작 레시피가 필요합니다."
		)

		recipe_list.add_child(
			empty_label
		)

func _select_dismantle_equipment(
	instance_id: int
) -> void:
	selected_equipment_instance_id = (
		instance_id
	)

	status_label.text = ""

	_refresh_dismantle_detail()

func _refresh_dismantle_detail() -> void:
	var placement: Dictionary = (
		_get_selected_equipment_placement()
	)

	if placement.is_empty():
		result_label.text = (
			"분해할 장비를 선택하세요."
		)

		materials_label.text = ""
		status_label.text = ""
		action_button.disabled = true
		return

	var instance_id: int = int(
		placement.get(
			"instance_id",
			-1
		)
	)

	if not GameState.has_owned_equipment_instance(
		instance_id
	):
		result_label.text = (
			"원정 가방의 장비는 분해할 수 없습니다."
			+ "\n먼저 보관함으로 옮겨주세요."
		)

		materials_label.text = ""
		status_label.text = ""
		action_button.disabled = true
		return

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var enhancement_level: int = int(
		placement.get(
			"enhancement_level",
			0
		)
	)

	var refund: Dictionary = (
		RecipeData.get_dismantle_refund(
			item_id
		)
	)

	result_label.text = (
		"%s +%d"
		% [
			ItemData.get_item_name(
				item_id
			),
			enhancement_level
		]
	)

	if refund.is_empty():
		materials_label.text = (
			"분해할 제작 레시피가 없습니다."
		)

		status_label.text = ""
		action_button.disabled = true
		return

	materials_label.text = (
		_build_dismantle_refund_text(
			refund
		)
	)

	status_label.text = (
		"분해하면 장비는 사라집니다."
	)

	action_button.disabled = false

func _build_dismantle_refund_text(
	refund: Dictionary
) -> String:
	var lines: Array[String] = [
		"분해 시 반환 재료"
	]

	for raw_item_id in refund.keys():
		var item_id: String = str(
			raw_item_id
		)

		var refund_amount: int = int(
			refund.get(
				raw_item_id,
				0
			)
		)

		if refund_amount <= 0:
			continue

		lines.append(
			"%s ×%d"
			% [
				ItemData.get_item_name(
					item_id
				),
				refund_amount
			]
		)

	return "\n".join(
		lines
	)

func _request_dismantle_selected() -> void:
	var placement: Dictionary = (
		_get_selected_equipment_placement()
	)

	if placement.is_empty():
		return

	var instance_id: int = int(
		placement.get(
			"instance_id",
			-1
		)
	)

	if not GameState.has_owned_equipment_instance(
		instance_id
	):
		status_label.text = (
			"보관함의 장비만 분해할 수 있습니다."
		)
		return

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var refund: Dictionary = (
		RecipeData.get_dismantle_refund(
			item_id
		)
	)

	if refund.is_empty():
		status_label.text = (
			"분해할 제작 레시피가 없습니다."
		)
		return

	dismantle_confirm_dialog.dialog_text = (
		ItemData.get_item_name(item_id)
		+ "을(를) 분해하시겠습니까?"
		+ "\n\n"
		+ _build_dismantle_refund_text(
			refund
		)
		+ "\n\n분해한 장비는 복구할 수 없습니다."
	)

	dismantle_confirm_dialog.popup_centered()

func _confirm_dismantle_selected() -> void:
	var placement: Dictionary = (
		_get_selected_equipment_placement()
	)

	if placement.is_empty():
		return

	var instance_id: int = int(
		placement.get(
			"instance_id",
			-1
		)
	)

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var refund: Dictionary = (
		RecipeData.get_dismantle_refund(
			item_id
		)
	)

	if refund.is_empty():
		status_label.text = (
			"분해 재료를 확인할 수 없습니다."
		)
		return

	var removed_instance: Dictionary = (
		GameState.take_owned_equipment_instance(
			instance_id
		)
	)

	if removed_instance.is_empty():
		status_label.text = (
			"장비를 분해하지 못했습니다."
		)
		return

	for raw_item_id in refund.keys():
		var material_id: String = str(
			raw_item_id
		)

		var refund_amount: int = int(
			refund.get(
				raw_item_id,
				0
			)
		)

		if refund_amount <= 0:
			continue

		GameState.add_item(
			material_id,
			refund_amount
		)

	selected_equipment_instance_id = -1

	if (
		is_instance_valid(bag_content)
		and bag_content.has_method(
			"refresh_all"
		)
	):
		bag_content.call(
			"refresh_all"
		)

	_refresh_dismantle_list()
	_refresh_dismantle_detail()

	status_label.text = (
		ItemData.get_item_name(item_id)
		+ " 분해 완료"
	)
