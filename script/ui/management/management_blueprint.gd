extends Control


@onready var furniture_list: VBoxContainer = (
	$MainVBox/Body/LeftPanel/ListScroll/FurnitureList
)

@onready var list_scroll: ScrollContainer = (
	$MainVBox/Body/LeftPanel/ListScroll
)

@onready var name_label: Label = (
	$MainVBox/Body/DetailPanel/DetailScroll/Detail/NameLabel
)

@onready var description_label: Label = (
	$MainVBox/Body/DetailPanel/DetailScroll/Detail/DescriptionLabel
)

@onready var material_label: Label = (
	$MainVBox/Body/DetailPanel/DetailScroll/Detail/MaterialLabel
)

@onready var owned_label: Label = (
	$MainVBox/Body/DetailPanel/DetailScroll/Detail/OwnedLabel
)

@onready var craft_button: Button = (
	$MainVBox/Body/DetailPanel/CraftButton
)

@onready var store_button: Button = (
	$MainVBox/CategoryTabs/StoreButton
)

@onready var production_button: Button = (
	$MainVBox/CategoryTabs/ProductionButton
)

@onready var interior_button: Button = (
	$MainVBox/CategoryTabs/InteriorButton
)

@onready var construction_button: Button = (
	$MainVBox/CategoryTabs/ConstructionButton
)

var category_buttons: Dictionary = {}
var furniture_buttons: Dictionary = {}

var selected_category: String = "store"
var selected_furniture_id: String = ""
var crafting: bool = false
var guide_summary: Label
var furniture_preview: FurniturePreview


func _ready() -> void:
	furniture_preview = FurniturePreview.new()
	name_label.get_parent().add_child(furniture_preview)
	name_label.get_parent().move_child(furniture_preview, name_label.get_index() + 1)
	furniture_preview.visible = false
	if FurnitureGuide.ENABLED:
		guide_summary = Label.new()
		guide_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		guide_summary.add_theme_font_size_override("font_size",18)
		name_label.get_parent().add_child(guide_summary)
		name_label.get_parent().move_child(guide_summary,name_label.get_index()+1)
	# 고정 레이아웃은 management_blueprint.tscn에서 관리한다.
	category_buttons = {
		"store": store_button,
		"production": production_button,
		"interior": interior_button,
		"construction": construction_button,
	}

	for raw_category_id in category_buttons:
		var category_id: String = str(
			raw_category_id
		)
		var button: Button = category_buttons[raw_category_id]

		button.pressed.connect(
			_on_category_pressed.bind(
				category_id
			)
		)

	craft_button.pressed.connect(_on_craft_pressed)
	refresh_view()


func _on_category_pressed(category_id: String) -> void:
	if not ShopSpaceProgression.category_visible(category_id): return
	if crafting:
		_update_category_buttons()
		return

	if selected_category != category_id:
		selected_category = category_id
		selected_furniture_id = ""
		list_scroll.scroll_vertical = 0

	refresh_view()


func _update_category_buttons() -> void:
	for raw_id in category_buttons:
		var category_id: String = str(raw_id)
		var button: Button = category_buttons[category_id]
		button.visible = ShopSpaceProgression.category_visible(category_id)

		button.set_pressed_no_signal(
			category_id == selected_category
		)


func _update_furniture_buttons() -> void:
	for raw_id in furniture_buttons:
		var furniture_id: String = str(raw_id)
		var button: Button = furniture_buttons[furniture_id]

		button.set_pressed_no_signal(
			furniture_id == selected_furniture_id
		)


func _get_visible_furniture_ids() -> Array[String]:
	var result: Array[String] = []

	# 레시피가 등록된 가구만 대상으로 함
	var ids: Array[String] = (
		FurnitureRecipeData.get_all_furniture_ids()
	)

	for furniture_id in ids:
		if not ShopSpaceProgression.furniture_visible(furniture_id): continue
		var data: Dictionary = FurnitureData.get_furniture(
			furniture_id
		)

		if data.is_empty():
			continue

		if str(data.get("craft_category", "")) != selected_category:
			continue

		if not BuildObjectData.has_build_object(furniture_id):
			continue

		result.append(furniture_id)

	return result


