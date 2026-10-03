extends CharacterBody2D

const FACILITY_DIALOG_SCENE = preload(
	"res://scenes/shop/production/facility_dialog.tscn"
)

@onready var production_room = $"../../ProductionRoom"

var in_production_room: bool = false

@export var speed: float = 200.0
@export var interaction_distance: float = 70.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shelf_panel = $"../../UI/ShelfPanel"
@onready var money_label: Label = $"../../UI/HUD/MoneyLabel"
@onready var warehouse_room = $"../../WarehouseRoom"
@onready var rumor_dialog: AcceptDialog = $RumorDialog


var production_return_door: Node2D = null

var shop_stats_label: Label = null

var last_direction := Vector2.DOWN

var total_visitors: int = 0
var successful_sales: int = 0
var missed_sales: int = 0
var daily_revenue: int = 0

var facility_dialog: AcceptDialog = null

var money: int:
	get:
		return GameState.get_money()

	set(value):
		GameState.money = maxi(value, 0)

var daily_visitors_by_customer_type: Dictionary = {}
var daily_sold_items: Dictionary = {}
var daily_unmet_demand: Dictionary = {}

var facility_recipe_picker: OptionButton
var facility_detail_label: Label

var selected_facility: ProductionFacility = null
var facility_recipe_ids: Array[String] = []

var facility_start_button: Button
var facility_collect_button: Button

const MAX_FACILITY_PRODUCTION_COUNT: int = 5

var facility_production_count_row: HBoxContainer
var facility_production_count_spin_box: SpinBox

var in_warehouse_room: bool = false
var warehouse_return_door: Node2D = null

# ================================================== #


# 이동과 상호작용 입력

func _physics_process(_delta):
	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	velocity = direction * speed
	move_and_slide()

	if direction != Vector2.ZERO:
		last_direction = direction
	# Character visual observes resolved movement and stops when blocked or idle.


func _unhandled_input(event) -> void:
	if not event.is_action_pressed("interact"):
		return

	if event.is_echo():
		return

	# 가공기 상태창 닫기
	if (
		is_instance_valid(facility_dialog)
		and facility_dialog.visible
	):
		facility_dialog.hide()
		get_viewport().set_input_as_handled()
		return

	# 소문 대화창 닫기
	if (
		is_instance_valid(rumor_dialog)
		and rumor_dialog.visible
	):
		rumor_dialog.hide()
		get_viewport().set_input_as_handled()
		return

	# 진열대 창 닫기
	if shelf_panel.visible:
		shelf_panel.close()
		get_viewport().set_input_as_handled()
		return

	var world_interactions = get_node_or_null("../../WorldInteractions")
	if world_interactions and world_interactions.try_interact():
		get_viewport().set_input_as_handled()
		return

	# 소문 손님 우선
	if try_talk_to_rumor_customer():
		get_viewport().set_input_as_handled()
		return

	# 다음으로 가공기 검사
	if try_interact_with_facility():
		get_viewport().set_input_as_handled()
		return

	# 생산실 쪽
	if try_use_production_door():
		get_viewport().set_input_as_handled()
		return

	# 창고 쪽
	if try_use_warehouse_door():
		get_viewport().set_input_as_handled()
		return

	# 창고 선반 상태 확인
	if try_interact_with_warehouse_storage():
		get_viewport().set_input_as_handled()
		return

	# 마지막으로 진열대 검사
	try_restock_shelf()
	get_viewport().set_input_as_handled()


func try_restock_shelf():
	var nearest_shelf = null
	var nearest_distance: float = interaction_distance

	for shelf in get_tree().get_nodes_in_group("shelf"):
		var distance: float

		if shelf.has_method("get_interaction_distance"):
			distance = shelf.get_interaction_distance(
				global_position
	)
		else:
			distance = global_position.distance_to(
				shelf.global_position
	)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_shelf = shelf

	if nearest_shelf == null:
		DebugLog.write("근처에 진열대가 없음")
		return

	shelf_panel.open(
		nearest_shelf,
		self
	)


