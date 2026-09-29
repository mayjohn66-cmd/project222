extends VBoxContainer


var layers_data: Array = []
var visited_ids: Array = []


func update_lines(
	new_layers: Array,
	new_visited_ids: Array
):
	layers_data = new_layers
	visited_ids = new_visited_ids.duplicate()

	queue_redraw()


func _draw():
	if layers_data.is_empty():
		return

	var node_positions: Dictionary = {}

	# =========================
	# 각 버튼의 중심 위치 저장
	# =========================

	for row in get_children():
		if not row is HBoxContainer:
			continue

		for child in row.get_children():
			if not child is Button:
				continue

			if not child.has_meta(
				"map_node_id"
			):
				continue

			var node_id: String = str(
				child.get_meta(
					"map_node_id"
				)
			)

			var global_center: Vector2 = (
				child.get_global_rect().get_center()
			)

			var local_center: Vector2 = (
				get_global_transform()
				.affine_inverse()
				* global_center
			)

			node_positions[node_id] = local_center

	# =========================
	# 연결선 그리기
	# =========================

	for layer in layers_data:
		for node in layer:
			var from_id: String = str(
				node.get(
					"id",
					""
				)
			)

			if not node_positions.has(from_id):
				continue

			var next_nodes: Array = node.get(
				"next",
				[]
			)

			for raw_next_id in next_nodes:
				var to_id: String = str(
					raw_next_id
				)

				if not node_positions.has(to_id):
					continue

				var from_position: Vector2 = (
					node_positions[from_id]
				)

				var to_position: Vector2 = (
					node_positions[to_id]
				)

				var passed: bool = (
					is_passed_connection(
						from_id,
						to_id
					)
				)

				if passed:
					draw_line(
						from_position,
						to_position,
						Color(
							0.95,
							0.8,
							0.25
						),
						4.0
					)

				else:
					draw_line(
						from_position,
						to_position,
						Color(
							0.35,
							0.35,
							0.35
						),
						2.0
					)


func is_passed_connection(
	from_id: String,
	to_id: String
) -> bool:
	if visited_ids.size() < 2:
		return false

	for index in range(
		visited_ids.size() - 1
	):
		if (
			str(visited_ids[index])
			== from_id
			and
			str(visited_ids[index + 1])
			== to_id
		):
			return true

	return false
