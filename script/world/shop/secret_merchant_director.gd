class_name SecretMerchantDirector
extends Node


# 심야에 낮은 확률로 비밀 상인을 가게 안에 세우고, 플레이어가 말을 걸면 판매 창을 연다.
# - 심야(0~6시)가 시작될 때 GameConfig.SECRET_MERCHANT_NIGHT_CHANCE 확률로 나타나 06:00에 떠난다.
# - 첫 원정을 다녀온 뒤부터 나올 수 있다(초반 혼란 방지).
# - 판매 목록은 data/shop/catalogs/secret_merchant.csv, 방문할 때마다 진열이 새로 정해진다.

const TALK_DISTANCE: float = 90.0

var day_manager: Node
var actors: Node
var player: Node2D
var world_interactions: Node
var panel: SecretMerchantPanel

var active_npc: MerchantNpc = null
var shopping: bool = false


func _ready() -> void:
	var world: Node = get_parent()

	day_manager = world.get_node("DayManager")
	actors = world.get_node("Actors")
	player = world.get_node("Actors/Player") as Node2D

	panel = SecretMerchantPanel.new()
	add_child(panel)
	panel.closed.connect(_on_panel_closed)

	day_manager.hour_changed.connect(_on_hour_changed)


func _on_hour_changed(
	hour: int
) -> void:
	if hour == GameConfig.DAY_START_HOUR:
		_dismiss_merchant()
		return

	if hour != GameConfig.NIGHT_PERIOD_START_HOUR:
		return

	if is_instance_valid(active_npc):
		return

	if not PlayerProgress.has_completed_expedition():
		return

	if randf() >= GameConfig.SECRET_MERCHANT_NIGHT_CHANCE:
		return

	spawn_merchant()


# 확률과 상관없이 상인을 세운다(시험용으로도 쓴다). 이미 있으면 아무것도 하지 않는다.
func spawn_merchant() -> void:
	if is_instance_valid(active_npc):
		return

	var offers: Array[Dictionary] = SecretMerchantData.roll_offers()

	if offers.is_empty():
		return

	var npc := MerchantNpc.new()
	npc.setup(offers)
	npc.global_position = _get_npc_position()
	actors.add_child(npc)
	active_npc = npc

	DebugLog.write(
		"[비밀 상인] 등장 / 진열 ",
		offers.size(),
		"종"
	)


func _dismiss_merchant() -> void:
	if not is_instance_valid(active_npc):
		return

	if shopping:
		panel.close()

	active_npc.leave()
	active_npc = null


# 손님이 가게 안에서 처음 서는 자리(출입문 안쪽)에 세운다.
func _get_npc_position() -> Vector2:
	for door in get_tree().get_nodes_in_group("door"):
		if not is_instance_valid(door) or door.is_queued_for_deletion():
			continue

		if door.get_meta("is_build_preview", false):
			continue

		if door.get_parent() != get_parent().get_node_or_null("Objects"):
			continue

		if door.has_method("get_customer_target_position"):
			return door.get_customer_target_position() + Vector2(60, 0)

	return player.global_position + Vector2(-160, 0)


func _is_blocked() -> bool:
	# WorldInteractions는 실행 중에 만들어지므로 그때그때 찾는다.
	if world_interactions == null:
		world_interactions = get_parent().get_node_or_null("WorldInteractions")

	if world_interactions != null and world_interactions.blocked():
		return true

	if player.in_production_room or player.in_warehouse_room:
		return true

	return false


func _unhandled_input(event: InputEvent) -> void:
	if shopping or not is_instance_valid(active_npc):
		return

	if not event.is_action_pressed("interact") or event.is_echo():
		return

	if _is_blocked():
		return

	if player.global_position.distance_to(
		active_npc.global_position
	) > TALK_DISTANCE:
		return

	get_viewport().set_input_as_handled()
	_start_shopping()


func _start_shopping() -> void:
	shopping = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	panel.start(active_npc.offers)


func _on_panel_closed() -> void:
	shopping = false
	player.set_physics_process(true)