func refresh_view() -> void:
	if not is_instance_valid(furniture_list):
		return
	if not ShopSpaceProgression.category_visible(selected_category):
		selected_category = "store"
		selected_furniture_id = ""

	_update_category_buttons()

	furniture_buttons.clear()

	for child in furniture_list.get_children():
		furniture_list.remove_child(child)
		child.queue_free()

	var ids: Array[String] = _get_visible_furniture_ids()

	for furniture_id in ids:
		var button := Button.new()

		button.text = FurnitureData.get_furniture_name(
			furniture_id
		)
		if not FurnitureObjectCatalog.locked_reason(furniture_id).is_empty():
			button.text += " · 미해금"
		button.toggle_mode = true
		button.custom_minimum_size.y = 42

		button.pressed.connect(
			_select_furniture.bind(furniture_id)
		)

		furniture_list.add_child(button)
		furniture_buttons[furniture_id] = button

	if not ids.has(selected_furniture_id):
		selected_furniture_id = ""

	if ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "등록된 제작품이 없습니다."
		furniture_list.add_child(empty_label)

		_clear_detail("이 분류에는 등록된 제작 레시피가 없습니다.")
		return

	if selected_furniture_id.is_empty():
		_clear_detail("왼쪽 목록에서 제작할 가구를 선택하세요.")
		return

	_select_furniture(selected_furniture_id)


func _clear_detail(message: String) -> void:
	if is_instance_valid(guide_summary): guide_summary.hide()
	furniture_preview.visible = false
	selected_furniture_id = ""

	name_label.text = "제작할 가구를 선택하세요"
	description_label.text = message
	owned_label.text = ""
	material_label.text = ""
	craft_button.text = "1개 제작"
	craft_button.disabled = true

	_update_furniture_buttons()


func _select_furniture(furniture_id: String) -> void:
	if not ShopSpaceProgression.furniture_visible(furniture_id):
		_clear_detail("현재 공간에서 사용할 집기를 먼저 준비하세요.")
		return
	var data: Dictionary = FurnitureData.get_furniture(
		furniture_id
	)
	var recipe: Dictionary = FurnitureRecipeData.get_recipe(
		furniture_id
	)

	if data.is_empty() or recipe.is_empty():
		_clear_detail("제작 정보를 찾을 수 없습니다.")
		return

	if str(data.get("craft_category", "")) != selected_category:
		_clear_detail("현재 분류에 해당하는 가구를 선택하세요.")
		return

	if selected_furniture_id != furniture_id:
		$MainVBox/Body/DetailPanel/DetailScroll.scroll_vertical = 0
	selected_furniture_id = furniture_id
	furniture_preview.show_furniture(furniture_id)
	_update_furniture_buttons()

	name_label.text = (
		FurnitureData.get_furniture_name(furniture_id)
		+ " ×1"
	)

	description_label.text = (
		str(data.get("description", ""))
		+ ShopSpaceProgression.furniture_purpose(furniture_id)
		+ FurnitureObjectCatalog.detail(furniture_id)
		+ _get_effect_description(furniture_id)
	)

	if FurnitureGuide.ENABLED:
		description_label.text = FurnitureGuide.description(furniture_id,true)
		guide_summary.text = FurnitureGuide.overview(furniture_id)
		guide_summary.visible = not guide_summary.text.is_empty()

	owned_label.text = (
		"미설치 보유 수량: %d개"
		% GameState.get_furniture_count(furniture_id)
	)

	var required: Dictionary = (
		ProductionRecipeService.collect_required_ingredients(
			recipe,
			1
		)
	)

	var lines: Array[String] = ["필요 재료"]
	var enough: bool = not required.is_empty()

	for raw_item_id in required:
		var item_id: String = str(raw_item_id)
		var needed: int = int(required[item_id])
		var owned: int = GameState.get_item_count(item_id)

		var line_text: String = "%s · 보유 %d / 필요 %d" % [
			ItemData.get_item_name(item_id),
			owned,
			needed
		]

		if owned < needed:
			enough = false
			line_text += " (%d개 부족)" % (needed - owned)

		lines.append(line_text)

	if required.is_empty():
		lines.append("유효한 재료 정보가 없습니다.")

	material_label.text = "\n".join(lines)
	craft_button.text = "1개 제작"
	craft_button.disabled = crafting or not enough or not FurnitureObjectCatalog.locked_reason(furniture_id).is_empty()
	if not FurnitureObjectCatalog.locked_reason(furniture_id).is_empty(): craft_button.text = "아직 만들 수 없습니다"


