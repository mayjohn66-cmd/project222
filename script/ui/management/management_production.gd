extends Control

# 생산 레시피와 현재 배치된 생산 설비 상태를 표시한다.
# 탭과 고정 레이아웃은 씬에서 관리하고, 레시피 버튼과 설비 상태 문구만
# 데이터에 맞춰 동적으로 갱신한다.


@onready var facility_status_button: Button = (
	$ProductionTabBar/FacilityStatusButton
)

@onready var recipe_tab_button: Button = (
	$ProductionTabBar/RecipeTabButton
)

@onready var facility_status_scroll: ScrollContainer = (
	$FacilityStatusScroll
)

@onready var facility_status_label: Label = (
	$FacilityStatusScroll/FacilityStatusLabel
)


@onready var recipe_list: VBoxContainer = (
	$MainHBox/LeftPanel/LeftVBox/RecipeScroll/RecipeList
)

@onready var product_name_label: Label = (
	$MainHBox/RightPanel/DetailVBox/ProductNameLabel
)

@onready var description_label: Label = (
	$MainHBox/RightPanel/DetailVBox/DescriptionLabel
)

@onready var material_list: VBoxContainer = (
	$MainHBox/RightPanel/DetailVBox/MaterialList
)

@onready var facility_label: Label = (
	$MainHBox/RightPanel/DetailVBox/FacilityLabel
)

@onready var amount_spin_box: SpinBox = (
	$MainHBox/RightPanel/DetailVBox/AmountHBox/AmountSpinBox
)

@onready var start_button: Button = (
	$MainHBox/RightPanel/DetailVBox/StartButton
)

@onready var max_amount_button: Button = (
	$MainHBox/RightPanel/DetailVBox/AmountHBox/MaxAmountButton
)

@onready var min_amount_button: Button = (
	$MainHBox/RightPanel/DetailVBox/AmountHBox/MinAmountButton
)


var selected_recipe_id: String = ""
var production_processing: bool = false

var showing_facility_status: bool = true

func _ready() -> void:
	ProductRecipeData.ensure_loaded()

	amount_spin_box.value_changed.connect(
		_on_amount_changed
	)

	if not start_button.pressed.is_connected(
		_on_start_pressed
	):
		start_button.pressed.connect(
			_on_start_pressed
		)

	start_button.disabled = true

	refresh_recipe_list()
	clear_recipe_detail()

	DebugLog.write("[관리 생산] 준비 완료")

	amount_spin_box.min_value = 1
	amount_spin_box.step = 1


	max_amount_button.pressed.connect(
		_on_max_amount_pressed
	)

	min_amount_button.pressed.connect(
		_on_min_amount_pressed
	)

	# 관리 메뉴에서는 레시피 1회분만 확인
	amount_spin_box.value = 1
	amount_spin_box.editable = false
	amount_spin_box.get_parent().hide()

	start_button.disabled = true
	start_button.hide()

	_setup_facility_status_view()
	refresh_facility_status()


func refresh_recipe_list() -> void:
	clear_container(recipe_list)

	var recipes: Array[Dictionary] = (
		ProductRecipeData.get_learned_recipes()
	)

	for recipe in recipes:
		create_recipe_button(recipe)

	DebugLog.write(
		"[관리 생산] 레시피 목록 생성 / ",
		recipes.size(),
		"개"
	)


func create_recipe_button(
	recipe: Dictionary
) -> void:
	var recipe_id: String = str(
		recipe.get(
			"recipe_id",
			""
		)
	)

	var result_item_id: String = str(
		recipe.get(
			"result_item_id",
			""
		)
	)

	if recipe_id.is_empty():
		return

	var button := Button.new()

	button.text = get_item_display_name(
		result_item_id
	)

	button.custom_minimum_size = Vector2(
		0,
		40
	)

	button.pressed.connect(
		select_recipe.bind(
			recipe_id
		)
	)

	button.icon = ItemData.get_item_icon(result_item_id)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width",32)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 56
	recipe_list.add_child(button)


