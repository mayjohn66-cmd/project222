class_name ExpeditionMapController
extends RefCounted


# 원정 지도 화면의 표시, 노드 선택과 이동 가능 판정, 노드 이벤트 시작, 노드 완료를 담당한다.
# 지도 상태(expedition_map, current_map_node_id 등)는 체크포인트도 쓰므로 host(expedition.gd)가 가지고 있다.
# host는 씬 노드라서 타입을 붙이지 않는다.

var host


func setup(new_host) -> void:
	host = new_host


func print_map():
	DebugLog.write("===== 원정 맵 =====")

	for layer_index in range(
		host.expedition_map.layers.size()
	):
		var layer: Array = (
			host.expedition_map.layers[
				layer_index
			]
		)

		var text: String = (
			"층 "
			+ str(layer_index)
			+ ": "
		)

		for node in layer:
			text += (
				"["
				+ str(node["type"])
				+ " / "
				+ str(node["id"])
				+ "] "
			)

		DebugLog.write(text)

	DebugLog.write("===================")


func get_node_display_name(
	node_type: String
) -> String:
	match node_type:
		ExpeditionMap.NODE_BATTLE:
			return "전투"

		ExpeditionMap.NODE_GATHER:
			return "채집"

		ExpeditionMap.NODE_UNKNOWN:
			return "미지"

		ExpeditionMap.NODE_TREASURE:
			return "보물"

		ExpeditionMap.NODE_BOSS:
			return "보스"

		"start":
			return "시작"

	return "?"


func is_node_reachable(
	node_id: String
) -> bool:
	var current_node: Dictionary = (
		host.expedition_map.get_node(
			host.current_map_node_id
		)
	)

	if current_node.is_empty():
		return false

	var next_nodes: Array = (
		current_node.get(
			"next",
			[]
		)
	)

	return next_nodes.has(
		node_id
	)


func refresh_ui():
	for child in host.map_layers.get_children():
		child.queue_free()

	# 화면에서는 보스가 위쪽,
	# 시작점이 아래쪽에 보이도록 역순 출력
	for layer_index in range(
		host.expedition_map.layers.size() - 1,
		-1,
		-1
	):
		var layer: Array = (
			host.expedition_map.layers[
				layer_index
			]
		)

		var row := HBoxContainer.new()

		row.alignment = (
			BoxContainer.ALIGNMENT_CENTER
		)

		row.add_theme_constant_override(
			"separation",
			25
		)

		host.map_layers.add_child(row)

		for node in layer:
			var node_id: String = str(
				node.get(
					"id",
					""
				)
			)

			var node_type: String = str(
				node.get(
					"type",
					""
				)
			)

			var button := Button.new()

			button.set_meta(
				"map_node_id",
				node_id
			)

			button.custom_minimum_size = Vector2(
				90,
				45
			)

			button.text = (
				get_node_display_name(
					node_type
				)
			)

			# 현재 위치
			if node_id == host.current_map_node_id:
				button.text = (
					"[현재]\n"
					+ button.text
				)

				button.disabled = true

			# 지나간 위치
			elif host.visited_map_node_ids.has(
				node_id
			):
				button.text = (
					"[지남]\n"
					+ button.text
				)

				button.disabled = true

			# 현재 위치에서 이동 가능한 곳
			elif is_node_reachable(
				node_id
			):
				button.disabled = false

				button.pressed.connect(
					on_node_pressed.bind(
						node_id
					)
				)

			# 아직 갈 수 없는 곳
			else:
				button.disabled = true

			row.add_child(button)

		host.map_layers.call_deferred(
			"update_lines",
			host.expedition_map.layers,
			host.visited_map_node_ids
		)


func on_node_pressed(
	node_id: String
):
	if not is_node_reachable(
		node_id
	):
		return

	var node: Dictionary = (
		host.expedition_map.get_node(
			node_id
		)
	)

	if node.is_empty():
		return

	host.selected_map_node_id = node_id

	var node_type: String = str(
		node.get(
			"type",
			""
		)
	)

	DebugLog.write(
		"[원정 맵] 진입: ",
		node_id,
		" / ",
		node_type
	)

	host.map_panel.visible = false

	match node_type:
		ExpeditionMap.NODE_BATTLE, \
		ExpeditionMap.NODE_GATHER, \
		ExpeditionMap.NODE_UNKNOWN, \
		ExpeditionMap.NODE_TREASURE, \
		ExpeditionMap.NODE_BOSS:
			start_event_node(
				node_type
			)

		_:
			push_warning(
				"[원정] 처리되지 않은 노드 타입: "
				+ node_type
			)

			complete_current_node()


func start_event_node(
	node_type: String
) -> void:
	var allow_heal_event: bool = (
		host.combat_player_hp
		< host.combat_player_max_hp
	)

	var event: Dictionary = (
		ExpeditionEventData.get_random_event(
			host.current_region_id,
			node_type,
			GameState.current_day,
			allow_heal_event
		)
	)
	if event.is_empty():
		push_error(
			"[원정] 사용할 이벤트가 없습니다."
			+ " / 지역: "
			+ host.current_region_id
			+ " / 노드: "
			+ node_type
			+ " / 요일: "
			+ str(GameState.current_day)
		)

		complete_current_node()
		return

	DebugLog.write(
		"[원정 이벤트] 선택"
		+ " / 노드: ",
		node_type,
		" / 이벤트: ",
		event.get(
			"event_id",
			""
		)
	)

	host.resolve_expedition_event(
		event
	)


func start_map_battle(
	enemy_id: String = "field_slime"
):
	host.battle_panel.visible = true
	host.loot_panel.visible = false

	host.start_test_battle(
		enemy_id
	)


func complete_current_node():
	if host.selected_map_node_id.is_empty():
		return

	host.current_map_node_id = (
		host.selected_map_node_id
	)

	host.selected_map_node_id = ""

	if not host.visited_map_node_ids.has(
		host.current_map_node_id
	):
		host.visited_map_node_ids.append(
			host.current_map_node_id
		)

	host.battle_panel.visible = false
	host.loot_panel.visible = false
	host.map_panel.visible = true

	refresh_ui()

	DebugLog.write(
		"[원정 맵] 노드 완료: ",
		host.current_map_node_id
	)

	DebugLog.write(
		"[원정 맵] 지나온 경로: ",
		host.visited_map_node_ids
	)

	# =========================
	# 보스 완료 → 원정 결과
	# =========================

	var completed_node: Dictionary = (
		host.expedition_map.get_node(
			host.current_map_node_id
		)
	)

	if not completed_node.is_empty():
		var completed_node_type: String = str(
			completed_node.get(
				"type",
				""
			)
		)

		if completed_node_type == ExpeditionMap.NODE_BOSS:
			DebugLog.write(
				"[원정] 보스 완료 → RESULT"
			)

			# 클리어한 난이도를 기록해서 다음 난이도를 연다.
			PlayerProgress.record_clear(
				host.current_region_id,
				host.get_run_difficulty()
			)

			host.open_result_phase(
				host.ExpeditionEndReason.BOSS_CLEAR
			)
			return