func _on_craft_pressed() -> void:
	if crafting:
		return

	if selected_furniture_id.is_empty():
		return

	var furniture_id: String = selected_furniture_id

	if (
		not FurnitureData.has_furniture(furniture_id)
		or not BuildObjectData.has_build_object(furniture_id)
	):
		return

	var recipe: Dictionary = FurnitureRecipeData.get_recipe(
		furniture_id
	)

	if recipe.is_empty():
		return

	crafting = true
	craft_button.disabled = true

	# 클릭 시점의 재료를 다시 검사하고 차감
	var consumed: bool = (
		FurnitureObjectCatalog.craft(furniture_id)
	)

	if not consumed:
		crafting = false
		_select_furniture(furniture_id)
		description_label.text += (
			"\n\n제작하지 못했습니다. 보유 재료를 확인해주세요."
		)
		return

	crafting = false
	refresh_view()

	description_label.text += (
		"\n\n제작 완료! 가구 인벤토리에 추가되었습니다."
	)

	DebugLog.write("[제작] ", furniture_id, " ×1")

func _get_effect_description(furniture_id: String) -> String:
	var effect: Dictionary = FurnitureData.get_effect_data(
		furniture_id
	)

	if effect.is_empty():
		return ""

	var effect_type: String = str(
		effect.get("effect_type", "")
	)
	var value: float = float(
		effect.get("effect_value", 0.0)
	)

	var effect_text: String = ""

	match effect_type:
		"reputation":
			var bonus: float = (
				DecorationEffectService.get_reputation_visit_bonus(
					value
				)
			)

			effect_text = (
				"평판 +%.1f\n동일 효과가 없는 매장에 1개 배치 시 방문 빈도 +%.1f%%"
				% [value, bonus * 100.0]
			)

		"customer_weight":
			var target: String = str(
				effect.get("effect_target", "")
			)
			var target_name: String = (
				CustomerTypeData.get_display_name(target)
			)

			var bonus: float = (
				DecorationEffectService.apply_diminishing_returns(
					value,
					DecorationEffectService.CUSTOMER_WEIGHT_HALF_VALUE,
					DecorationEffectService.CUSTOMER_WEIGHT_MAX_BONUS
				)
			)

			effect_text = (
				"%s 유치 기여도 +%.2f\n같은 대상의 효과가 없는 매장에 1개 배치 시 등장 가중치 +%.1f%%"
				% [target_name, value, bonus * 100.0]
			)

		"purchase_desire":
			var chance: float = (
				DecorationEffectService.apply_diminishing_returns(
					value,
					DecorationEffectService.PURCHASE_DESIRE_HALF_VALUE,
					DecorationEffectService.PURCHASE_DESIRE_MAX_CHANCE
				)
			)

			effect_text = (
				"구매욕구 기여도 +%.2f\n동일 효과가 없는 매장에 1개 배치 시 추가 구매 확률 %.1f%%"
				% [value, chance * 100.0]
			)

		_:
			return ""

	return (
		"\n\n[배치 효과]\n"
		+ effect_text
		+ "\n같은 효과를 많이 배치할수록 추가 효율이 감소합니다."
		+ "\n가방에 보관 중인 가구에는 효과가 없습니다."
	)