# 초기화와 기본 인벤토리·통계
func _ready():
	_create_facility_dialog()


	var current_scene = get_tree().current_scene

	if current_scene != null:
		shop_stats_label = (
			current_scene.get_node_or_null(
				"UI/HUD/ShopStatsLabel"
			) as Label
		)

	update_money_ui()
	update_shop_stats_ui()

	if GameState.has_player_state():
		apply_persistent_state(
			GameState.get_player_state()
		)


func update_money_ui():
	money_label.text = (
		"보유금: "
		+ str(money)
		+ "G"
	)


func get_item_count(
	item_id: String
) -> int:
	return GameState.get_item_count(
		item_id
	)


func add_item(
	item_id: String,
	amount: int
) -> void:
	GameState.add_item(
		item_id,
		amount
	)


func remove_item(
	item_id: String,
	amount: int
) -> int:
	return GameState.remove_item(
		item_id,
		amount
	)


func record_visitor(
	customer_type_id: String = ""
) -> void:
	total_visitors += 1

	if not customer_type_id.is_empty():
		daily_visitors_by_customer_type[
			customer_type_id
		] = (
			int(
				daily_visitors_by_customer_type.get(
					customer_type_id,
					0
				)
			)
			+ 1
		)

	update_shop_stats_ui()


func record_successful_sale(
	revenue_amount: int,
	item_id: String = "",
	quantity: int = 1
) -> void:

	successful_sales += 1
	daily_revenue += maxi(
		revenue_amount,
		0
	)

	if (
		not item_id.is_empty()
		and quantity > 0
	):
		daily_sold_items[item_id] = (
			int(
				daily_sold_items.get(
					item_id,
					0
				)
			)
			+ quantity
		)

	update_shop_stats_ui()


func record_missed_sale(
	item_id: String = "",
	missing_amount: int = 1
) -> void:

	missed_sales += 1

	if not item_id.is_empty():
		record_unmet_demand(
			item_id,
			missing_amount
		)

	update_shop_stats_ui()


func update_shop_stats_ui():
	if shop_stats_label == null:
		return

	shop_stats_label.text = (
		"방문객: "
		+ str(total_visitors)
		+ "\n구매: "
		+ str(successful_sales)
		+ "\n판매 실패: "
		+ str(missed_sales)
	)


func reset_shop_stats():
	total_visitors = 0
	successful_sales = 0
	missed_sales = 0
	daily_revenue = 0

	daily_visitors_by_customer_type.clear()
	daily_sold_items.clear()
	daily_unmet_demand.clear()

	update_shop_stats_ui()


func get_daily_shop_stats() -> Dictionary:
	return {
		"visitors": total_visitors,
		"sales": successful_sales,
		"missed": missed_sales,
		"revenue": daily_revenue,

		"visitors_by_customer_type": (
			daily_visitors_by_customer_type.duplicate(
				true
			)
		),

		"sold_items": (
			daily_sold_items.duplicate(true)
		),

		"unmet_demand": (
			daily_unmet_demand.duplicate(true)
		)
	}


func get_persistent_state() -> Dictionary:
	# 소지금은 GameState에서 별도로 관리
	return {}


func apply_persistent_state(
	_data: Dictionary
) -> void:
	update_money_ui()
	update_shop_stats_ui()

func get_money() -> int:
	return GameState.get_money()


func add_money(amount: int) -> void:
	if amount <= 0:
		return

	GameState.add_money(amount)
	update_money_ui()


func try_talk_to_rumor_customer() -> bool:

	var nearest_customer = null

	var nearest_distance: float = (
		interaction_distance
	)

	for customer in get_tree().get_nodes_in_group(
		"customer"
	):
		if not is_instance_valid(customer):
			continue

		if not customer.has_method(
			"can_share_rumor"
		):
			continue

		if not customer.can_share_rumor():
			continue

		var distance: float = (
			global_position.distance_to(
				customer.global_position
			)
		)

		if distance >= nearest_distance:
			continue

		nearest_distance = distance
		nearest_customer = customer

	if nearest_customer == null:
		return false

	var event_data: Dictionary = (
		nearest_customer.share_rumor_event()
	)

	if event_data.is_empty():
		return false

	show_rumor_dialog(
		event_data
	)

	return true

