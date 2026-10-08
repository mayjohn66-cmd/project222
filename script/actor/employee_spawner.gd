extends Node

@export var worker_scene: PackedScene

@onready var actors: Node = $"../Actors"


func _ready() -> void:
	# 다른 노드의 초기화가 끝난 뒤 직원 생성
	call_deferred("_spawn_missing_employees")


func _spawn_missing_employees() -> void:
	if worker_scene == null:
		push_error("[직원 생성] Worker Scene을 지정해주세요.")
		return

	if not is_instance_valid(actors):
		push_error("[직원 생성] Actors를 찾지 못했습니다.")
		return

	var existing_ids: Dictionary = {}

	# 씬에 이미 배치된 직원은 유지
	for actor in actors.get_children():
		if not actor.has_method("get_work_periods"):
			continue

		var employee_id: String = str(
			actor.get("employee_id")
		)

		if employee_id.is_empty():
			push_error(
				"[직원 생성] 기존 직원의 Employee Id가 비어 있습니다: "
				+ str(actor.name)
			)
			return

		if existing_ids.has(employee_id):
			push_error(
				"[직원 생성] 중복 Employee Id: "
				+ employee_id
			)
			return

		existing_ids[employee_id] = true

	var created_count: int = 0

	for employee_id in EmployeeData.get_all_employee_ids():
		if existing_ids.has(employee_id):
			continue

		var instance: Node = worker_scene.instantiate()

		if (
			not instance is CharacterBody2D
			or not instance.has_method("get_work_periods")
			or not instance.has_method("set_work_periods")
		):
			instance.free()
			push_error(
				"[직원 생성] worker.gd가 연결된 직원 씬이 필요합니다."
			)
			return

		# _ready() 실행 전에 ID 지정
		instance.set("employee_id", employee_id)
		instance.name = "Employee_" + employee_id

		# 기존 ../../Floor, ../../DayManager 경로 유지
		actors.add_child(instance)

		existing_ids[employee_id] = true
		created_count += 1

	EmployeeRecruitmentFlow.initialize(get_tree().get_nodes_in_group("worker"))
	if EmployeeRecruitmentFlow.enabled() and not get_parent().has_node("EmployeeRecruitmentDirector"):
		var recruitment := EmployeeRecruitmentDirector.new()
		recruitment.name = "EmployeeRecruitmentDirector"
		get_parent().add_child(recruitment)

	DebugLog.write(
		"[직원 생성] 자동 생성 완료 / 추가: ",
		created_count
	)
