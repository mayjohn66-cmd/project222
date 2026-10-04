extends Node


const CUSTOMER_SCENE = preload(
	"res://scenes/shop/actors/customer.tscn"
)

# 편의점 앞을 지나던 행인이 입장할 기본 확률
# 이후 평판, 장식, 행사 등의 영향을 연결한다.
@export_range(0.0, 1.0, 0.05)
var base_store_interest_chance: float = 0.65

@export var max_customers: int = 3
@export var allow_debug_customer_spawn: bool = false

@onready var actors = $"../Actors"
@onready var build_manager = $"../BuildManager"
@onready var spawn_timer: Timer = $SpawnTimer
@onready var store_exterior: Node = $"../StoreExterior"
@onready var day_manager: Node = get_node_or_null("../DayManager")

var shop_open: bool = false
var base_spawn_interval: float = 1.0


func _ready():
	base_spawn_interval = spawn_timer.wait_time

	spawn_timer.timeout.connect(
		_on_spawn_timer_timeout
	)

	spawn_timer.stop()


func _input(event: InputEvent) -> void:
	# 에디터에서 옵션을 켠 경우에만 C키 수동 생성을 허용한다.
	if not allow_debug_customer_spawn:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_C:
				spawn_customer()


func _on_spawn_timer_timeout():

	if not shop_open:
		return

	# 건축 중에는 손님 생성 금지
	if build_manager.build_mode:
		return

	# 시간대별 도착률(customer_arrival.csv)에 따라 이번 틱에 행인이 나타날지 정한다.
	if not roll_time_based_arrival():
		return

	var customers: Array = (
		get_tree().get_nodes_in_group(
			"customer"
		)
	)

	if customers.size() >= max_customers:
		return

	var doors: Array[Node] = (
		get_available_entrance_doors()
	)

	if doors.is_empty():
		return
	spawn_customer()

# 시간당 도착률 λ로 이번 생성 틱에 행인이 나타날 확률을 구한다.
# 행인은 입장 확률(base_store_interest_chance)만큼만 들어오므로, 그 확률로 나눠서
# 최종 입장 손님 수의 기대값이 λ가 되게 한다. 평판 보너스는 틱 빈도와 입장 확률로 따로 더해진다.
func roll_time_based_arrival() -> bool:
	if not is_instance_valid(day_manager):
		return true

	var hour_seconds: float = day_manager.hour_timer.wait_time

	if hour_seconds <= 0.0:
		return true

	var rate: float = CustomerArrivalData.get_rate(
		int(day_manager.current_hour)
	)

	var chance: float = (
		rate
		* base_spawn_interval
		/ hour_seconds
		/ maxf(base_store_interest_chance, 0.05)
	)

	return randf() < clampf(chance, 0.0, 1.0)