func select_recipe(
	recipe_id: String
) -> void:
	var recipe: Dictionary = (
		ProductRecipeData.get_recipe(
			recipe_id
		)
	)

	if recipe.is_empty():
		return

	selected_recipe_id = recipe_id

	amount_spin_box.value = 1

	refresh_recipe_detail()

	DebugLog.write(
		"[관리 생산] 레시피 선택: ",
		selected_recipe_id
	)


func refresh_recipe_detail() -> void:
	if selected_recipe_id.is_empty():
		clear_recipe_detail()
		return

	var recipe: Dictionary = (
		ProductRecipeData.get_recipe(
			selected_recipe_id
		)
	)

	if recipe.is_empty():
		clear_recipe_detail()
		return

	var result_item_id: String = str(
		recipe.get(
			"result_item_id",
			""
		)
	)

	var result_amount: int = int(
		recipe.get(
			"result_amount",
			1
		)
	)

	var production_count: int = 1

	product_name_label.text = (
		get_item_display_name(
			result_item_id
		)
		+ " ×"
		+ str(
			result_amount
			* production_count
		)
	)

	description_label.text = (
		"레시피 1회분의 재료와 필요한 설비를 확인합니다."
		+ "\n가공과 완성품 회수는 설치한 설비에서 진행합니다."
	)

	refresh_material_list(
		recipe,
		production_count
	)

	var facility_id: String = str(
		recipe.get(
			"facility_id",
			""
		)
	)

	var facility_available: bool = (
		has_required_facility(recipe)
	)

	if facility_id.is_empty():
		facility_label.text = "필요 설비: 없음"
		facility_label.modulate = Color.WHITE
	else:
		facility_label.text = (
			"필요 설비: "
			+ get_facility_display_name(facility_id)
		)

		if facility_available:
			facility_label.text += " (설치됨)"
			facility_label.modulate = Color(
				0.65, 1.0, 0.65
			)
		else:
			facility_label.text += " (미설치)"
			facility_label.modulate = Color(
				1.0, 0.55, 0.45
			)

	start_button.disabled = true


func refresh_material_list(
	recipe: Dictionary,
	production_count: int
) -> void:
	clear_container(material_list)

	var required: Dictionary = (
		collect_required_ingredients(
			recipe,
			production_count
		)
	)

	if required.is_empty():
		var label := Label.new()
		label.text = "유효한 재료 정보가 없습니다."
		material_list.add_child(label)
		return

	for raw_item_id in required:
		var item_id: String = str(raw_item_id)

		var required_amount: int = int(
			required[item_id]
		)

		var owned_amount: int = (
			GameState.get_item_count(item_id)
		)

		var shortage: int = maxi(
			required_amount - owned_amount,
			0
		)

		var label := Label.new()

		label.text = "%s    보유 %d / 필요 %d" % [
			get_item_display_name(item_id),
			owned_amount,
			required_amount
		]

		if shortage > 0:
			label.text += "    (%d개 부족)" % shortage
			label.modulate = Color(1.0, 0.55, 0.45)
		else:
			label.text += "    (충분)"
			label.modulate = Color(0.65, 1.0, 0.65)

		material_list.add_child(label)


func clear_recipe_detail() -> void:
	selected_recipe_id = ""

	facility_label.text = (
		"필요 설비: -"
	)

	facility_label.modulate = Color.WHITE

	product_name_label.text = (
		"상품을 선택하세요"
	)

	description_label.text = (
		"왼쪽 목록에서 확인할 레시피를 선택하세요."
		+ "\n실제 가공은 생산 설비에서 진행합니다."
	)

	facility_label.text = (
		"필요 설비: -"
	)

	amount_spin_box.value = 1

	start_button.disabled = true

	clear_container(material_list)


func get_item_display_name(
	item_id: String
) -> String:
	if item_id.is_empty():
		return "-"

	if ItemData.has_item(item_id):
		return ItemData.get_item_name(
			item_id
		)

	return item_id + " (미등록)"


func _on_amount_changed(
	_value: float
) -> void:
	if selected_recipe_id.is_empty():
		return

	refresh_recipe_detail()


