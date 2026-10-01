class_name StoryDirector
extends Node


# 조건이 맞으면 스토리 NPC를 가게 안에 세우고, 플레이어가 말을 걸면 대화와 선물을 처리한다.
# 머리 위 느낌표를 보고 E로 말을 걸면 "느낌표 인물과 대화하면 무언가를 받거나 들을 수 있다"는 것을
# 플레이어가 스스로 알게 하고, 돈이나 재료가 부족해진 때에도 같은 방식으로 간접 개입한다.
# 조건과 선물은 data/story/story_beats.csv에서 정한다.

const CHECK_INTERVAL: float = 1.0
const TALK_DISTANCE: float = 90.0

var actors: Node
var player: Node2D
var world_interactions: Node
var dialogue: StoryDialoguePanel

var active_npc: StoryNpc = null
var talking: bool = false
var elapsed: float = 0.0


func _ready() -> void:
	var world: Node = get_parent()

	actors = world.get_node("Actors")
	player = world.get_node("Actors/Player") as Node2D

	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)


func _process(delta: float) -> void:
	elapsed += delta

	if elapsed < CHECK_INTERVAL:
		return

	elapsed = 0.0

	if talking:
		return

	if is_instance_valid(active_npc):
		if not NpcInterventionSelector.is_available(
			active_npc.beat, get_tree()
		):
			active_npc.leave()
			active_npc = null
		return

	if _is_blocked():
		return

	var beat: Dictionary = _find_available_beat()

	if beat.is_empty():
		return

	_spawn_npc(beat)


func _is_blocked() -> bool:
	var tutorial = get_parent().get_node_or_null("TutorialDirector")
	if tutorial != null and tutorial.is_guiding(): return true
	var requests = get_parent().get_node_or_null("ResidentRequestDirector")
	if requests != null and requests.is_guiding(): return true
	# WorldInteractions는 실행 중에 만들어지므로 그때그때 찾는다.
	if world_interactions == null:
		world_interactions = get_parent().get_node_or_null("WorldInteractions")

	if world_interactions != null and world_interactions.blocked():
		return true

	if player.in_production_room or player.in_warehouse_room:
		return true

	return false


func _find_available_beat() -> Dictionary:
	return NpcInterventionSelector.find_available(get_tree())


func _spawn_npc(beat: Dictionary) -> void:
	var npc := StoryNpc.new()
	npc.setup(beat)
	npc.global_position = _get_npc_position()
	actors.add_child(npc)
	active_npc = npc

	DebugLog.write(
		"[스토리] NPC ", NpcInterventionSelector.kind_of(beat), " 등장: ",
		beat["beat_id"]
	)


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
			return door.get_customer_target_position()

	return player.global_position + Vector2(160, 0)


# 다른 입력 처리보다 먼저 받아서(트리에서 뒤쪽 노드), 가까이 있을 때만 대화로 가져온다.
func _unhandled_input(event: InputEvent) -> void:
	if talking or not is_instance_valid(active_npc):
		return

	if not event.is_action_pressed("interact") or event.is_echo():
		return

	if _is_blocked():
		return

	if player.global_position.distance_to(
		active_npc.global_position
	) > TALK_DISTANCE:
		return

	if not NpcInterventionSelector.is_available(
		active_npc.beat, get_tree()
	):
		active_npc.leave()
		active_npc = null
		return

	get_viewport().set_input_as_handled()
	_start_talk()


func _start_talk() -> void:
	var beat: Dictionary = active_npc.beat
	var npc_data: Dictionary = StoryData.get_npc(
		str(beat["npc_id"])
	)

	talking = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO

	var lines: Array[String] = []
	lines.assign(beat["lines"])

	# 선물은 대화를 시작할 때 지급하고 기록한다(도중에 닫혀도 중복 지급되지 않게).
	var received: Array[String] = _grant_gifts(beat["gifts"])

	PlayerProgress.record_story_beat(
		str(beat["beat_id"]),
		GameState.total_day
	)

	if not received.is_empty():
		lines.append("받은 물건: " + ", ".join(received))

	var portrait: Texture2D = null
	var portrait_path: String = str(npc_data.get("portrait_path", ""))

	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		portrait = load(portrait_path) as Texture2D

	dialogue.start(
		str(npc_data.get("name", "")),
		portrait,
		lines
	)


func _grant_gifts(gifts: Array) -> Array[String]:
	var received: Array[String] = []

	for gift in gifts:
		var gift_type: String = str(gift["type"])
		var gift_id: String = str(gift["id"])
		var amount: int = int(gift["amount"])

		match gift_type:
			"furniture":
				if FurnitureData.get_furniture(gift_id).is_empty():
					push_error("[스토리] 없는 가구 선물: " + gift_id)
					continue

				GameState.add_furniture(gift_id, amount)
				received.append(
					"%s ×%d" % [
						FurnitureData.get_furniture_name(gift_id),
						amount
					]
				)

			"item":
				if not ItemData.has_item(gift_id):
					push_error("[스토리] 없는 아이템 선물: " + gift_id)
					continue

				GameState.add_item(gift_id, amount)
				received.append(
					"%s ×%d" % [
						ItemData.get_item_name(gift_id),
						amount
					]
				)

			"money":
				GameState.add_money(amount)
				received.append("%d G" % amount)

			_:
				push_warning("[스토리] 알 수 없는 선물 종류: " + gift_type)

	return received


func _on_dialogue_finished() -> void:
	talking = false
	player.set_physics_process(true)

	if is_instance_valid(active_npc):
		active_npc.leave()

	active_npc = null
