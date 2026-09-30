class_name ItemCard
extends Button


signal item_selected(item_id: String)

signal inventory_entry_selected(
	entry_type: String,
	entry_id: Variant
)


const ENTRY_TYPE_ITEM: String = "item"
const ENTRY_TYPE_FURNITURE: String = "furniture"
const ENTRY_TYPE_EQUIPMENT_INSTANCE: String = "equipment_instance"
const DRAG_TYPE_ITEM_TRANSFER: String = "inventory_item_transfer"


@onready var icon_rect: TextureRect = (
	$IconRect
)

@onready var count_label: Label = (
	$CountLabel
)


var item_id: String = ""
var entry_type: String = ""
var entry_id: Variant = null

var item_drag_enabled: bool = false
var item_drag_source: String = ""
var item_drag_amount: int = 0


#==================================


func _ready() -> void:
	preload("res://script/ui/common/inventory/inventory_slot_style.gd").content(self)
	pressed.connect(
		_on_pressed
	)


# 일반 수량형 아이템
func setup(
	new_item_id: String,
	stored_count: int,
	displayed_count: int = 0
) -> void:
	item_id = new_item_id
	entry_type = ENTRY_TYPE_ITEM
	entry_id = new_item_id

	icon_rect.texture = (
		ItemData.get_item_icon(
			item_id
		)
	)

	var total_count: int = (
		stored_count
		+ displayed_count
	)

	count_label.text = (
		str(total_count)
	)

	var item_data: Dictionary = (
		ItemData.get_item(
			item_id
		)
	)

	var item_name: String = (
		ItemData.get_item_name(
			item_id
		)
	)

	var description: String = str(
		item_data.get(
			"description",
			""
		)
	)

	if description.is_empty():
		description = "등록된 설명이 없습니다."

	var price: int = int(
		item_data.get(
			"price",
			0
		)
	)

	var sellable: bool = bool(
		item_data.get(
			"sellable",
			false
		)
	)

	var tooltip_lines: Array[String] = [
		item_name,
		"",
		description,
		"",
		"전체 보유: %d개" % total_count,
		"창고 보관: %d개" % stored_count,
		"진열 중: %d개" % displayed_count
	]

	if sellable:
		tooltip_lines.append(
			"판매 가격: %d G" % price
		)
	else:
		tooltip_lines.append(
			"판매: 불가"
		)

	tooltip_text = "\n".join(
		tooltip_lines
	)


func enable_item_drag(
	source_inventory: String,
	amount: int
) -> void:
	item_drag_enabled = (
		entry_type == ENTRY_TYPE_ITEM
		and not item_id.is_empty()
		and not source_inventory.is_empty()
		and amount > 0
	)

	item_drag_source = source_inventory
	item_drag_amount = maxi(
		amount,
		0
	)


# 가구 보관함 항목
# 가구의 보관 수량과 배치 수량을 함께 표시한다.
func setup_furniture(
	furniture_id: String,
	stored_count: int,
	placed_count: int = 0
) -> void:
	item_id = furniture_id
	entry_type = ENTRY_TYPE_FURNITURE
	entry_id = furniture_id

	icon_rect.texture = (
		FurnitureData.get_furniture_icon(
			furniture_id
		)
	)

	var total_count: int = (
		stored_count
		+ placed_count
	)

	count_label.text = (
		str(total_count)
	)

	var furniture_data: Dictionary = (
		FurnitureData.get_furniture(
			furniture_id
		)
	)

	var furniture_name: String = (
		FurnitureData.get_furniture_name(
			furniture_id
		)
	)

	var description: String = str(
		furniture_data.get(
			"description",
			""
		)
	)

	if description.is_empty():
		description = "등록된 설명이 없습니다."

	var status_text: String = "가구 보관함"

	if (
		stored_count > 0
		and placed_count > 0
	):
		status_text = "보관 및 매장 배치 중"

	elif placed_count > 0:
		status_text = "매장 배치 중"

	tooltip_text = "\n".join(
		[
			furniture_name,
			"",
			description,
			"",
			"전체 보유: %d개" % total_count,
			"보관 중: %d개" % stored_count,
			"배치 중: %d개" % placed_count,
			"사용 상태: " + status_text
		]
	)