func clear_container(
	container: Node
) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func has_required_facility(
	recipe: Dictionary
) -> bool:
	var facility_id: String = str(
		recipe.get(
			"facility_id",
			""
		)
	)

	if facility_id.is_empty():
		return true

	var facilities: Array[Node] = (
		get_tree().get_nodes_in_group(
			"production_facility"
		)
	)

	for facility in facilities:
		var placed_facility_id: String = str(
			facility.get_meta(
				"facility_id",
				""
			)
		)

		if not is_instance_valid(facility):
			continue

		if facility.is_queued_for_deletion():
			continue

		if bool(facility.get_meta("is_build_preview", false)):
			continue

		if placed_facility_id == facility_id:
			return true

	return false


func can_produce(
	recipe: Dictionary,
	production_count: int
) -> bool:
	if recipe.is_empty() or production_count <= 0:
		return false

	var result_item_id: String = str(
		recipe.get("result_item_id", "")
	)

	var result_amount: int = int(
		recipe.get("result_amount", 0)
	)

	# 완성품을 지급할 수 있는지 먼저 검사
	if not ItemData.has_item(result_item_id):
		return false

	if result_amount <= 0:
		return false

	if not has_required_facility(recipe):
		return false

	var required: Dictionary = (
		collect_required_ingredients(
			recipe,
			production_count
		)
	)

	if required.is_empty():
		return false

	for item_id in required:
		if GameState.get_item_count(item_id) < int(required[item_id]):
			return false

	return true

func _on_start_pressed() -> void:
	description_label.text = (
		"생산 구역의 설비와 상호작용하여 가공해주세요."
		+ "\n완성된 상품은 해당 설비에서 회수할 수 있습니다."
	)

func consume_ingredients(
	recipe: Dictionary,
	production_count: int
) -> bool:
	return ProductionRecipeService.consume_ingredients(
		recipe,
		production_count
	)


func get_facility_display_name(
	facility_id: String
) -> String:
	match facility_id:
		"drink_machine":
			return "음료 제조기"

		"magic_oven":
			return "마법 오븐"

		"cooking_table":
			return "조리대"

		_:
			return facility_id


func refresh_view() -> void:
	if not is_instance_valid(facility_status_scroll):
		return

	_select_production_tab(
		showing_facility_status
	)

func collect_required_ingredients(
	recipe: Dictionary,
	production_count: int
) -> Dictionary:
	return ProductionRecipeService.collect_required_ingredients(
		recipe,
		production_count
	)

func get_max_production_count(
	recipe: Dictionary
) -> int:
	if not can_produce(recipe, 1):
		return 0

	var required: Dictionary = (
		collect_required_ingredients(recipe, 1)
	)

	# 현재 수량 입력창의 상한 안에서 선택
	var max_count: int = int(
		amount_spin_box.max_value
	)

	for raw_item_id in required:
		var item_id: String = str(raw_item_id)

		var required_per_production: int = int(
			required[item_id]
		)

		var owned_amount: int = (
			GameState.get_item_count(item_id)
		)

		var possible_count: int = floori(
			float(owned_amount)
			/ float(required_per_production)
		)

		max_count = mini(
			max_count,
			possible_count
		)

	return max_count

func _on_max_amount_pressed() -> void:
	if production_processing:
		return

	if selected_recipe_id.is_empty():
		return

	var recipe: Dictionary = (
		ProductRecipeData.get_recipe(
			selected_recipe_id
		)
	)

	var max_count: int = (
		get_max_production_count(recipe)
	)

	if max_count <= 0:
		refresh_recipe_detail()

		description_label.text = (
			"생산할 수 없습니다. 재료와 설비를 확인해주세요."
		)
		return

	amount_spin_box.value = max_count

	refresh_recipe_detail()

func _on_min_amount_pressed() -> void:
	if production_processing:
		return

	if selected_recipe_id.is_empty():
		return

	amount_spin_box.value = 1

	refresh_recipe_detail()

func _setup_facility_status_view() -> void:
	# 고정 UI는 씬에 있으며 여기서는 동작만 연결한다.
	facility_status_button.pressed.connect(
		_select_production_tab.bind(true)
	)
	recipe_tab_button.pressed.connect(
		_select_production_tab.bind(false)
	)

	_select_production_tab(showing_facility_status)


