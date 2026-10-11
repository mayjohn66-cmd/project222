class_name FishingSpots
extends Node2D
const LAYOUT_FILE := "res://data/fishing/fishing_tile_layouts.json"
var points: Dictionary = {}
var models: Dictionary = {}
var terrain: Node2D
var view: Node
var markers: Dictionary = {}
var tile_keys: Dictionary = {}
var retry := 0.0
func _ready() -> void:
	terrain = get_parent().get_node("StoreExterior")
	view = get_parent().get_node_or_null("StoreView3D")
	z_index = -5
	call_deferred("_build_after_environment")
func _build_after_environment() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	build()
func _world(cell: Vector2) -> Vector2:
	return terrain.to_global(IsometricGrid.project(cell, Vector2(terrain.tile_width, terrain.tile_height)))
func build() -> void:
	if points.size() == 3 or terrain.is_wild(): return
	var layouts: Array = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))["locations"]
	var available: Array = terrain.get_connected_map_cells()
	var available_set := {}
	for cell in available: available_set[cell] = true
	var reserved := {}
	for existing in points.values():
		for group in existing["groups"].values():
			for cell in group:
				for offset in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: reserved[cell+offset] = true
	var anchors := [Vector2i(-8,9),Vector2i(-10,0),Vector2i(-2,-10)]
	for index in layouts.size():
		var layout: Dictionary = layouts[index]
		if points.has(str(layout["id"])): continue
		var stand := Vector2i(layout["stand_cell"][0],layout["stand_cell"][1])
		var anchor: Vector2i = anchors[index]
		available.sort_custom(func(a: Vector2i,b: Vector2i):
			var da := Vector2(a).distance_squared_to(anchor)
			var db := Vector2(b).distance_squared_to(anchor)
			return da < db if da != db else (a.x < b.x if a.x != b.x else a.y < b.y))
		for candidate: Vector2i in available:
			var origin := candidate - stand
			var occupied := {}
			for entry in layout["cells"]:
				var cell := origin + Vector2i(entry["cell"][0],entry["cell"][1])
				occupied[cell] = true
			var valid := true
			for cell: Vector2i in occupied:
				if not available_set.has(cell) or reserved.has(cell) or (cell.x >= -1 and cell.y >= -1 and cell.x < 18 and cell.y < 16):
					valid = false
					break
				if terrain._is_route_road(cell) or terrain._is_road_cell(cell) or terrain._is_sidewalk_cell(cell) or terrain._is_village_courtyard(cell):
					valid = false
					break
				var query := PhysicsShapeQueryParameters2D.new()
				var shape := CircleShape2D.new()
				shape.radius = 24
				query.shape = shape
				query.collision_mask = 1
				query.transform = Transform2D(0, _world(Vector2(cell)))
				if not get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():
					valid = false
					break
			if not valid: continue
			var id := str(layout["id"])
			var groups := {}
			var collisions: Array = []
			var body := StaticBody2D.new()
			add_child(body)
			for entry in layout["cells"]:
				var cell := origin + Vector2i(entry["cell"][0],entry["cell"][1])
				var tile := str(entry["tile"])
				if not groups.has(tile): groups[tile] = []
				groups[tile].append(cell)
				if not entry["dock"]:
					# Shore art has a land strip; clip water to its blue area.
					for rect: Rect2 in water_regions(tile):
						var collision := CollisionPolygon2D.new()
						var polygon := PackedVector2Array()
						for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
							polygon.append(_world(Vector2(cell)+corner-Vector2(0.5,0.5)))
						collision.polygon = polygon
						collision.disabled = true
						body.add_child(collision)
						collisions.append(collision)
				for offset in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: reserved[cell+offset] = true
			var float_cell := origin + Vector2i(layout["float_cell"][0],layout["float_cell"][1])
			var dry: Array = []
			for cell: Vector2i in available:
				if not occupied.has(cell): dry.append(cell)
			dry.sort_custom(func(a: Vector2i,b: Vector2i): return Vector2(a).distance_squared_to(candidate) < Vector2(b).distance_squared_to(candidate))
			var visitor := Vector2.INF
			var visitor_spawn := Vector2.INF
			for cell: Vector2i in dry:
				var query := PhysicsPointQueryParameters2D.new()
				query.position = _world(Vector2(cell))
				query.collision_mask = 1
				if get_world_2d().direct_space_state.intersect_point(query,1).is_empty():
					if visitor == Vector2.INF:
						visitor = query.position
					elif query.position.distance_to(visitor) > 40.0:
						visitor_spawn = query.position
						break
			points[id] = {"cell":candidate,"point":_world(Vector2(candidate)),"float_cell":float_cell,"groups":groups,"collisions":collisions,"visitor":visitor,"visitor_spawn":visitor_spawn}
			var marker := Label.new()
			marker.text = str(FishingData.entry(id)["name"]) + " [E]"
			marker.position = to_local(position_for(id)) + Vector2(-100,-56)
			marker.size = Vector2(200,32)
			marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(marker)
			markers[id] = marker
			break
	queue_redraw()
