class_name VillageRoutine
extends RefCounted

static func location(entry: Dictionary, hour: int) -> Dictionary:
	var home := {"path":str(entry["site"]), "label":"머무는 곳"}
	if VillageGatheringFlow.active(hour): return {"path":VillageGatheringFlow.SETTINGS.site_path,"label":"저녁 모임"}
	if hour < 6 or hour >= 18:
		if hour >= 18 and ResidentRequestFlow.done("settle_sora"): return {"path":"VillageDecor/VillageWell", "label":"우물 곁"}
		return home
	if hour >= 12 and ResidentRequestFlow.done("settle_naru"):
		return {"path":"VillageDecor/MarketStall", "label":"노점 주변"}
	return home

# Only existing exterior ground and clear segments belong to the walking graph.
static func route(world: Node2D, start: Vector2, finish: Vector2) -> PackedVector2Array:
	var terrain = world.get_node("StoreExterior")
	var floor_node = world.get_node("Floor")
	var space := world.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = VillageLifeFlow.SETTINGS.resident_radius
	var graph := AStar2D.new()
	var ids: Dictionary = {}
	for cell in terrain.get_connected_map_cells():
		var point: Vector2 = terrain.to_global(terrain.grid_to_local(cell))
		if floor_node.is_cell_inside(floor_node.local_to_grid(floor_node.to_local(point))): continue
		if not clear(space,shape,point): continue
		var id := graph.get_available_point_id()
		ids[cell] = id
		graph.add_point(id,point)
	for cell in ids:
		for offset in [Vector2i.RIGHT,Vector2i.DOWN]:
			var other: Vector2i = cell + offset
			if ids.has(other) and segment_clear(space,shape,graph.get_point_position(ids[cell]),graph.get_point_position(ids[other])):
				graph.connect_points(ids[cell],ids[other])
	var start_id := attachment(graph,space,shape,start)
	var finish_id := attachment(graph,space,shape,finish)
	if start_id < 0 or finish_id < 0: return PackedVector2Array()
	var path := graph.get_point_path(start_id,finish_id)
	if path.is_empty(): return path
	path.append(finish)
	return path

static func clear(space: PhysicsDirectSpaceState2D, shape: Shape2D, point: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform.origin = point
	query.collision_mask = 1
	return space.intersect_shape(query,1).is_empty()

static func segment_clear(space: PhysicsDirectSpaceState2D, shape: Shape2D, start: Vector2, finish: Vector2) -> bool:
	if not clear(space,shape,start) or not clear(space,shape,finish): return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform.origin = start
	query.motion = finish - start
	query.collision_mask = 1
	return space.cast_motion(query)[0] >= 1.0

static func attachment(graph: AStar2D, space: PhysicsDirectSpaceState2D, shape: Shape2D, point: Vector2) -> int:
	var ids := Array(graph.get_point_ids())
	ids.sort_custom(func(a,b): return point.distance_squared_to(graph.get_point_position(a)) < point.distance_squared_to(graph.get_point_position(b)))
	# An endpoint may sit between tile centers, but must not jump across a building.
	for id in ids.slice(0,12):
		if segment_clear(space,shape,point,graph.get_point_position(id)): return id
	return -1
