extends StaticBody2D


const BUILD_AREA_RULES_SCRIPT = preload(
	"res://script/build/model/build_area_rules.gd"
)

var build_area_rules = (
	BUILD_AREA_RULES_SCRIPT.new()
)

func get_area_profile() -> RegisterAreaProfile:
	var build_id: String = str(
		get_meta("build_id", "")
	)

	if build_id.is_empty():
		return null

	return BuildObjectData.get_register_area_profile(
		build_id
	)


func get_checkout_offsets(
	rotation_index: int
) -> Array[Vector2i]:
	var profile: RegisterAreaProfile = get_area_profile()

	if profile == null:
		return []

	return profile.get_checkout_offsets(rotation_index)


func get_worker_cells() -> Array[Vector2i]:
	var profile: RegisterAreaProfile = get_area_profile()

	if profile == null:
		return []

	var saved_rotation: int = int(
		get_meta("rotation_index", 0)
	)

	return offsets_to_world_cells(
		profile.get_worker_offsets(saved_rotation)
	)


func get_checkout_cells() -> Array[Vector2i]:
	var saved_rotation: int = int(
		get_meta("rotation_index", 0)
	)

	return offsets_to_world_cells(
		get_checkout_offsets(saved_rotation)
	)


func offsets_to_world_cells(
	offsets: Array[Vector2i]
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if not has_meta("anchor"):
		return result

	var anchor: Vector2i = get_meta("anchor")

	for offset in offsets:
		var cell: Vector2i = anchor + offset

		if not result.has(cell):
			result.append(cell)

	return result


func get_body_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []

	if not has_meta("anchor"):
		return empty_cells

	var build_id: String = str(
		get_meta("build_id", "")
	)

	if build_id.is_empty():
		push_warning(
			"[계산대] 본체 크기를 조회할 build_id가 없음"
		)
		return empty_cells

	var build_data: Dictionary = (
		BuildObjectData.get_build_object(
			build_id
		)
	)

	if build_data.is_empty():
		push_warning(
			"[계산대] 건축 데이터 없음: "
			+ build_id
		)
		return empty_cells

	var base_size: Vector2i = build_data.get(
		"grid_size",
		Vector2i.ZERO
	)

	var saved_rotation: int = int(
		get_meta("rotation_index", 0)
	)

	var rotated_size: Vector2i = (
		build_area_rules.get_rotated_size(
			base_size,
			saved_rotation
		)
	)

	var anchor: Vector2i = get_meta("anchor")

	return build_area_rules.get_occupied_cells(
		anchor,
		rotated_size
	)

var waiting_customer = null
var reserved_worker = null
var worker_cell_users: Dictionary = {}

func reserve_tutorial_cashier(player_node: Node, cell: Vector2i) -> bool:
	if has_waiting_customer() or not get_worker_cells().has(cell): return false
	# 연습은 도착률이나 직원 대기 자리 예약 때문에 무기한 미뤄지면 안 된다.
	for worker in worker_cell_users.values().duplicate():
		if not is_instance_valid(worker) or worker == player_node: continue
		if worker.has_method("release_worker_position"): worker.release_worker_position()
		else: release_worker_cell(worker)
	if is_instance_valid(reserved_worker) and reserved_worker != player_node:
		var previous = reserved_worker
		if previous.has_method("release_register_reservation"):
			previous.release_register_reservation()
			previous.pending_register = null
			previous.finish_current_work()
		reserved_worker = null
	return try_reserve_worker(player_node) and try_reserve_worker_cell(cell, player_node)


func request_checkout(customer) -> bool:
	if has_waiting_customer():
		return false

	waiting_customer = customer

	DebugLog.write("계산 대기 손님 등록")

	return true


func has_waiting_customer() -> bool:
	return is_instance_valid(
		waiting_customer
	)


func get_waiting_customer():
	if not has_waiting_customer():
		waiting_customer = null
		return null

	return waiting_customer


func finish_checkout():
	waiting_customer = null



func debug_service_cells():
	DebugLog.write(
		"계산대 본체: ",
		get_body_cells()
	)

	DebugLog.write(
		"직원 위치: ",
		get_worker_cells()
	)

	DebugLog.write(
		"손님 위치: ",
		get_checkout_cells()
	)


func try_reserve_worker(worker_node) -> bool:
	# 첫 손님 튜토리얼은 플레이어의 결제를 기다린다.
	var customer = get_waiting_customer()
	if customer != null and customer.has_method("can_be_checked_out_by") \
			and not customer.can_be_checked_out_by(worker_node):
		return false
	if is_instance_valid(reserved_worker):
		return reserved_worker == worker_node

	reserved_worker = worker_node
	return true


func is_reserved_for_other(worker_node) -> bool:
	if not is_instance_valid(reserved_worker):
		reserved_worker = null
		return false

	return reserved_worker != worker_node


func release_worker_reservation(worker_node):
	if reserved_worker == worker_node:
		reserved_worker = null

func cleanup_worker_cell_users() -> void:
	var valid_cells: Array[Vector2i] = (
		get_worker_cells()
	)

	var cells_to_remove: Array[Vector2i] = []

	for raw_cell in worker_cell_users.keys():
		var cell: Vector2i = raw_cell
		var worker = worker_cell_users[cell]

		if not is_instance_valid(worker):
			cells_to_remove.append(cell)
			continue

		if worker.is_queued_for_deletion():
			cells_to_remove.append(cell)
			continue

		if not valid_cells.has(cell):
			cells_to_remove.append(cell)

	for cell in cells_to_remove:
		worker_cell_users.erase(cell)


func is_worker_cell_available(
	cell: Vector2i,
	worker_node
) -> bool:
	if not is_instance_valid(worker_node):
		return false

	# 리소스에 설정된 직원 작업 칸만 허용
	if not get_worker_cells().has(cell):
		return false

	cleanup_worker_cell_users()

	if not worker_cell_users.has(cell):
		return true

	return worker_cell_users[cell] == worker_node


func try_reserve_worker_cell(
	cell: Vector2i,
	worker_node
) -> bool:
	if not is_worker_cell_available(
		cell,
		worker_node
	):
		return false

	# 같은 직원이 다른 칸을 예약했다면 이전 예약 해제
	release_worker_cell(worker_node)

	worker_cell_users[cell] = worker_node

	return true


func release_worker_cell(
	worker_node
):
	cleanup_worker_cell_users()

	var cells_to_remove: Array[Vector2i] = []

	for cell in worker_cell_users.keys():
		if worker_cell_users[cell] == worker_node:
			cells_to_remove.append(cell)

	for cell in cells_to_remove:
		worker_cell_users.erase(cell)
