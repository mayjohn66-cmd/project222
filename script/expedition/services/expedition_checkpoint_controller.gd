class_name ExpeditionCheckpointController
extends RefCounted


# 원정 체크포인트(저장 가능 여부 판단, 저장 데이터 생성·기록, 복원)를 담당한다.
# 원정 상태는 host(expedition.gd)가 가지고 있으므로 host를 통해 읽고 쓴다.
# host는 씬 노드라서 타입을 붙이지 않는다.

var host


func setup(new_host) -> void:
	host = new_host


func can_save() -> bool:
	if host.expedition_bag == null:
		return false

	# 원정 준비 화면에서는 저장 가능
	if host.current_expedition_phase == host.ExpeditionPhase.PREP:
		return true

	# 결과 정산 화면에서는 저장하지 않는다.
	if host.current_expedition_phase != host.ExpeditionPhase.RUN:
		return false

	if host.battle_active:
		return false

	if not host.battle_timer.is_stopped():
		return false

	if host.message_panel.visible:
		return false

	if not host.run_message_queue.is_empty():
		return false

	if host.run_message_finish_action.is_valid():
		return false

	if host.loot_panel.visible:
		return false

	if not host.temporary_loot.is_empty():
		return false

	if not host.selected_map_node_id.is_empty():
		return false

	if host.discard_loot_dialog.visible:
		return false

	# 다음 경로를 선택하는 지도 화면에서만 저장 가능
	return host.map_panel.visible


func _get_map_layers_for_save() -> Array:
	var saved_layers: Array = []

	if host.expedition_map == null:
		return saved_layers

	for raw_layer in host.expedition_map.layers:
		if not raw_layer is Array:
			continue

		saved_layers.append(
			raw_layer.duplicate(true)
		)

	return saved_layers


func create_data() -> Dictionary:
	if not can_save():
		return {}

	var saved_region_id: String = (
		host.current_region_id
	)

	if (
		host.current_expedition_phase
		== host.ExpeditionPhase.PREP
		and host.prep_panel.has_method(
			"get_selected_region_id"
		)
	):
		saved_region_id = str(
			host.prep_panel.call(
				"get_selected_region_id"
			)
		)

	return {
		"checkpoint_version": 1,
		"shop_return_context": GameState.get_meta("shop_return_context",{}).duplicate(true),
		"current_day": host.current_day,
		"phase": int(host.current_expedition_phase),
		"region_id": saved_region_id,
		"difficulty": host.get_run_difficulty(),

		"bag_placements": (
			host.expedition_bag.placements.duplicate(true)
		),

		"map_layers": (
			_get_map_layers_for_save()
		),

		"current_map_node_id": (
			host.current_map_node_id
		),

		"visited_map_node_ids": (
			host.visited_map_node_ids.duplicate()
		),

		"combat_player_hp": host.combat_player_hp,
		"combat_player_max_hp": host.combat_player_max_hp,
	}


func save(
	target_path: String = GameState.SAVE_PATH
) -> bool:
	host.save_failure_reason = ""

	if not can_save():
		host.save_failure_reason = (
			"현재 진행을 마친 뒤 저장해주세요."
		)
		return false

	var checkpoint_data: Dictionary = (
		create_data()
	)

	if checkpoint_data.is_empty():
		host.save_failure_reason = (
			"원정 저장 정보를 만들지 못했습니다."
		)
		return false

	# 현재 원정 가방도 공통 저장 데이터에 반영
	GameState.save_expedition_bag(
		host.expedition_bag.placements
	)

	GameState.current_day = host.current_day

	GameState.set_expedition_checkpoint(
		checkpoint_data
	)

	var save_data: Dictionary = (
		GameState.create_save_data()
	)

	var save_result: Dictionary = (
		host.checkpoint_file_service.write_verified_checkpoint(
			save_data,
			target_path
		)
	)

	if not bool(
		save_result.get(
			"success",
			false
		)
	):
		host.save_failure_reason = str(
			save_result.get(
				"message",
				"원정 데이터를 저장하지 못했습니다."
			)
		)
		return false

	return true


