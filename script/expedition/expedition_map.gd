class_name ExpeditionMap
extends RefCounted

const MAP_DATA = preload(
	"res://script/data/expedition/expedition_map_data.gd"
)


const NODE_BATTLE: String = "battle"
const NODE_GATHER: String = "gather"
const NODE_UNKNOWN: String = "unknown"
const NODE_TREASURE: String = "treasure"
const NODE_BOSS: String = "boss"


var layer_count: int = 6

# 난이도 레벨(1~). 방 개수는 generate()에서 난이도 CSV로 정한다.
var difficulty: int = ExpeditionDifficultyData.MIN_LEVEL
var width: int = 3
var layers: Array = []


var region_id: String = GameConfig.DEFAULT_REGION_ID




func generate():
	layers.clear()

	difficulty = ExpeditionDifficultyData.clamp_level(
		difficulty
	)

	# 시작 지점 층 + 방 개수(보스 방 포함)
	layer_count = (
		ExpeditionDifficultyData.get_room_count(
			difficulty
		)
		+ 1
	)

	# 시작 지점
	layers.append(
		[
			create_node(
				0,
				0,
				"start"
			)
		]
	)

	# 중간 경로
	for layer_index in range(
		1,
		layer_count - 1
	):
		var layer: Array = []

		for column in range(width):
			var node_type: String = (
				get_random_node_type()
			)

			layer.append(
				create_node(
					layer_index,
					column,
					node_type
				)
			)

		layers.append(layer)

	# 최종 목적지는 동일
	layers.append(
		[
			create_node(
				layer_count - 1,
				0,
				NODE_BOSS
			)
		]
	)

	create_connections()


func create_node(
	layer: int,
	column: int,
	node_type: String
) -> Dictionary:
	return {
		"id": (
			str(layer)
			+ "_"
			+ str(column)
		),
		"layer": layer,
		"column": column,
		"type": node_type,
		"next": []
	}


func get_random_node_type() -> String:
	var node_type: String = (
		MAP_DATA.get_random_node_type(
			region_id
		)
	)

	match node_type:
		NODE_BATTLE:
			return NODE_BATTLE

		NODE_GATHER:
			return NODE_GATHER

		NODE_UNKNOWN:
			return NODE_UNKNOWN

		NODE_TREASURE:
			return NODE_TREASURE

		_:
			push_warning(
				"[ExpeditionMap] 알 수 없는 노드 타입: "
				+ node_type
			)

			return NODE_BATTLE


func create_connections():
	for layer_index in range(
		layers.size() - 1
	):
		var current_layer: Array = (
			layers[layer_index]
		)

		var next_layer: Array = (
			layers[layer_index + 1]
		)

		# 기존 연결 초기화
		for node in current_layer:
			node["next"] = []

		# =========================
		# 시작점 → 첫 층
		# =========================

		if current_layer.size() == 1:
			for next_node in next_layer:
				current_layer[0]["next"].append(
					next_node["id"]
				)

			continue

		# =========================
		# 마지막 층 → 보스
		# =========================

		if next_layer.size() == 1:
			for node in current_layer:
				node["next"].append(
					next_layer[0]["id"]
				)

			continue

		# =========================
		# 일반 층
		# =========================

		for node in current_layer:
			var column: int = int(
				node["column"]
			)

			var possible_columns: Array[int] = []

			for target_column in [
				column - 1,
				column,
				column + 1
			]:
				if target_column < 0:
					continue

				if target_column >= next_layer.size():
					continue

				possible_columns.append(
					target_column
				)

			# 기본 경로 1개
			var primary_column: int = (
				possible_columns.pick_random()
			)

			node["next"].append(
				next_layer[primary_column]["id"]
			)

			# 30% 확률로 추가 분기 1개
			if (
				randf() < 0.30
				and possible_columns.size() >= 2
			):
				var extra_columns: Array[int] = (
					possible_columns.duplicate()
				)

				extra_columns.erase(
					primary_column
				)

				var extra_column: int = (
					extra_columns.pick_random()
				)

				node["next"].append(
					next_layer[extra_column]["id"]
				)

		# =========================
		# 고립된 다음 노드 방지
		# =========================

		for next_node in next_layer:
			var next_id: String = str(
				next_node["id"]
			)

			var has_incoming := false

			for node in current_layer:
				if node["next"].has(
					next_id
				):
					has_incoming = true
					break

			if has_incoming:
				continue

			# 해당 노드와 가장 가까운
			# 이전 층 노드에서 하나 연결
			var target_column: int = int(
				next_node["column"]
			)

			var closest_node: Dictionary = {}
			var closest_distance := 999

			for node in current_layer:
				var distance: int = abs(
					int(node["column"])
					- target_column
				)

				if distance < closest_distance:
					closest_distance = distance
					closest_node = node

			if not closest_node.is_empty():
				closest_node["next"].append(
					next_id
				)


func get_node(
	node_id: String
) -> Dictionary:
	for layer in layers:
		for node in layer:
			if str(node["id"]) == node_id:
				return node

	return {}


func get_start_node() -> Dictionary:
	if layers.is_empty():
		return {}

	return layers[0][0]

func set_region(
	new_region_id: String
) -> void:
	region_id = new_region_id