func show_rumor_dialog(
	event_data: Dictionary
) -> void:
	if not is_instance_valid(rumor_dialog):
		return

	rumor_dialog.title = "가게에서 들은 이야기"
	rumor_dialog.dialog_text = StoreEventStory.rumor_text(event_data, GameState.total_day)

	rumor_dialog.popup_centered(
		Vector2i(
			500,
			340
		)
	)

func record_unmet_demand(
	item_id: String,
	amount: int
) -> void:
	if item_id.is_empty():
		return

	if amount <= 0:
		return

	daily_unmet_demand[item_id] = (
		int(
			daily_unmet_demand.get(
				item_id,
				0
			)
		)
		+ amount
	)

# 생산 설비 상호작용

func _create_facility_dialog() -> void:
	facility_dialog = (
		FACILITY_DIALOG_SCENE.instantiate()
		as AcceptDialog
	)

	if facility_dialog == null:
		push_error(
			"[생산 설비] 조작 창을 생성하지 못했습니다."
		)
		return

	add_child(facility_dialog)

	facility_recipe_picker = (
		facility_dialog.get_node(
			"Content/RecipePicker"
		) as OptionButton
	)

	facility_production_count_row = (
		facility_dialog.get_node(
			"Content/ProductionCountRow"
		) as HBoxContainer
	)

	facility_production_count_spin_box = (
		facility_dialog.get_node(
			"Content/ProductionCountRow/ProductionCountSpinBox"
		) as SpinBox
	)

	facility_production_count_spin_box.max_value = (
		float(
			MAX_FACILITY_PRODUCTION_COUNT
		)
	)

	facility_detail_label = (
		facility_dialog.get_node(
			"Content/DetailLabel"
		) as Label
	)

	facility_start_button = (
		facility_dialog.get_node(
			"Content/StartButton"
		) as Button
	)

	facility_collect_button = (
		facility_dialog.get_node(
			"Content/CollectButton"
		) as Button
	)

	facility_recipe_picker.item_selected.connect(
		_on_facility_recipe_selected
	)

	facility_production_count_spin_box.value_changed.connect(
		_on_facility_production_count_changed
	)

	facility_start_button.pressed.connect(
		_on_facility_start_pressed
	)

	facility_collect_button.pressed.connect(
		_on_facility_collect_pressed
	)


func try_interact_with_facility() -> bool:
	var nearest_facility: ProductionFacility = null
	var nearest_distance: float = interaction_distance

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

		var distance: float = global_position.distance_to(
			facility.global_position
		)

		if distance >= nearest_distance:
			continue

		nearest_distance = distance
		nearest_facility = facility

	if nearest_facility == null:
		return false

	_show_facility_status(nearest_facility)
	return true


func _show_facility_status(
	facility: ProductionFacility
) -> void:
	if not is_instance_valid(facility):
		return

	if facility.is_queued_for_deletion():
		return

	selected_facility = facility
	facility_dialog.dialog_text = ""

	var facility_name: String = (
		FurnitureData.get_furniture_name(
			facility.facility_id
		)
	)

	if facility_name.is_empty():
		facility_name = facility.facility_id

	facility_dialog.title = facility_name

	_refresh_facility_dialog()

	facility_dialog.popup_centered(
		Vector2i(632, 552)
	)