func restore() -> bool:
	if not GameState.has_expedition_checkpoint():
		return false

	var checkpoint: Dictionary = (
		GameState.expedition_checkpoint.duplicate(true)
	)

	GameState.set_meta("shop_return_context",checkpoint.get("shop_return_context",{}).duplicate(true))

	var saved_phase: int = int(
		checkpoint.get(
			"phase",
			host.ExpeditionPhase.PREP
		)
	)

	host.current_day = int(
		checkpoint.get(
			"current_day",
			GameState.current_day
		)
	)

	GameState.current_day = host.current_day

	host.current_region_id = str(
		checkpoint.get(
			"region_id",
			GameConfig.DEFAULT_REGION_ID
		)
	)

	var saved_bag: Variant = (
		checkpoint.get(
			"bag_placements",
			[]
		)
	)

	if saved_bag is Array:
		if not host.expedition_bag.load_placements(
			saved_bag
		):
			push_error(
				"[원정 복원] 가방 배치를 복원하지 못했습니다."
			)
			return false

	host.combat_player_max_hp = maxi(
		int(
			checkpoint.get(
				"combat_player_max_hp",
				100
			)
		),
		1
	)

	host.combat_player_hp = clampi(
		int(
			checkpoint.get(
				"combat_player_hp",
				host.combat_player_max_hp
			)
		),
		0,
		host.combat_player_max_hp
	)

	# 준비 화면 저장 복원
	if saved_phase == host.ExpeditionPhase.PREP:
		host.set_expedition_phase(
			host.ExpeditionPhase.PREP
		)

		host.setup_bag_grid_view()
		host.refresh_bag_ui()
		host.update_ui()

		DebugLog.write(
			"[원정 복원] 준비 화면 복원 완료"
		)

		return true

	# 현재는 PREP와 안전한 RUN만 저장한다.
	if saved_phase != host.ExpeditionPhase.RUN:
		push_error(
			"[원정 복원] 지원하지 않는 원정 단계입니다."
		)
		return false

	var saved_layers: Variant = (
		checkpoint.get(
			"map_layers",
			[]
		)
	)

	if (
		not saved_layers is Array
		or saved_layers.is_empty()
	):
		push_error(
			"[원정 복원] 저장된 지도 정보가 없습니다."
		)
		return false

	var restored_map := ExpeditionMap.new()

	restored_map.region_id = host.current_region_id

	restored_map.difficulty = ExpeditionDifficultyData.clamp_level(
		int(
			checkpoint.get(
				"difficulty",
				ExpeditionDifficultyData.MIN_LEVEL
			)
		)
	)
	restored_map.layers.clear()

	for raw_layer in saved_layers:
		if not raw_layer is Array:
			continue

		restored_map.layers.append(
			raw_layer.duplicate(true)
		)

	if restored_map.layers.is_empty():
		push_error(
			"[원정 복원] 지도 층을 복원하지 못했습니다."
		)
		return false

	restored_map.layer_count = (
		restored_map.layers.size()
	)

	host.expedition_map = restored_map

	host.current_map_node_id = str(
		checkpoint.get(
			"current_map_node_id",
			""
		)
	)

	host.selected_map_node_id = ""
	host.visited_map_node_ids.clear()

	var saved_visited_nodes: Variant = (
		checkpoint.get(
			"visited_map_node_ids",
			[]
		)
	)

	if saved_visited_nodes is Array:
		for raw_node_id in saved_visited_nodes:
			host.visited_map_node_ids.append(
				str(raw_node_id)
			)

	if host.current_map_node_id.is_empty():
		push_error(
			"[원정 복원] 현재 지도 위치가 없습니다."
		)
		return false

	host.temporary_loot.clear()
	host.run_message_queue.clear()
	host.run_message_finish_action = Callable()

	host.battle_active = false
	host.battle_timer.stop()

	host.message_panel.visible = false
	host.battle_panel.visible = false
	host.loot_panel.visible = false

	host.apply_bag_equipment_stats()
	host.setup_bag_grid_view()

	host.set_expedition_phase(
		host.ExpeditionPhase.RUN
	)

	host.update_ui()
	host.update_battle_ui()
	host.refresh_bag_ui()
	host.refresh_map_ui()

	DebugLog.write(
		"[원정 복원] 진행 상태 복원 완료"
		+ " / 위치: ",
		host.current_map_node_id
	)

	return true