func refresh_facility_status() -> void:
	if not is_instance_valid(facility_status_label):
		return

	var lines: Array[String] = [
		"생산 설비 현황"
	]

	var facility_count: int = 0

	for node in get_tree().get_nodes_in_group(
		"production_facility"
	):
		if not is_instance_valid(node):
			continue

		if node.is_queued_for_deletion():
			continue

		if not node is ProductionFacility:
			continue

		if bool(node.get_meta("is_build_preview", false)):
			continue

		var facility: ProductionFacility = (
			node as ProductionFacility
		)

		facility_count += 1

		var facility_name: String = (
			get_facility_display_name(
				facility.facility_id
			)
		)

		var status_text: String = ""

		match facility.production_state:
			ProductionFacility.ProductionState.IDLE:
				status_text = "대기 중"

			ProductionFacility.ProductionState.PROCESSING:
				status_text = (
					"%s ×%d · 남은 시간 %d초"
					% [
						get_item_display_name(
							facility.pending_item_id
						),
						facility.pending_amount,
						ceili(facility.remaining_seconds)
					]
				)

			ProductionFacility.ProductionState.READY:
				status_text = (
					"%s ×%d · 회수 대기"
					% [
						get_item_display_name(
							facility.pending_item_id
						),
						facility.pending_amount
					]
				)

		lines.append(
			"%d. %s\n   %s"
			% [
				facility_count,
				facility_name,
				status_text
			]
		)

	if facility_count == 0:
		lines.append("설치된 생산 설비가 없습니다.")

	facility_status_label.text = "\n\n".join(lines)
	_render_facility_cards()

func _select_production_tab(
	show_status: bool
) -> void:
	showing_facility_status = show_status

	facility_status_scroll.visible = show_status
	$MainHBox.visible = not show_status

	facility_status_button.disabled = show_status
	recipe_tab_button.disabled = not show_status

	if show_status:
		refresh_facility_status()
	elif not selected_recipe_id.is_empty():
		refresh_recipe_detail()

func _render_facility_cards() -> void:
	facility_status_label.hide()
	var old := facility_status_scroll.get_node_or_null("FacilityCards")
	if old:
		facility_status_scroll.remove_child(old)
		old.queue_free()
	var cards := GridContainer.new()
	cards.name = "FacilityCards"
	cards.columns = 1
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation",16)
	cards.add_theme_constant_override("v_separation",16)
	facility_status_scroll.add_child(cards)
	var found := {}
	for node in get_tree().get_nodes_in_group("production_facility"):
		if node is ProductionFacility and not node.is_queued_for_deletion() and not node.get_meta("is_build_preview",false):
			_add_facility_card(cards,node.facility_id,node)
			found[node.facility_id] = true
	for id in ["drink_machine","magic_oven"]:
		if not found.has(id): _add_facility_card(cards,id,null)

func _add_facility_card(cards: GridContainer, id: String, facility: ProductionFacility) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0,164)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("fff5df")
	paper.set_content_margin_all(18)
	paper.border_width_top = 4
	paper.border_color = Color("b06b3d")
	panel.add_theme_stylebox_override("panel",paper)
	cards.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	panel.add_child(row)
	var image := TextureRect.new()
	image.texture = FurnitureData.get_furniture_icon(id)
	image.custom_minimum_size = Vector2(80,80)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(image)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",10)
	row.add_child(content)
	var title := Label.new()
	title.text = get_facility_display_name(id)
	title.add_theme_font_size_override("font_size",22)
	content.add_child(title)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "미설치 · 설계도에서 제작할 수 있습니다."
	if facility:
		match facility.production_state:
			ProductionFacility.ProductionState.IDLE: status.text = "재료 준비 대기"
			ProductionFacility.ProductionState.PROCESSING: status.text = "가공 중 · %d초 남음" % ceili(facility.remaining_seconds)
			ProductionFacility.ProductionState.READY: status.text = "완성 · 회수할 수 있습니다."
	content.add_child(status)
	var note := Label.new()
	note.text = "반죽 → 굽기 → 완성" if id=="magic_oven" else "재료 → 혼합 → 병에 담기"
	note.add_theme_font_size_override("font_size",15)
	note.add_theme_color_override("font_color",Color("90694b"))
	content.add_child(note)
