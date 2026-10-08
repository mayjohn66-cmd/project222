class_name ProductionFacility
extends StaticBody2D

signal output_collected(item_id: String, amount: int)

enum ProductionState {
	IDLE,
	PROCESSING,
	READY
}

@export var facility_id: String = ""

var production_state: ProductionState = ProductionState.IDLE

var active_recipe_id: String = ""
var remaining_seconds: float = 0.0

var pending_item_id: String = ""
var pending_amount: int = 0
var reserved_collector: Node = null

@onready var status_label: Label = $StatusLabel
@onready var facility_name_label: Label = $Label


func _ready() -> void:
	add_to_group(
		"production_facility"
	)

	set_process(false)

	# 전용 씬을 사용하던 이전 방식과의 호환
	if not facility_id.is_empty():
		configure_facility(
			facility_id
		)
	else:
		var build_id: String = str(
			get_meta(
				"build_id",
				""
			)
		)

		if not build_id.is_empty():
			configure_facility(
				build_id
			)

	_refresh_production_status()

	call_deferred(
		"_configure_from_build_meta"
	)


func _configure_from_build_meta() -> void:
	var build_id: String = str(
		get_meta(
			"build_id",
			""
		)
	).strip_edges()

	if build_id.is_empty():
		push_warning(
			"[가공기 설정] build_id 메타가 없습니다."
		)
		return

	configure_facility(
		build_id
	)


func configure_facility(
	build_id: String
) -> void:
	if build_id.is_empty():
		push_error(
			"[가공기] build_id가 비어 있습니다."
		)
		return

	var furniture_data: Dictionary = (
		FurnitureData.get_furniture(
			build_id
		)
	)

	if furniture_data.is_empty():
		push_error(
			"[가공기] 등록되지 않은 가구: "
			+ build_id
		)
		return

	var category: String = str(
		furniture_data.get(
			"category",
			""
		)
	)

	if (
		category
		!= FurnitureData.CATEGORY_PRODUCTION
	):
		push_error(
			"[가공기] 생산 설비가 아닌 가구가 전달됨: "
			+ build_id
		)
		return

	# 동일한 설정이면 다시 처리하지 않음
	if (
		facility_id == build_id
		and has_meta("facility_id")
	):
		_refresh_facility_name()
		return

	# 이미 생산 중인 실제 설비를 다른 설비로 바꾸지 못하게 함
	if (
		not facility_id.is_empty()
		and facility_id != build_id
		and production_state
			!= ProductionState.IDLE
	):
		push_error(
			"[가공기] 생산 중에는 설비 종류를 변경할 수 없습니다."
		)
		return

	facility_id = build_id

	set_meta(
		"build_id",
		build_id
	)

	set_meta(
		"facility_id",
		facility_id
	)

	_refresh_facility_name()
	_refresh_production_status()


func _refresh_facility_name() -> void:
	var visual = get_node_or_null("Visual")
	if visual != null: visual.configure(facility_id)
	if not is_instance_valid(
		facility_name_label
	):
		return

	facility_name_label.text = (
		FurnitureData.get_furniture_name(
			facility_id
		)
	)

func can_start_production(
	recipe_id: String,
	production_count: int = 1
) -> bool:
	if not CraftingPathFlow.recipe_ready(recipe_id) or not FishingRecords.recipe_available(recipe_id): return false
	if production_state != ProductionState.IDLE:
		return false

	if bool(get_meta("is_build_preview", false)):
		return false

	if facility_id.is_empty():
		return false

	if production_count <= 0:
		return false

	var recipe: Dictionary = (
		ProductRecipeData.get_recipe(recipe_id)
	)

	if recipe.is_empty():
		return false

	if float(recipe.get("craft_time", 0.0)) <= 0.0:
		return false

	# 이 기계에 지정된 레시피만 허용
	var required_facility_id: String = str(
		recipe.get("facility_id", "")
	)

	if required_facility_id != facility_id:
		return false

	var result_item_id: String = str(
		recipe.get("result_item_id", "")
	)

	var result_amount: int = int(
		recipe.get("result_amount", 0)
	)

	if not ItemData.has_item(result_item_id):
		return false

	if result_amount <= 0:
		return false

	var required: Dictionary = (
		ProductionRecipeService.collect_required_ingredients(
			recipe,
			production_count
		)
	)

	if required.is_empty():
		return false

	for raw_item_id in required:
		var item_id: String = str(raw_item_id)

		if GameState.get_item_count(item_id) < int(required[item_id]):
			return false

	return true


func start_production(
	recipe_id: String,
	production_count: int = 1
) -> bool:
	if not can_start_production(recipe_id, production_count):
		return false

	var recipe: Dictionary = (
		ProductRecipeData.get_recipe(recipe_id)
	)

	if not ProductionRecipeService.consume_ingredients(
		recipe,
		production_count
	):
		return false

	reserved_collector = null


	active_recipe_id = recipe_id
	pending_item_id = str(recipe.get("result_item_id", ""))
	pending_amount = (
		int(recipe.get("result_amount", 0))
		* production_count
	)

	remaining_seconds = (
		float(recipe.get("craft_time", 0.0))
		* float(production_count)
	)

	production_state = ProductionState.PROCESSING
	set_process(true)
	_refresh_production_status()


	return true


func _process(delta: float) -> void:
	if production_state != ProductionState.PROCESSING:
		return

	remaining_seconds = maxf(
		remaining_seconds - delta,
		0.0
	)

	if remaining_seconds <= 0.0:
		production_state = ProductionState.READY
		set_process(false)


	_refresh_production_status()


