extends Node
## 기존 편집 가능한 모델/소품 템플릿을 투명 정지 그림으로 내보낸다. 바닥·그림자·새 디자인 없음.
const OUT := "res://docs/그림_작업/받은그림/환경_정지_전환/렌더_원본/"
const UNIT := 1.41421356237 / 64.0
var vp: SubViewport
var camera: Camera3D
var content: Node3D
var rows: Array = []

func _ready() -> void:
	run.call_deferred()

func frames(count: int = 3) -> void:
	for i in count: await get_tree().process_frame

func snapshot(id: String, template: Dictionary, canvas: Vector2i, anchor: Vector2, yaw: float = 0.0) -> void:
	for child in content.get_children(): child.queue_free()
	await frames(1)
	vp.size = canvas
	camera.size = float(canvas.y) * UNIT
	camera.position = camera.basis.z * 40.0
	camera.h_offset = (float(canvas.x) * 0.5 - anchor.x) * UNIT
	camera.v_offset = (anchor.y - float(canvas.y) * 0.5) * UNIT
	var node := MeshInstance3D.new()
	node.mesh = template.mesh
	for i in template.mats.size():
		var mat := (template.mats[i] as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("use_sort", false)
		mat.set_shader_parameter("sway_amp", 0.0)
		mat.set_shader_parameter("emit_strength", 0.0)
		node.set_surface_override_material(i, mat)
	node.rotation.y = yaw
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	content.add_child(node)
	await frames(5)
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	image.save_png(OUT + id + ".png")
	rows.append({"id":id,"canvas":[canvas.x,canvas.y],"anchor":[anchor.x,anchor.y],"pixel_unit":UNIT,"yaw":yaw})
	print("[투명 렌더] ", id, " ", image.get_used_rect())

func prop(style: String, half: Vector2) -> Dictionary:
	var built := VillageAssets.build_prop(style, -half, half, {}, {"ts":24,"block_px":22.0,"unit_px_z":20.0})
	if style == "well":
		# The old sorted preview drew water above a solid stone top; real-depth baking needs its surface above the rim.
		var mesh := ArrayMesh.new()
		for i in built.mesh.get_surface_count():
			var arrays: Array = built.mesh.surface_get_arrays(i)
			if "water" in str(built.specs[i].name):
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for j in vertices.size(): vertices[j].y += 0.04
				arrays[Mesh.ARRAY_VERTEX] = vertices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		built.mesh = mesh
	return {"mesh":built.mesh,"mats":VillageAssets.make_materials(built.specs)}

func run() -> void:
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-30,45,0)
	vp.add_child(camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	var world := WorldEnvironment.new()
	world.environment = environment
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,110,0)
	sun.light_energy = 0.35
	sun.shadow_enabled = false
	vp.add_child(sun)
	content = Node3D.new()
	vp.add_child(content)
	await snapshot("village_well", prop("well",Vector2(0.75,0.75)),Vector2i(128,192),Vector2(64,128))
	for rotation in 2:
		await snapshot("low_wall_%d" % rotation,prop("low_wall",Vector2(2,0.25)),Vector2i(192,192),Vector2(96,128),float(rotation)*PI*0.5)
	var stage := ExpeditionStage3D.new() # Not in scene; only the existing template builders are used.
	var scenery := ExpeditionScenery.new(stage)
	scenery.use_prepared_art = false
	var templates := {}
	templates.f_grass_b = scenery._tpl_grass(Color(0.28,0.58,0.26),Color(0.42,0.74,0.34),"f_grass_b",0.5)
	templates.f_grass = scenery._tpl_grass(Color(0.28,0.58,0.26),Color(0.42,0.74,0.34),"f_grass",0.45)
	for pair in [["f_fl_a",Color(1.0,0.85,0.95)],["f_fl_b",Color(1.0,0.85,0.3)],["f_fl_c",Color(0.85,0.7,1.0)]]:
		templates[pair[0]] = scenery._tpl_flowers(pair[1],pair[0])
	templates.m_stal = scenery._tpl_stalagmite(Color(0.5,0.5,0.58),"m_stal")
	templates.m_crystal = scenery._tpl_crystal(Color(0.35,0.85,0.95),"m_crystal")
	templates.m_rubble = scenery._tpl_pebbles(Color(0.5,0.5,0.58),"m_rubble")
	templates.s_reeds = scenery._tpl_reeds("s_reeds")
	templates.s_grass = scenery._tpl_grass(Color(0.3,0.46,0.26),Color(0.42,0.6,0.34),"s_grass",0.4)
	templates.s_mush = scenery._tpl_mushrooms("s_mush")
	for pair in [["r_rubble_b",false],["r_rubble",false],["r_grass_b",true],["r_grass",true]]:
		templates[pair[0]] = scenery._tpl_grass(Color(0.3,0.5,0.3),Color(0.4,0.62,0.36),pair[0],0.4 if pair[0]=="r_grass_b" else 0.35) if pair[1] else scenery._tpl_pebbles(Color(0.62,0.58,0.7),pair[0])
	for id in templates:
		await snapshot(id,templates[id],Vector2i(64,128),Vector2(32,104))
	for variant in 3:
		for rotation in 4:
			await snapshot("r_wall_%d_rot%d" % [variant,rotation],scenery._tpl_ruin_wall(variant,"r_wall"),Vector2i(128,128),Vector2(64,104),float(rotation)*PI*0.5)
	for variant in 2:
		await snapshot("r_col_%d" % variant,scenery._tpl_column(variant,"r_col"),Vector2i(64,128),Vector2(32,104))
	stage.free()
	var file := FileAccess.open(OUT + "render_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"existing VillageAssets and ExpeditionScenery templates","assets":rows},"  "))
	print("[투명 렌더 완료] ",rows.size())
	get_tree().quit()