func _fill_facility_recipes(
	facility: ProductionFacility
) -> void:
	facility_recipe_ids.clear()
	facility_recipe_picker.clear()

	var recipes: Array[Dictionary] = (
		ProductRecipeData.get_learned_recipes()
	)

	for recipe in recipes:
		var required_facility_id: String = str(
			recipe.get("facility_id", "")
		)

		if required_facility_id != facility.facility_id:
			continue

		var recipe_id: String = str(
			recipe.get("recipe_id", "")
		)
		var result_item_id: String = str(
			recipe.get("result_item_id", "")
		)
		var result_amount: int = int(
			recipe.get("result_amount", 0)
		)

		if (
			recipe_id.is_empty()
			or not ItemData.has_item(result_item_id)
			or result_amount <= 0
		):
			continue

		facility_recipe_ids.append(recipe_id)

		facility_recipe_picker.add_item(
			"%s ×%d" % [
				ItemData.get_item_name(result_item_id),
				result_amount
			]
		)

	if facility_recipe_ids.is_empty():
		facility_detail_label.text = (
			"이 설비에서 사용할 수 있는 레시피가 없습니다."
		)
		return

	facility_recipe_picker.show()
	facility_recipe_picker.select(0)
	_on_facility_recipe_selected(0)


func _get_selected_production_count() -> int:
	if not is_instance_valid(
		facility_production_count_spin_box
	):
		return 1

	return clampi(
		int(
			facility_production_count_spin_box.value
		),
		1,
		MAX_FACILITY_PRODUCTION_COUNT
	)


func _on_facility_production_count_changed(
	_value: float
) -> void:
	if not is_instance_valid(
		facility_recipe_picker
	):
		return

	var index: int = facility_recipe_picker.selected

	if (
		index < 0
		or index >= facility_recipe_ids.size()
	):
		return

	_on_facility_recipe_selected(
		index
	)


func _on_facility_recipe_selected(
	index: int
) -> void:
	if (
		not is_instance_valid(selected_facility)
		or selected_facility.is_queued_for_deletion()
	):
		facility_detail_label.text = (
			"설비를 찾을 수 없습니다. 창을 닫아주세요."
		)
		return

	if (
		index < 0
		or index >= facility_recipe_ids.size()
	):
		return

	var recipe_id: String = (
		facility_recipe_ids[index]
	)

	var recipe: Dictionary = (
		ProductRecipeData.get_recipe(
			recipe_id
		)
	)

	if recipe.is_empty():
		facility_detail_label.text = (
			"레시피를 찾을 수 없습니다."
		)
		return

	var production_count: int = (
		_get_selected_production_count()
	)

	var required: Dictionary = (
		ProductionRecipeService.collect_required_ingredients(
			recipe,
			production_count
		)
	)

	var craft_time: float = float(
		recipe.get(
			"craft_time",
			0.0
		)
	)

	var result_item_id: String = str(
		recipe.get(
			"result_item_id",
			""
		)
	)

	var result_amount: int = int(
		recipe.get(
			"result_amount",
			0
		)
	)

	var total_result_amount: int = (
		result_amount
		* production_count
	)

	var lines: Array[String] = [
		"생산 횟수: %d회" % production_count,
		"완성 수량: %s ×%d" % [
			ItemData.get_item_name(
				result_item_id
			),
			total_result_amount
		],
		"총 가공 시간: %d초" % ceili(
			craft_time
			* float(production_count)
		),
		"",
		"[필요 재료]"
	]

	if required.is_empty():
		lines.append(
			"유효한 재료 정보가 없습니다."
		)
	else:
		for raw_item_id in required:
			var item_id: String = str(
				raw_item_id
			)

			var needed: int = int(
				required[item_id]
			)

			var owned: int = (
				GameState.get_item_count(
					item_id
				)
			)

			var material_text: String = (
				"%s · 보유 %d / 필요 %d" % [
					ItemData.get_item_name(
						item_id
					),
					owned,
					needed
				]
			)

			if owned < needed:
				material_text += (
					" (%d개 부족)"
					% (needed - owned)
				)

			lines.append(
				material_text
			)

	lines.append("")

	var can_start: bool = (
		selected_facility.can_start_production(
			recipe_id,
			production_count
		)
	)

	if can_start:
		lines.append(
			"가공에 필요한 조건을 충족했습니다."
		)
	else:
		lines.append(
			"재료 또는 설비 상태를 확인해주세요."
		)

	facility_detail_label.text = (
		"\n".join(lines)
	)

	facility_dialog.show_recipe(recipe,production_count,selected_facility)

	facility_start_button.text = (
		"%d회 가공 시작"
		% production_count
	)

	facility_start_button.disabled = (
		not can_start
	)