# 개별 장비 인스턴스
func setup_equipment_instance(
	instance_data: Dictionary,
	location_text: String = "보유 장비"
) -> void:
	var instance_id: int = int(
		instance_data.get(
			"instance_id",
			-1
		)
	)

	var equipment_item_id: String = str(
		instance_data.get(
			"item_id",
			""
		)
	)

	var enhancement_level: int = int(
		instance_data.get(
			"enhancement_level",
			0
		)
	)

	item_id = equipment_item_id
	entry_type = ENTRY_TYPE_EQUIPMENT_INSTANCE
	entry_id = instance_id

	icon_rect.texture = (
		ItemData.get_item_icon(
			equipment_item_id
		)
	)

	if enhancement_level > 0:
		count_label.text = (
			"+" + str(enhancement_level)
		)
	else:
		count_label.text = "1"

	var item_data: Dictionary = (
		ItemData.get_item(
			equipment_item_id
		)
	)

	var item_name: String = (
		ItemData.get_item_name(
			equipment_item_id
		)
	)

	var description: String = str(
		item_data.get(
			"description",
			""
		)
	)

	if description.is_empty():
		description = "등록된 설명이 없습니다."

	var equipment_type: String = (
		ExpeditionEquipmentData.get_equipment_type(
			equipment_item_id
		)
	)

	var effect_id: String = (
		ExpeditionEquipmentData.get_effect_id(
			equipment_item_id
		)
	)

	var effective_value: int = int(
		EquipmentEnhancementService.get_effective_value(
			instance_data
		)
	)

	var tooltip_lines: Array[String] = [
		item_name,
		"",
		description,
		"",
		"종류: " + get_equipment_type_text(
			equipment_type
		),
		"강화 단계: +" + str(
			enhancement_level
		),
		get_equipment_effect_text(
			effect_id,
			effective_value
		),
		"현재 위치: " + location_text
	]

	tooltip_text = "\n".join(
		tooltip_lines
	)

# 장비 종류의 내부 ID를 사용자용 문구로 변환한다.
func get_equipment_type_text(
	equipment_type: String
) -> String:
	match equipment_type:
		"weapon":
			return "무기"

		"armor":
			return "방어구"

		"tool":
			return "도구"

		"misc":
			return "기타"

	return equipment_type


# 장비 효과의 내부 ID를 사용자용 문구로 변환한다.
func get_equipment_effect_text(
	effect_id: String,
	effect_value: int
) -> String:
	match effect_id:
		"attack":
			# 공격력 숫자는 보이지 않는다(무기 종류가 공격 방식을 정한다).
			return "무기"

		"defense":
			return (
				"방어력: +"
				+ str(effect_value)
			)

		_:
			if effect_id.is_empty():
				return "장비 효과: 없음"

			return (
				"장비 효과: "
				+ effect_id
				+ " +"
				+ str(effect_value)
			)

func _get_drag_data(
	_at_position: Vector2
) -> Variant:
	if not item_drag_enabled:
		return null

	if entry_type != ENTRY_TYPE_ITEM:
		return null

	if item_id.is_empty():
		return null

	if item_drag_amount <= 0:
		return null

	var preview_panel := PanelContainer.new()

	preview_panel.custom_minimum_size = Vector2(
		90.0,
		72.0
	)

	preview_panel.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	var preview_vbox := VBoxContainer.new()

	preview_vbox.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	preview_panel.add_child(
		preview_vbox
	)

	var preview_icon := TextureRect.new()

	preview_icon.texture = icon_rect.texture
	preview_icon.custom_minimum_size = Vector2(
		48.0,
		48.0
	)

	preview_icon.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)

	preview_icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	preview_icon.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	preview_vbox.add_child(
		preview_icon
	)

	var preview_count := Label.new()

	preview_count.text = (
		str(item_drag_amount)
	)

	preview_count.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	preview_count.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	preview_vbox.add_child(
		preview_count
	)

	set_drag_preview(
		preview_panel
	)

	return {
		"type": DRAG_TYPE_ITEM_TRANSFER,
		"entry_type": entry_type,
		"item_id": item_id,
		"amount": item_drag_amount,
		"source": item_drag_source
	}

func _on_pressed() -> void:
	if entry_type.is_empty():
		return

	inventory_entry_selected.emit(
		entry_type,
		entry_id
	)

	# 기존 진열대 UI와의 호환성을 유지한다.
	if entry_type == ENTRY_TYPE_ITEM:
		item_selected.emit(
			item_id
		)
