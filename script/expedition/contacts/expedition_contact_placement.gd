class_name ExpeditionContactPlacement
extends RefCounted

static func grid(room: ExpeditionRoomModel) -> AStarGrid2D:
	var walk := AStarGrid2D.new()
	walk.region = Rect2i(0,0,33,33)
	walk.cell_size = Vector2.ONE * 0.25
	walk.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	walk.update()
	for y in range(33):
		for x in range(33):
			var point := Vector2(x,y) * 0.25
			var radius := room.settings.actor_radius + 0.04
			var solid := point.x < radius or point.y < radius or point.x > 8-radius or point.y > 8-radius
			for obstacle in room.obstacles:
				if obstacle.grow(radius).has_point(point): solid = true
			walk.set_point_solid(Vector2i(x,y),solid)
	return walk

static func choose(room: ExpeditionRoomModel) -> Vector2:
	var walk := grid(room)
	var origin := Vector2i(roundi(room.player_position.x * 4),roundi(room.player_position.y * 4))
	if not walk.region.has_point(origin) or walk.is_point_solid(origin): return Vector2.INF
	var candidates: Array[Vector2i] = []
	for y in range(4,27,2):
		for x in range(4,29,2):
			var cell := Vector2i(x,y)
			var point := Vector2(cell) * 0.25
			if walk.is_point_solid(cell) or point.distance_to(room.player_position) < ExpeditionContactFlow.SETTINGS.room_separation: continue
			if point.distance_to(room.exit_position) < ExpeditionContactFlow.SETTINGS.room_separation: continue
			if not room.object_kind.is_empty() and point.distance_to(room.object_position) < ExpeditionContactFlow.SETTINGS.room_separation: continue
			candidates.append(cell)
	candidates.shuffle()
	for cell in candidates:
		if not walk.get_id_path(origin,cell).is_empty(): return Vector2(cell) * 0.25
	return Vector2.INF
