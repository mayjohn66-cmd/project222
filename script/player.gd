extends CharacterBody2D

@export var speed: float = 200.0
@export var interaction_distance: float = 70.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shelf_panel = $"../../UI/ShelfPanel"
@onready var money_label: Label = $"../../UI/MoneyLabel"
var shop_stats_label: Label = null

var last_direction := Vector2.DOWN
var money: int = 0

var total_visitors: int = 0
var successful_sales: int = 0
var missed_sales: int = 0
var daily_revenue: int = 0

func _physics_process(_delta):
	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
        "move_down"
	)

	velocity = direction * speed
	move_and_slide()

	update_animation(direction)

func update_animation(direction: Vector2):
	if direction == Vector2.ZERO:
		return

	last_direction = direction

	var animation_name := get_direction_name(direction)

	sprite.play("walk_" + animation_name)

func get_direction_name(direction: Vector2) -> String:
	var angle := direction.angle()

	if angle >= -PI / 8 and angle < PI / 8:
		return "right"

	elif angle >= PI / 8 and angle < 3 * PI / 8:
		return "down_right"

	elif angle >= 3 * PI / 8 and angle < 5 * PI / 8:
		return "down"

	elif angle >= 5 * PI / 8 and angle < 7 * PI / 8:
		return "down_left"

	elif angle >= 7 * PI / 8 or angle < -7 * PI / 8:
		return "left"

	elif angle >= -7 * PI / 8 and angle < -5 * PI / 8:
		return "up_left"

	elif angle >= -5 * PI / 8 and angle < -3 * PI / 8:
		return "up"

	else:
		return "up_right"

func _unhandled_input(event):
	if event.is_action_pressed("interact"):
		# 이미 진열대 창이 열려 있으면 닫기
		if shelf_panel.visible:
			shelf_panel.close()
			return

		# 닫혀 있으면 근처 진열대 찾기
		try_restock_shelf()

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
		print("근처에 진열대가 없음")
		return

	shelf_panel.open(
		nearest_shelf,
		self
	)

func _ready():
	var current_scene = get_tree().current_scene

	if current_scene != null:
		shop_stats_label = (
			current_scene.get_node_or_null(
				"UI/ShopStatsLabel"
			) as Label
		)

	print(
		"ShopStatsLabel 확인: ",
		shop_stats_label
	)
	
	print(
	"통계 UI 확인: ",
	get_node_or_null(
		"../../UI/ShopStatsLabel"
	)
)
	print("물: ", get_item_count("water"))
	print("빵: ", get_item_count("bread"))
	print("포션: ", get_item_count("potion"))
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


func add_money(amount: int):
	if amount <= 0:
		return

	money += amount

	update_money_ui()

	print(
		"돈 획득: ",
		amount,
		" / 현재 돈: ",
		money
	)


func get_money() -> int:
	return money


func record_visitor():
	print(
		"[통계] 방문 전: ",
		total_visitors
	)

	total_visitors += 1

	print(
		"[통계] 방문 후: ",
		total_visitors
	)

	update_shop_stats_ui()
	print_shop_stats()


func record_successful_sale(
	amount: int
):

	print(
		"[통계] 구매 전: ",
		successful_sales
	)

	successful_sales += 1
	daily_revenue += max(amount, 0)

	print(
		"[통계] 구매 후: ",
		successful_sales
	)

	update_shop_stats_ui()
	print_shop_stats()


func record_missed_sale():
	print(
		"[통계] 실패 전: ",
		missed_sales
	)

	missed_sales += 1

	print(
		"[통계] 실패 후: ",
		missed_sales
	)

	update_shop_stats_ui()
	print_shop_stats()


func print_shop_stats():
	print(
		"방문객: ",
		total_visitors,
		" / 구매: ",
		successful_sales,
		" / 판매 실패: ",
		missed_sales,
		" / 보유금: ",
		money,
		"G"
	)

func update_shop_stats_ui():
	if shop_stats_label == null:
		print("ShopStatsLabel을 찾지 못했습니다.")
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

	update_shop_stats_ui()

	print("일일 영업 통계 초기화")

func get_daily_shop_stats() -> Dictionary:
	return {
		"visitors": total_visitors,
		"sales": successful_sales,
		"missed": missed_sales,
		"revenue": daily_revenue
	}

func get_persistent_state() -> Dictionary:
	return {
		"money": money
	}

func apply_persistent_state(
	data: Dictionary
):
	if data.is_empty():
		return

	money = int(
		data.get(
			"money",
			money
		)
	)

	update_money_ui()
	update_shop_stats_ui()

	print(
		"[Player] 상태 복원 / 돈: ",
		money,
		"G"
	)