# 설치가 완료된 일반 출입문만 가져온다.
# 건축 미리보기 문이나 데이터가 없는 문은 제외한다.
func get_available_entrance_doors() -> Array[Node]:
	var result: Array[Node] = []

	var doors: Array = (
		get_tree().get_nodes_in_group(
			"door"
		)
	)

	for door in doors:

		if not is_instance_valid(
			store_exterior
		):
			return []

		if not is_instance_valid(door):
			continue

		if door.is_queued_for_deletion():
			continue

		if not store_exterior.has_method(
			"get_random_sidewalk_route_for_door"
		):
			continue

		if bool(
			door.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		if not door.has_meta("anchor"):
			continue

		if not door.has_method(
			"get_customer_spawn_position"
		):
			continue

		if not door.has_method(
			"get_customer_target_position"
		):
			continue

		if not door.has_method(
			"get_customer_arrival_position"
		):
			continue

		if not store_exterior.has_method(
			"get_sidewalk_spawn_position_for_door"
		):
			continue

		if not store_exterior.has_method(
			"get_sidewalk_approach_position_for_door"
		):
			continue

		result.append(
			door
		)

	return result

func spawn_customer() -> void:
	var tutorial = get_parent().get_node_or_null("TutorialDirector")
	if tutorial != null and tutorial.enabled and not OpeningJourneyFlow.core_finished(): return
	var doors: Array[Node] = (
		get_available_entrance_doors()
	)

	if doors.is_empty():
		push_warning(
			"[행인 생성기] 사용할 수 있는 출입문이 없습니다."
		)
		return

	var door: Node = (
		doors.pick_random()
	)

	var sidewalk_route: Dictionary = (
		store_exterior.call(
			"get_random_sidewalk_route_for_door",
			door
		)
	)

	if sidewalk_route.is_empty():
		push_warning(
			"[행인 생성기] 보도 경로를 만들지 못했습니다."
		)
		return

	var customer: Node2D = (
		CUSTOMER_SCENE.instantiate()
		as Node2D
	)

	if not is_instance_valid(customer):
		return

	actors.add_child(
		customer
	)
	# Lock identity before the pedestrian appears; keep it throughout the visit.
	customer.choose_customer_type()
	var introduced_type := ResidentRequestFlow.pending_introduction()
	if not introduced_type.is_empty():
		customer.customer_type_id = introduced_type
		customer.customer_group_id = CustomerTypeData.get_group_id(introduced_type)
	var regular_visit := RegularCustomerVisits.prepare(customer,introduced_type)
	if not regular_visit: regular_visit = ExpeditionContactVisits.prepare(customer,introduced_type)
	customer.get_node("Visual").refresh_profile()

	# 손님은 반드시 도로 양쪽 끝 중 한 곳에서 생성된다.
	var start_position: Vector2 = (
		sidewalk_route.get(
			"start_position",
			Vector2.ZERO
		)
	)

	customer.global_position = (
		start_position
	)

	await get_tree().physics_frame

	if not is_instance_valid(customer):
		return

	# 도로 끝에서 편의점 앞 판단 위치까지
	# 필요하면 도로 모서리를 경유해 이동한다.
	var reached_decision: bool = await (
		move_customer_along_points(
			customer,
			sidewalk_route.get(
				"approach_positions",
				[]
			)
		)
	)

	if not reached_decision:
		return

	# 편의점 앞에서 잠시 매장을 바라본다.
	await get_tree().create_timer(
		0.2
	).timeout

	if not is_instance_valid(customer):
		return

	# 입장 여부는 한 번만 판정한다.
	var wants_to_enter: bool = (
		not introduced_type.is_empty() or regular_visit or should_pedestrian_enter_store()
	)

	if not wants_to_enter:
		# 관심이 없다면 보도를 따라 반대편 끝까지 간다.
		await move_customer_along_points(
			customer,
			sidewalk_route.get(
				"pass_positions",
				[]
			)
		)

		if is_instance_valid(customer):
			customer.queue_free()

		return

	# 관심이 생긴 손님은 보도에서 문 바깥으로 이동한다.
	var outside_door_position: Vector2 = (
		door.call(
			"get_customer_spawn_position"
		)
	)

	var inside_door_position: Vector2 = (
		door.call(
			"get_customer_target_position"
		)
	)

	var yard_distance: float = (
		customer.global_position.distance_to(
			outside_door_position
		)
	)

	var yard_duration: float = clampf(
		yard_distance / 180.0,
		0.3,
		2.0
	)

	var entrance_tween: Tween = (
		customer.create_tween()
	)

	entrance_tween.set_trans(
		Tween.TRANS_LINEAR
	)

	entrance_tween.tween_property(
		customer,
		"global_position",
		outside_door_position,
		yard_duration
	)

	entrance_tween.tween_interval(
		0.15
	)

	# 문 바깥에서 매장 안으로 진입한다.
	entrance_tween.tween_property(
		customer,
		"global_position",
		inside_door_position,
		0.45
	)

	await entrance_tween.finished

	if not is_instance_valid(customer):
		return

	customer.call(
		"start_shopping"
	)
	if customer.visit_recorded:
		ResidentRequestFlow.record_visit(customer.get_customer_type_id())

func set_shop_open(value: bool):
	shop_open = value

	if shop_open:
		refresh_spawn_interval()
		spawn_timer.start()

	else:
		spawn_timer.stop()

func refresh_spawn_interval() -> void:
	var reputation: float = maxf(
		build_manager.get_decoration_effect("reputation") + ResidentRequestFlow.reputation(),
		0.0
	)

	var bonus: float = (
		DecorationEffectService.get_reputation_visit_bonus(
			reputation
		)
	)

	var visit_multiplier: float = 1.0 + bonus

	spawn_timer.wait_time = (
		base_spawn_interval / visit_multiplier
	)

# 편의점 앞을 지나는 행인이 입장할지 결정한다.
# 기본 관심도에 매장의 평판·장식 보너스를 더한다.
func should_pedestrian_enter_store() -> bool:
	var reputation: float = maxf(
		build_manager.get_decoration_effect(
			"reputation"
		) + ResidentRequestFlow.reputation(),
		0.0
	)

	var reputation_bonus: float = (
		DecorationEffectService.get_reputation_visit_bonus(
			reputation
		)
	)

	# 평판 효과가 방문 빈도와 입장 확률에 동시에 적용되므로
	# 입장 확률에는 절반만 반영한다.
	var interest_bonus: float = (
		reputation_bonus * 0.5
	)

	var final_chance: float = clampf(
		base_store_interest_chance
		+ interest_bonus,
		0.05,
		0.95
	)

	return randf() <= final_chance

# 손님을 여러 경유점을 따라 순서대로 이동시킨다.
func move_customer_along_points(
	customer: Node2D,
	points: Array
) -> bool:
	const PEDESTRIAN_MOVE_SPEED: float = 180.0

	for point_value in points:
		if not is_instance_valid(customer):
			return false

		if not point_value is Vector2:
			continue

		var target_position: Vector2 = (
			point_value
		)

		var distance: float = (
			customer.global_position.distance_to(
				target_position
			)
		)

		var duration: float = maxf(
			distance / PEDESTRIAN_MOVE_SPEED,
			0.05
		)

		var move_tween: Tween = (
			create_tween()
		)

		move_tween.tween_property(
			customer,
			"global_position",
			target_position,
			duration
		)

		await move_tween.finished

	return is_instance_valid(customer)
