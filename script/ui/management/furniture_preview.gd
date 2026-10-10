class_name FurniturePreview
extends SubViewportContainer
## 제작 설명과 함께 실제 배치에 사용하는 3D 모델을 보여 준다.

var viewport: SubViewport
var camera: Camera3D
var received_preview: ReceivedFurniturePreview
var display: MeshInstance3D

func _ready() -> void:
	custom_minimum_size = Vector2(0, 160)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(420, 160)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-25, 45, 0)
	viewport.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 120, 0)
	viewport.add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.93, 0.87, 0.74)  # 양피지 쪽에 놓이므로 종이색 바탕
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	display = MeshInstance3D.new()
	viewport.add_child(display)
	received_preview = ReceivedFurniturePreview.new()
	add_child(received_preview)
	received_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_furniture(id: String) -> void:
	var data := BuildObjectData.get_build_object(id)
	visible = not data.is_empty() and (FurnitureAssets.has_model(id) or not ShelfData.get_shelf_data(id).is_empty())
	if not visible: return
	display.visible = not received_preview.show_shape(id)
	var size: Vector2i = data["grid_size"]
	var row := Furniture3DData.get_row(id)
	var lo := Vector2.ZERO
	var hi := Vector2(size.x, float(row["depth_ratio"]))
	var params := VillageAssets.default_params()
	params["furniture_stage"] = FurnitureObjectCatalog.get_object(id).get("stage", "")
	var built: Dictionary
	if str(row["kind"]) == "shelf":
		built = ShelfAssets.build(lo, hi, 0, 1, [], ShelfData.get_slots_per_level(id), params)
	else:
		built = FurnitureAssets.build(id, lo, hi, 0, params)
	display.mesh = built["mesh"]
	var materials := VillageAssets.make_materials(built["specs"])
	for i in range(materials.size()): display.set_surface_override_material(i, materials[i])
	camera.size = maxf(2.6, float(size.x) * 1.2)
	camera.position = Vector3(float(size.x) * 0.5, float(built["total_blocks"]) * 0.5, hi.y * 0.5) + camera.basis.z * 8.0
