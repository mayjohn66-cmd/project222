extends Node


const CUSTOMER_SCENE = preload(
	"res://scenes/actors/customer.tscn"
)


@export var max_customers: int = 3

@onready var actors = $"../Actors"
@onready var build_manager = $"../BuildManager"
@onready var spawn_timer: Timer = $SpawnTimer

var shop_open: bool = false

func _ready():
	spawn_timer.timeout.connect(
		_on_spawn_timer_timeout
	)

	spawn_timer.stop()

	print("CustomerSpawner 준비 완료")


func _input(event):
	# 테스트용 수동 생성
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_C:
				spawn_customer()


func _on_spawn_timer_timeout():
	print(
		"[손님 생성 확인] ",
		"shop_open:", shop_open,
		" / build_mode:", build_manager.build_mode,
		" / timer_stopped:", spawn_timer.is_stopped()
	)

	if not shop_open:
		print("[손님 생성 차단] 가게가 닫혀 있음")
		return

	# 건축 중에는 손님 생성 금지
	if build_manager.build_mode:
		print("[손님 생성 차단] 건축 모드")
		return

	var customers: Array = (
		get_tree().get_nodes_in_group(
			"customer"
		)
	)

	print(
		"[손님 생성 확인] 현재 손님: ",
		customers.size(),
		" / 최대: ",
		max_customers
	)

	if customers.size() >= max_customers:
		print("[손님 생성 차단] 최대 인원")
		return

	var doors: Array = (
		get_tree().get_nodes_in_group(
			"door"
		)
	)

	if doors.is_empty():
		print("[손님 생성 차단] 문 없음")
		return

	print("[손님 생성 실행]")

	spawn_customer()

func spawn_customer():
	var doors: Array = (
		get_tree().get_nodes_in_group(
			"door"
		)
	)

	if doors.is_empty():
		print(
			"손님 생성 실패: 문이 없습니다."
		)
		return

	var door = doors[0]

	var customer = (
		CUSTOMER_SCENE.instantiate()
	)

	actors.add_child(
		customer
	)

	customer.global_position = (
		door.get_customer_target_position()
	)

	print(
		"손님 생성 / 현재 손님 수: ",
		get_tree()
		.get_nodes_in_group(
			"customer"
		)
		.size()
	)

	await get_tree().physics_frame

	if is_instance_valid(customer):
		customer.start_shopping()

func set_shop_open(value: bool):
	shop_open = value

	if shop_open:
		spawn_timer.start()

		print(
			"[손님 생성기] 영업 시작",
			" / Timer Wait Time: ",
			spawn_timer.wait_time
		)

	else:
		spawn_timer.stop()

		print("[손님 생성기] 영업 종료")

func start_spawning():
	process_mode = Node.PROCESS_MODE_INHERIT

	if spawn_timer.is_stopped():
		spawn_timer.start()

	print("[손님 생성기] 시작")

func stop_spawning():
	if not spawn_timer.is_stopped():
		spawn_timer.stop()

	print("[손님 생성기] 중지")
