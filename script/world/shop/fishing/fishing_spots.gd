class_name FishingSpots
extends Node2D
var points: Dictionary = {}
var models: Dictionary = {}
var terrain: Node2D
var view: Node
var markers: Dictionary = {}
func _ready() -> void:
	terrain = get_parent().get_node("StoreExterior")
	view = get_parent().get_node_or_null("StoreView3D")
	z_index = -5
	call_deferred("build")
func build() -> void:
	var cells: Array = terrain.get_connected_map_cells()
	var used := []
	var anchors := [Vector2i(-2, 9), Vector2i(-5, 6), Vector2i(-7, 3)]
	var index := 0
	for e in FishingData.entries("locations"):
		var id := str(e["id"])
		var target: Vector2i = anchors[index]
		index += 1
		cells.sort_custom(func(a: Vector2i, b: Vector2i): return Vector2(a).distance_squared_to(target) < Vector2(b).distance_squared_to(target))
		for cell: Vector2i in cells:
			if cell.x >= -1 and cell.y >= -1 and cell.x < 18 and cell.y < 16: continue
			var crowded := false
			for previous: Vector2i in used:
				if Vector2(cell).distance_to(previous) < 4: crowded = true
			if crowded: continue
			var point := terrain.to_global(IsometricGrid.project(Vector2(cell), Vector2(terrain.tile_width, terrain.tile_height)))
			var query := PhysicsShapeQueryParameters2D.new()
			var shape := CircleShape2D.new()
			shape.radius = 20
			query.shape = shape
			query.collision_mask = 1
			query.transform = Transform2D(0, point)
			if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
			used.append(cell)
			var target_node := Node2D.new()
			target_node.name = id
			add_child(target_node)
			target_node.global_position = point
			var water_body := StaticBody2D.new()
			add_child(water_body)
			water_body.global_position = point
			var collision := CollisionPolygon2D.new()
			var polygon := PackedVector2Array()
			for offset in [Vector2(0.4,0.4),Vector2(2.4,0.4),Vector2(2.4,2.4),Vector2(0.4,2.4)]:
				polygon.append(IsometricGrid.project(offset,Vector2(terrain.tile_width,terrain.tile_height)))
			collision.polygon = polygon
			collision.disabled = true
			water_body.add_child(collision)
			points[id] = {"cell":cell, "point":point, "node":target_node, "collision":collision}
			var marker := Label.new()
			marker.text = str(e["name"]) + " [E]"
			marker.position = to_local(point) + Vector2(-100, -56)
			marker.size = Vector2(200, 32)
			marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			marker.add_theme_color_override("font_color", Color("e5f8e1"))
			marker.add_theme_color_override("font_outline_color", Color("244337"))
			marker.add_theme_constant_override("outline_size", 4)
			add_child(marker)
			markers[id] = marker
			break
	queue_redraw()
func position_for(id: String) -> Vector2:
	return points.get(id, {}).get("point", Vector2.INF)
func _process(_delta: float) -> void:
	if points.is_empty(): return
	var director = get_parent().get_node_or_null("FishingDirector")
	if director == null: return
	for id in points:
		var accessible := FishingContent.location_available(id, director.hour(), director.weather())
		if points[id]["collision"].disabled == accessible: points[id]["collision"].set_deferred("disabled", not accessible)
		markers[id].visible = accessible and (view == null or not is_instance_valid(view.get("_viewport")))
		if view != null and is_instance_valid(view.get("_viewport")):
			if not models.has(id): _build_model(id)
			models[id].visible = accessible
			var cast = models[id].get_node("Cast")
			cast.visible = director.location == id and director.mode in ["waiting", "bite", "full"]
			models[id].get_node("LocationLabel").visible = not cast.visible
			var float_node = cast.get_node("Float")
			float_node.position.y = 0.08 + sin(Time.get_ticks_msec()*0.005) * (0.045 if director.mode == "bite" else 0.012)
	queue_redraw()
func _draw() -> void:
	if view != null and is_instance_valid(view.get("_viewport")): return
	for id in points:
		if not markers[id].visible: continue
		var p := to_local(position_for(id))
		var diamond := PackedVector2Array([p+Vector2(0,4),p+Vector2(96,52),p+Vector2(0,100),p+Vector2(-96,52)])
		draw_colored_polygon(diamond, Color("34787d"))
		draw_polyline(PackedVector2Array([p+Vector2(-55,45),p+Vector2(-5,63),p+Vector2(40,50)]),Color("73b8af"),3)
func _build_model(id: String) -> void:
	var root := Node3D.new()
	root.name = id
	view.get("_viewport").add_child(root)
	var cell: Vector2i = points[id]["cell"]
	root.position = Vector3(cell.x, 0.03, cell.y)
	var water := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	water.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("377e85")
	material.roughness = 0.4
	water.material_override = material
	water.position = Vector3(1.4, 0, 1.4)
	root.add_child(water)
	for i in range(5):
		var stone := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(0.24, 0.13, 0.32)
		stone.mesh = shape
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("818d7c")
		stone.material_override = mat
		stone.position = Vector3(0.18 + i*0.44, 0.04, 0.28)
		root.add_child(stone)
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
	float_node.position = Vector3(1.3,0.08,1.3)
	cast.add_child(float_node)
	var line := MeshInstance3D.new()
	var thread := CylinderMesh.new()
	thread.top_radius = 0.005
	thread.bottom_radius = 0.005
	var start := Vector3(0.5,1.1,0.2)
	var finish := Vector3(1.3,0.08,1.3)
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
