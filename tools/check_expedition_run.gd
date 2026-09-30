extends Node

# 원정 한 판을 끝까지 자동으로 진행해서 실행 중 오류(타입 오류 등)를 찾는다.
# 로드 검사(check_godot)로는 잡히지 않는 런타임 오류용이다.
# 실행: godot --headless --path . res://tools/check_expedition_run.tscn
# 지역 4곳(유적 포함) × 난이도 1·2 × 2판을 돌리고, 모든 판이 결과 화면까지 가고 첫 두루마리가 보스에서만 나와야 종료 코드 0이다.
# 오류 메시지는 Godot 로그(SCRIPT ERROR / ERROR)에 출력되니 함께 확인한다.

var report := {
	"runs": 0, "clears": 0, "steps": 0, "stuck": 0, "node_types": {},
	"boss_had_starter": 0, "starter_before_boss": 0
}

func _drain(inst) -> void:
	# 메시지·전리품 창을 사람처럼 넘긴다.
	var guard := 0
	while guard < 60:
		guard += 1
		await get_tree().process_frame
		if inst.message_panel.visible:
			inst.expedition_message_controller.on_continue_pressed()
			continue
		if inst.loot_panel.visible:
			_check_starter_scroll(inst)
			# 전리품은 가방에 넣지 않고 포기하는 것으로 정리한다.
			inst.expedition_bag_controller.finish_loot_organization()
			continue
		break

# 첫 두루마리는 보스를 잡을 때만 나와야 한다(매 판 새 게임 상태로 시작하므로 매 판 검사).
func _check_starter_scroll(inst) -> void:
	var starter: String = RecipeUnlockData.get_starter_scroll_item_id()
	var has_starter := false

	for loot in inst.temporary_loot:
		if str(loot.get("item_id", "")) == starter:
			has_starter = true

	var node: Dictionary = inst.expedition_map.get_node(inst.selected_map_node_id)
	var is_boss: bool = str(node.get("type", "")) == "boss"

	if is_boss and has_starter:
		report["boss_had_starter"] += 1
	elif not is_boss and has_starter:
		report["starter_before_boss"] += 1
		print("[오류] 보스가 아닌 칸에서 첫 두루마리가 나옴: ", node.get("id"))


func _run_once(region: String, difficulty: int) -> void:
	PlayerProgress.reset()
	for lv in range(1, difficulty):
		PlayerProgress.record_clear(region, lv)
	var scene: PackedScene = load("res://scenes/expedition/expedition.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in range(3): await get_tree().process_frame
	var prep = inst.prep_panel
	prep.call("show_departure_choice")
	prep.show()
	# 유적은 보물 지도를 소모해서 들어간다.
	GameState.add_item("treasure_map", 1)
	prep.map_content._select_region(region)
	for i in range(difficulty - 1): prep._step_difficulty(1)
	inst.start_expedition_run()
	await get_tree().process_frame
	report["runs"] += 1
	var steps := 0
	while inst.current_expedition_phase == inst.ExpeditionPhase.RUN and steps < 40:
		steps += 1
		var current: Dictionary = inst.expedition_map.get_node(inst.current_map_node_id) if not inst.current_map_node_id.is_empty() else inst.expedition_map.get_start_node()
		var nexts: Array = current.get("next", [])
		if nexts.is_empty():
			report["stuck"] += 1
			print("[막힘] 다음 노드 없음 현재=", current.get("id"), " 타입=", current.get("type"))
			break
		var pick = nexts[randi() % nexts.size()]
		var node: Dictionary = inst.expedition_map.get_node(str(pick))
		var t := str(node.get("type", ""))
		report["node_types"][t] = int(report["node_types"].get(t, 0)) + 1
		inst.expedition_map_controller.on_node_pressed(str(pick))
		await _drain(inst)
		report["steps"] += 1
		if inst.current_expedition_phase != inst.ExpeditionPhase.RUN:
			break
	if inst.current_expedition_phase == inst.ExpeditionPhase.RESULT:
		report["clears"] += 1
	print("[판] ", region, " 난이도=", difficulty, " 단계=", steps, " phase=", inst.current_expedition_phase, " 사유=", inst.current_end_reason)
	inst.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	seed(12345)
	for region in ["forest", "mine", "swamp", "hidden_ruins"]:
		for difficulty in [1, 2]:
			for n in range(2):
				await _run_once(region, difficulty)
	print("[요약] ", report)
	var ok: bool = (
		int(report["clears"]) == int(report["runs"])
		and int(report["boss_had_starter"]) == int(report["runs"])
		and int(report["starter_before_boss"]) == 0
	)
	get_tree().quit(0 if ok else 1)
