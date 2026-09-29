extends RefCounted


func prepare_departure(
	region_id: String,
	current_day: int
) -> Dictionary:
	if region_id.is_empty():
		return _failure(
			"출발할 지역을 선택해주세요.",
			"[원정 출발] 지역 ID가 비어 있습니다."
		)

	if not ExpeditionMapData.has_valid_region_nodes(
		region_id
	):
		return _failure(
			"지역 정보를 불러올 수 없어 출발하지 못했습니다.",
			(
				"[원정 출발] 지역의 맵 노드 설정을 확인하세요: "
				+ region_id
			)
		)

	var required_node_types: Array[String] = (
		ExpeditionMapData.get_required_event_node_types(
			region_id
		)
	)

	var missing_node_types: Array[String] = (
		ExpeditionEventData.get_missing_event_node_types(
			region_id,
			required_node_types,
			current_day
		)
	)

	if not missing_node_types.is_empty():
		return _failure(
			"지역 이벤트를 불러올 수 없어 출발하지 못했습니다.",
			(
				"[원정 출발] 선택 가능한 이벤트 없음"
				+ " / 지역: "
				+ region_id
				+ " / 요일: "
				+ str(current_day)
				+ " / 노드: "
				+ ", ".join(missing_node_types)
			)
		)

	var invalid_event_ids: Array[String] = (
		ExpeditionEventData.get_invalid_region_event_ids(
			region_id,
			required_node_types,
			current_day
		)
	)

	if not invalid_event_ids.is_empty():
		return _failure(
			"지역 이벤트 설정에 오류가 있어 출발하지 못했습니다.",
			(
				"[원정 출발] 잘못된 이벤트 설정"
				+ " / 지역: "
				+ region_id
				+ " / 이벤트: "
				+ ", ".join(invalid_event_ids)
			)
		)

	# 입장 아이템 보유 여부만 먼저 검사
	if not ExpeditionMapData.can_enter_region(
		region_id
	):
		return _failure(
			"출발할 수 없습니다. 지역 입장 조건을 확인해주세요.",
			(
				"[원정 출발] 입장 아이템 부족 / 지역: "
				+ region_id
			)
		)

	# 비용을 소비하기 전에 맵을 완성한다.
	var prepared_map := ExpeditionMap.new()

	prepared_map.set_region(
		region_id
	)

	prepared_map.generate()

	var start_node: Dictionary = (
		prepared_map.get_start_node()
	)

	var start_node_id: String = str(
		start_node.get(
			"id",
			""
		)
	)

	if start_node_id.is_empty():
		return _failure(
			"원정 지도를 생성하지 못했습니다.",
			(
				"[원정 출발] 시작 노드 생성 실패 / 지역: "
				+ region_id
			)
		)

	# 모든 검사와 맵 생성이 성공한 뒤 비용을 소비한다.
	if not ExpeditionMapData.try_pay_entry_cost(
		region_id
	):
		return _failure(
			"입장 아이템을 사용하지 못했습니다.",
			(
				"[원정 출발] 입장 비용 처리 실패 / 지역: "
				+ region_id
			)
		)

	return {
		"success": true,
		"message": "",
		"debug_message": "",
		"map": prepared_map,
		"start_node_id": start_node_id
	}


func _failure(
	message: String,
	debug_message: String
) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"debug_message": debug_message,
		"map": null,
		"start_node_id": ""
	}