func _refresh_facility_dialog() -> void:
	facility_recipe_picker.hide()
	facility_production_count_row.hide()
	facility_start_button.hide()
	facility_collect_button.hide()

	facility_start_button.disabled = true
	facility_collect_button.disabled = true

	if not is_instance_valid(selected_facility):
		facility_detail_label.text = "설비를 찾을 수 없습니다."
		return

	if selected_facility.is_queued_for_deletion():
		facility_detail_label.text = "철거된 설비입니다."
		return

	match selected_facility.production_state:
		ProductionFacility.ProductionState.IDLE:
			facility_production_count_row.show()
			facility_start_button.show()
			_fill_facility_recipes(
				selected_facility
			)

		ProductionFacility.ProductionState.PROCESSING:
			facility_detail_label.text = (
				"가공 중입니다."
				+ "\n남은 시간: %d초"
				% ceili(selected_facility.remaining_seconds)
				+ "\n\n창을 닫아도 가공은 계속됩니다."
			)

		ProductionFacility.ProductionState.READY:
			facility_detail_label.text = (
				"가공이 완료되었습니다."
				+ "\n\n%s ×%d"
				% [
					ItemData.get_item_name(
						selected_facility.pending_item_id
					),
					selected_facility.pending_amount
				]
				+ "\n회수하면 보유 인벤토리에 추가됩니다."
			)

			facility_collect_button.show()
			facility_collect_button.disabled = false

	facility_dialog.refresh_state(selected_facility)


func _on_facility_start_pressed() -> void:
	if not is_instance_valid(selected_facility):
		_refresh_facility_dialog()
		return

	if selected_facility.is_queued_for_deletion():
		_refresh_facility_dialog()
		return

	var index: int = facility_recipe_picker.selected

	if index < 0 or index >= facility_recipe_ids.size():
		return

	var recipe_id: String = facility_recipe_ids[index]

	facility_start_button.disabled = true

	var production_count: int = (
		_get_selected_production_count()
	)

	var started: bool = (
		selected_facility.start_production(
			recipe_id,
			production_count
		)
	)

	_refresh_facility_dialog()

	if not started:
		facility_detail_label.text += (
			"\n\n가공을 시작하지 못했습니다."
			+ "\n재료와 설비 상태를 확인해주세요."
		)


func _on_facility_collect_pressed() -> void:
	if not is_instance_valid(selected_facility):
		_refresh_facility_dialog()
		return

	if selected_facility.is_queued_for_deletion():
		_refresh_facility_dialog()
		return

	facility_collect_button.disabled = true

	var collected: bool = (
		selected_facility.collect_production()
	)

	_refresh_facility_dialog()

	if collected:
		facility_detail_label.text += (
			"\n\n완성품을 보유 인벤토리에 넣었습니다."
		)
	else:
		facility_detail_label.text += (
			"\n\n완성품을 회수하지 못했습니다."
		)

func _process(_delta: float) -> void:
	if not is_instance_valid(facility_dialog):
		return

	if not facility_dialog.visible:
		return

	if not is_instance_valid(selected_facility):
		facility_dialog.hide()
		return

	if selected_facility.is_queued_for_deletion():
		facility_dialog.hide()
		return

	match selected_facility.production_state:
		ProductionFacility.ProductionState.PROCESSING:
			# 가공 중에는 시간 표시만 갱신
			facility_detail_label.text = (
				"가공 중입니다."
				+ "\n남은 시간: %d초"
				% ceili(selected_facility.remaining_seconds)
				+ "\n\n창을 닫아도 가공은 계속됩니다."
			)

		ProductionFacility.ProductionState.READY:
			# 완료 화면으로 한 번만 전환
			if not facility_collect_button.visible:
				_refresh_facility_dialog()

	facility_dialog.refresh_state(selected_facility)