static func water_regions(tile: String) -> Array:
	var edges: Array = tile.trim_prefix("shore_").trim_prefix("corner_").split("_") if tile.begins_with("shore_") else []
	var lo := Vector2.ZERO
	var hi := Vector2.ONE
	if tile.begins_with("shore_corner_"):
		var regions: Array = []
		for edge in edges:
			var a := Vector2.ZERO
			var b := Vector2.ONE
			if edge == "nx": a.x = 0.3
			if edge == "ny": a.y = 0.3
			if edge == "px": b.x = 0.7
			if edge == "py": b.y = 0.7
			regions.append(Rect2(a,b-a))
		return regions
	for edge in edges:
		if edge == "nx": lo.x = 0.3
		if edge == "ny": lo.y = 0.3
		if edge == "px": hi.x = 0.7
		if edge == "py": hi.y = 0.7
	return [Rect2(lo,hi-lo)]
func position_for(id: String) -> Vector2:
	return points.get(id,{}).get("point",Vector2.INF)
func visitor_position_for(id: String) -> Vector2:
	return points.get(id,{}).get("visitor",Vector2.INF)
func visitor_spawn_for(id: String) -> Vector2:
	return points.get(id,{}).get("visitor_spawn",Vector2.INF)
func facing_for(id: String) -> Vector2:
	if not points.has(id): return Vector2.DOWN
	return (_world(Vector2(points[id]["float_cell"]))-position_for(id)).normalized()
func can_cast_from(position: Vector2,id: String) -> bool:
	return points.has(id) and position.distance_to(position_for(id)) < 26.0
func _process(delta: float) -> void:
	if points.size() < 3:
		retry += delta
		if retry >= 1.0: retry = 0.0; build()
	if points.is_empty(): return
	var director = get_parent().get_node_or_null("FishingDirector")
	if director == null: return
	for id in points:
		var accessible := FishingContent.location_available(id,director.hour(),director.weather())
		for collision in points[id]["collisions"]:
			if collision.disabled == accessible: collision.set_deferred("disabled",not accessible)
		markers[id].visible = accessible and (view == null or not is_instance_valid(view.get("_viewport")))
		if view != null and is_instance_valid(view.get("_viewport")):
			if not models.has(id):
				_build_model(id)
				tile_keys[id] = []
				for tile in points[id]["groups"]:
					var key := "fishing:%s:%s:%s" % [get_instance_id(),id,tile]
					FishingTileArt.install(view,key,points[id]["groups"][tile],tile)
					tile_keys[id].append(key)
			models[id].visible = accessible
			for key in tile_keys[id]:
				if view._items.has(key): view._items[key]["mesh"].visible = accessible
			var cast = models[id].get_node("Cast")
			cast.visible = director.location == id and director.mode in ["waiting","bite","full"]
			models[id].get_node("LocationLabel").visible = not cast.visible
	queue_redraw()
func _draw() -> void:
	if view != null and is_instance_valid(view.get("_viewport")): return
	for id in points:
		if not markers[id].visible: continue
		for tile in points[id]["groups"]:
			var texture := ReceivedWorldArt.texture(FishingTileArt.path(tile))
			if texture == null: continue
			for cell in points[id]["groups"][tile]:
				draw_texture_rect(texture,Rect2(to_local(_world(Vector2(cell)))-Vector2(48,24),Vector2(96,48)),false)
func _build_model(id: String) -> void:
	var root := Node3D.new()
	root.name = id
	view.get("_viewport").add_child(root)
	var cell: Vector2i = points[id]["cell"]
	root.position = Vector3(cell.x, 0.03, cell.y)
	var label := Label3D.new()
	label.name = "LocationLabel"
	label.text = str(FishingData.entry(id)["name"]) + " [E]"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.005
	label.position = Vector3(0, 1, 0)
	label.outline_size = 6
	root.add_child(label)

	var cast := Node3D.new()
	cast.name = "Cast"
	root.add_child(cast)
	var rod := MeshInstance3D.new()
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.012
	rod_mesh.bottom_radius = 0.025
	rod_mesh.height = 1.3
	rod.mesh = rod_mesh
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("a88957")
	rod.material_override = wood
	rod.position = Vector3(0.2, 0.6, 0.2)
	rod.rotation_degrees.z = -32
	var direction: Vector2 = Vector2(points[id]["float_cell"] - cell).normalized()
	rod.rotation.y = -atan2(direction.y, direction.x)
	cast.add_child(rod)
	var float_node := MeshInstance3D.new()
	float_node.name = "Float"
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	float_node.mesh = sphere
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("f36555")
	float_node.material_override = red
	float_node.position = Vector3(points[id]["float_cell"].x-cell.x,0.08,points[id]["float_cell"].y-cell.y)
	cast.add_child(float_node)
	var line := MeshInstance3D.new()
	var thread := CylinderMesh.new()
	thread.top_radius = 0.005
	thread.bottom_radius = 0.005
	var start := Vector3(0.5,1.1,0.2)
	var finish := Vector3(points[id]["float_cell"].x-cell.x,0.08,points[id]["float_cell"].y-cell.y)
	thread.height = start.distance_to(finish)
	line.mesh = thread
	line.position = (start+finish)*0.5
	line.quaternion = Quaternion(Vector3.UP,(finish-start).normalized())
	cast.add_child(line)
	cast.hide()
	models[id] = root
func _exit_tree() -> void:
	for model in models.values():
		if is_instance_valid(model): model.queue_free()
	if is_instance_valid(view):
		for keys in tile_keys.values():
			for key in keys: view._remove_item(key)