func has_collectable_output() -> bool:
	if bool(
		get_meta(
			"is_build_preview",
			false
		)
	):
		return false

	return (
		production_state == ProductionState.READY
		and not pending_item_id.is_empty()
		and pending_amount > 0
		and ItemData.has_item(pending_item_id)
	)


func try_reserve_collector(
	worker: Node
) -> bool:
	if not is_instance_valid(worker):
		return false

	# 현재 실제 근무 중인 직원인지 검사
	if worker.has_method(
		"can_accept_production_task"
	):
		if not worker.can_accept_production_task():
			return false
	else:
		return false

	if not has_collectable_output():
		return false

	# 사라진 직원의 오래된 예약 제거
	if (
		reserved_collector != null
		and not is_instance_valid(reserved_collector)
	):
		reserved_collector = null

	# 같은 직원이 이미 예약했다면 그대로 성공 처리
	# 예약 출력은 다시 하지 않음
	if reserved_collector == worker:
		return true

	# 다른 직원이 이미 예약한 설비
	if is_instance_valid(reserved_collector):
		return false

	# 새로운 직원 예약
	reserved_collector = worker


	return true


func release_collector(
	worker: Node
) -> void:
	if reserved_collector != worker:
		return

	reserved_collector = null


func collect_output_by_worker(
	worker: Node
) -> bool:
	if not is_instance_valid(worker):
		return false

	if reserved_collector != worker:
		return false

	if not has_collectable_output():
		reserved_collector = null
		return false

	var success: bool = collect_production()

	if not success:
		return false

	reserved_collector = null


	return true


func collect_production() -> bool:
	if production_state != ProductionState.READY:
		return false

	if (
		pending_amount <= 0
		or not ItemData.has_item(pending_item_id)
	):
		push_warning("[가공기] 완성품 정보를 확인할 수 없습니다.")
		return false

	if pending_item_id.begins_with("fish_"):
		var fishing = load("res://script/world/shop/fishing/fishing_service.gd")
		if not fishing.capacity(pending_item_id, pending_amount): return false
	GameState.add_item(
		pending_item_id,
		pending_amount
	)
	FishingRecords.collected(pending_item_id, pending_amount)
	output_collected.emit(pending_item_id, pending_amount)


	active_recipe_id = ""
	pending_item_id = ""
	pending_amount = 0
	remaining_seconds = 0.0
	reserved_collector = null

	production_state = ProductionState.IDLE
	set_process(false)
	_refresh_production_status()

	return true


func _refresh_production_status() -> void:
	if not is_instance_valid(status_label):
		return

	status_label.visible = production_state != ProductionState.IDLE and not bool(
		get_meta("is_build_preview", false)
	)

	match production_state:
		ProductionState.IDLE:
			status_label.text = "가공 대기"

		ProductionState.PROCESSING:
			status_label.text = "가공 중 · %d초" % ceili(
				remaining_seconds
			)

		ProductionState.READY:
			status_label.text = "%s ×%d\n회수 가능" % [
				ItemData.get_item_name(pending_item_id),
				pending_amount
			]

func can_remove_facility() -> bool:
	return (
		production_state == ProductionState.IDLE
		and active_recipe_id.is_empty()
		and pending_item_id.is_empty()
		and pending_amount == 0
		and remaining_seconds == 0.0
	)

func get_production_save_data() -> Dictionary:
	return {
		"production_state": int(production_state),
		"active_recipe_id": active_recipe_id,
		"remaining_seconds": remaining_seconds,
		"pending_item_id": pending_item_id,
		"pending_amount": pending_amount
	}


func apply_production_save_data(data: Dictionary) -> bool:
	# 생산 상태가 없는 이전 저장 파일은 기본 대기 상태 유지
	if data.is_empty():
		return true

	# 값을 적용하기 전에 전체 형식을 검사
	if not data.get("production_state") is int:
		return false

	if not data.get("active_recipe_id") is String:
		return false

	if not data.get("pending_item_id") is String:
		return false

	if not data.get("pending_amount") is int:
		return false

	var raw_seconds: Variant = data.get("remaining_seconds")

	if not (raw_seconds is float or raw_seconds is int):
		return false

	var saved_state: int = int(data["production_state"])
	var saved_recipe: String = str(data["active_recipe_id"])
	var saved_item: String = str(data["pending_item_id"])
	var saved_amount: int = int(data["pending_amount"])
	var saved_seconds: float = float(raw_seconds)

	if not is_finite(saved_seconds) or saved_seconds < 0.0:
		return false

	match saved_state:
		ProductionState.IDLE:
			if (
				not saved_recipe.is_empty()
				or not saved_item.is_empty()
				or saved_amount != 0
				or saved_seconds != 0.0
			):
				return false

		ProductionState.PROCESSING, ProductionState.READY:
			if saved_recipe.is_empty():
				return false

			if not ItemData.has_item(saved_item):
				return false

			if saved_amount <= 0:
				return false

			if (
				saved_state == ProductionState.READY
				and saved_seconds != 0.0
			):
				return false

		_:
			return false

	# 작업 예약은 저장하지 않으며 불러올 때 초기화
	reserved_collector = null

	active_recipe_id = saved_recipe
	pending_item_id = saved_item
	pending_amount = saved_amount
	remaining_seconds = saved_seconds

	match saved_state:
		ProductionState.IDLE:
			production_state = ProductionState.IDLE

		ProductionState.PROCESSING:
			if remaining_seconds > 0.0:
				production_state = ProductionState.PROCESSING
			else:
				production_state = ProductionState.READY

		ProductionState.READY:
			production_state = ProductionState.READY

	set_process(
		production_state == ProductionState.PROCESSING
	)

	_refresh_production_status()
	return true