# 생산실 출입

func get_production_door_candidates() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var checked: Dictionary = {}

	# 1. 그룹에 등록된 문 검색
	for node in get_tree().get_nodes_in_group(
		"production_door"
	):
		if not is_instance_valid(node):
			continue

		if not node is Node2D:
			continue

		var node_id: int = node.get_instance_id()

		if checked.has(node_id):
			continue

		checked[node_id] = true
		result.append(node as Node2D)

	# 2. 그룹 등록이 빠진 경우 Objects에서 배치 데이터로 검색
	var objects_node: Node = get_node_or_null(
		"../../Objects"
	)

	if objects_node == null:
		return result

	for node in objects_node.get_children():
		if not is_instance_valid(node):
			continue

		if not node is Node2D:
			continue

		if node.is_queued_for_deletion():
			continue

		if bool(
			node.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		var build_id: String = str(
			node.get_meta(
				"build_id",
				""
			)
		)

		if build_id.is_empty():
			continue

		if (
			BuildObjectData.get_build_type(build_id)
			!= BuildObjectData.BUILD_TYPE_PRODUCTION_DOOR
		):
			continue

		var node_id: int = node.get_instance_id()

		if checked.has(node_id):
			continue

		checked[node_id] = true
		result.append(node as Node2D)

	return result

func try_use_production_door() -> bool:
	# 창고 안에서는 매장의 생산실 문을 검색하지 않는다.
	if in_warehouse_room:
		return false

	if not is_instance_valid(production_room):
		push_warning(
			"[생산실 문] ProductionRoom을 찾지 못했습니다."
		)
		return false

	if not is_instance_valid(production_room):
		push_warning("[생산실 문] ProductionRoom을 찾지 못했습니다.")
		return false

	# =========================
	# 생산실에서 매장으로 복귀
	# =========================
	if in_production_room:
		var entry_world: Vector2 = (
			production_room.get_entry_world_position()
		)

		if global_position.distance_to(
			entry_world
		) > interaction_distance:
			return false

		if not is_instance_valid(production_return_door):
			push_warning("[생산실 문] 복귀할 매장 문이 없습니다.")
			return true

		var exited: bool = (
			production_room.exit_actor(
				self,
				production_return_door
			)
		)

		if not exited:
			push_warning("[생산실 문] 매장 복귀에 실패했습니다.")
			return true

		in_production_room = false
		production_return_door = null

		return true

	# =========================
	# 매장의 생산실 문 검색
	# =========================
	var candidates: Array[Node2D] = (
		get_production_door_candidates()
	)

	if candidates.is_empty():
		return false

	var nearest_door: Node2D = null
	var nearest_distance: float = INF

	for door in candidates:
		if not is_instance_valid(door):
			continue

		if door.is_queued_for_deletion():
			continue

		var distance: float = (
			global_position.distance_to(
				door.global_position
			)
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_door = door

	if not is_instance_valid(nearest_door):
		return false

	# 문의 실제 위치와 셀 중심의 차이를 고려하여 여유를 둠
	var allowed_distance: float = maxf(
		interaction_distance,
		110.0
	)

	if nearest_distance > allowed_distance:
		return false

	production_return_door = nearest_door

	var entered: bool = production_room.enter_actor(
		self
	)

	if not entered:
		production_return_door = null
		push_warning("[생산실 문] 생산실 입장에 실패했습니다.")
		return true

	in_production_room = true

	return true


func get_warehouse_door_candidates() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var checked: Dictionary = {}

	# 그룹에 등록된 창고 문 검색
	for node in get_tree().get_nodes_in_group(
		"warehouse_door"
	):
		if not is_instance_valid(node):
			continue

		if not node is Node2D:
			continue

		if node.is_queued_for_deletion():
			continue

		if bool(
			node.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		var node_id: int = (
			node.get_instance_id()
		)

		if checked.has(node_id):
			continue

		checked[node_id] = true
		result.append(node as Node2D)

	# 그룹이 누락된 경우 Objects의 build_id로 다시 검색
	var objects_node: Node = get_node_or_null(
		"../../Objects"
	)

	if objects_node == null:
		return result

	for node in objects_node.get_children():
		if not is_instance_valid(node):
			continue

		if not node is Node2D:
			continue

		if node.is_queued_for_deletion():
			continue

		if bool(
			node.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		var build_id: String = str(
			node.get_meta(
				"build_id",
				""
			)
		)

		if build_id.is_empty():
			continue

		if (
			BuildObjectData.get_build_type(
				build_id
			)
			!= BuildObjectData.BUILD_TYPE_WAREHOUSE_DOOR
		):
			continue

		var node_id: int = (
			node.get_instance_id()
		)

		if checked.has(node_id):
			continue

		checked[node_id] = true
		result.append(node as Node2D)

	return result

func try_use_warehouse_door() -> bool:
	# 생산실 안에서는 매장의 창고 문을 검색하지 않는다.
	if in_production_room:
		return false

	if not is_instance_valid(warehouse_room):
		push_warning(
			"[창고 문] WarehouseRoom을 찾지 못했습니다."
		)
		return false

	# =========================
	# 창고에서 매장으로 복귀
	# =========================
	if in_warehouse_room:
		var entry_world: Vector2 = (
			warehouse_room.get_entry_world_position()
		)

		if global_position.distance_to(
			entry_world
		) > interaction_distance:
			return false

		if not is_instance_valid(
			warehouse_return_door
		):
			push_warning(
				"[창고 문] 복귀할 매장 문이 없습니다."
			)
			return true

		var exited: bool = (
			warehouse_room.exit_actor(
				self,
				warehouse_return_door
			)
		)

		if not exited:
			push_warning(
				"[창고 문] 매장 복귀에 실패했습니다."
			)
			return true

		in_warehouse_room = false
		warehouse_return_door = null

		return true

	# =========================
	# 매장의 창고 문 검색
	# =========================
	var candidates: Array[Node2D] = (
		get_warehouse_door_candidates()
	)

	if candidates.is_empty():
		return false

	var nearest_door: Node2D = null
	var nearest_distance: float = INF

	for door in candidates:
		if not is_instance_valid(door):
			continue

		if door.is_queued_for_deletion():
			continue

		var distance: float = (
			global_position.distance_to(
				door.global_position
			)
		)

		if distance >= nearest_distance:
			continue

		nearest_distance = distance
		nearest_door = door

	if not is_instance_valid(nearest_door):
		return false

	var allowed_distance: float = maxf(
		interaction_distance,
		110.0
	)

	if nearest_distance > allowed_distance:
		return false

	warehouse_return_door = nearest_door

	var entered: bool = (
		warehouse_room.enter_actor(
			self
		)
	)

	if not entered:
		warehouse_return_door = null

		push_warning(
			"[창고 문] 창고 입장에 실패했습니다."
		)
		return true

	in_warehouse_room = true

	return true

func try_interact_with_warehouse_storage() -> bool:
	if not in_warehouse_room:
		return false

	var nearest_storage: Node2D = null
	var nearest_distance: float = (
		interaction_distance
	)

	for node in get_tree().get_nodes_in_group(
		"warehouse_storage"
	):
		if not is_instance_valid(node):
			continue

		if not node is Node2D:
			continue

		if node.is_queued_for_deletion():
			continue

		if bool(
			node.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		var distance: float = (
			global_position.distance_to(
				node.global_position
			)
		)

		if distance >= nearest_distance:
			continue

		nearest_distance = distance
		nearest_storage = node as Node2D

	if nearest_storage == null:
		return false

	if not is_instance_valid(
		shelf_panel
	):
		push_warning(
			"[창고 선반] ShelfPanel을 찾지 못했습니다."
		)
		return true

	shelf_panel.open_warehouse(
		nearest_storage,
		self
	)

	return true
