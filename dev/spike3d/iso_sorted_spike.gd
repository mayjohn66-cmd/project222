extends "res://dev/spike3d/iso_room_spike.gd"
## 시험 방 2: 정렬 순서를 깊이에 넣는 방식(Never's End 식). 같은 방을 "그냥 깊이 버퍼"와 "정렬 순서 깊이"로 그려서 비교한다.
##   O = 정렬 순서 깊이 켜기/끄기(끄면 3D 깊이 버퍼 그대로: 캐릭터 발이 기둥에 파묻힘)
##   방향키 = 캐릭터 이동 / 1·2·3, L, T, P, S, C 는 시험 방 1 과 같음
## 정렬은 우리 IsoSorter(feature/iso-objects)로 구한다. 물체마다 상자(칸 좌표 + 높이 픽셀)를 넣는다.

const SURFACE_SHADER: Shader = preload("res://dev/spike3d/sorted_surface.gdshader")
const SPRITE_SHADER: Shader = preload("res://dev/spike3d/sorted_sprite.gdshader")
const BaseSpike = preload("res://dev/spike3d/iso_room_spike.gd")

var sorted_mode: bool = true
var items: Array = []  # {id, cell, size, blocks, mesh, material}
var sprite_material: ShaderMaterial
var ground_material: ShaderMaterial


func _surface_material(kind: String, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("albedo_tex", BaseSpike.make_texture(kind, _texture_size()))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("texel_per_unit", 1.0)
	return m


func _add_item(id: String, cell: Vector2, size: Vector2, blocks: float, kind: String, tint: Color = Color.WHITE) -> void:
	var material: ShaderMaterial = _surface_material(kind, tint)
	var mesh_inst: MeshInstance3D = _add_box(cell, size, block_height(blocks), material)
	items.append({"id": id, "cell": cell, "size": size, "blocks": blocks, "mesh": mesh_inst, "material": material, "kind": kind})


func _build_world() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(14, 12)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	ground_material = _surface_material(GRASS, Color.WHITE)
	floor_inst.material_override = ground_material
	floor_inst.position = Vector3(5.0, 0.0, 4.0)
	viewport.add_child(floor_inst)

	_add_item("wall", Vector2(0, 0), Vector2(8, 1), 2.0, PAVING)
	_add_item("pillar", Vector2(5, 4), Vector2(1, 1), 3.0, WOOD, Color(0.55, 0.95, 0.65))
	_add_item("plank", Vector2(6, 4), Vector2(3, 1), 1.0, WOOD, Color(0.95, 0.65, 0.75))
	_add_item("crate_a", Vector2(2, 2), Vector2(1, 1), 1.0, WOOD)
	_add_item("crate_b", Vector2(2, 5), Vector2(1, 1), 1.0, WOOD)

	# 캐릭터: 한 장짜리 판. 시트의 첫 칸(64x64)을 쓴다.
	var quad := QuadMesh.new()
	var world_per_px: float = 1.0 / ((TILE_PX / sqrt(2.0)))
	quad.size = Vector2(64.0, 64.0) * world_per_px
	actor_mesh = MeshInstance3D.new()
	actor_mesh.mesh = quad
	sprite_material = ShaderMaterial.new()
	sprite_material.shader = SPRITE_SHADER
	sprite_material.set_shader_parameter("sheet", load(PLAYER_SHEET))
	sprite_material.set_shader_parameter("region", Vector4(0.0, 0.0, 64.0 / 256.0, 64.0 / 320.0))
	actor_mesh.material_override = sprite_material
	viewport.add_child(actor_mesh)
	actor_logic_pos = Vector3(3.6, 0.0, 5.4)

	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 25, 0)
	light.shadow_enabled = true
	light.light_energy = 1.1
	viewport.add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	_update_sorting()


var actor_mesh: MeshInstance3D
var actor_half: float = 0.12  # 캐릭터 정렬 상자의 반 폭(칸). 작을수록 벽에 바짝 붙을 수 있다.


# 캐릭터 판 위치(발끝이 논리 위치). 스냅이 켜져 있으면 화면 픽셀 격자에 맞춘다.
func _update_actor() -> void:
	if actor_mesh == null:
		return

	var foot: Vector3 = snap_to_pixels(actor_logic_pos) if snap else actor_logic_pos
	var half: float = 32.0 * (1.0 / (TILE_PX / sqrt(2.0)))
	actor_mesh.position = foot + Vector3(0.0, half, 0.0)
	_update_sorting()


# IsoSorter 로 순서를 구해 각 물체의 순번(rank)을 셰이더에 넣는다.
func _update_sorting() -> void:
	if items.is_empty() or actor_mesh == null:
		return

	var px_per_unit_z: float = (LOW_TILE_PX / sqrt(2.0)) * cos(deg_to_rad(PITCH_DEG))
	var boxes: Array = []

	for it in items:
		var c: Vector2 = it["cell"]
		var s: Vector2 = it["size"]
		boxes.append({"id": it["id"], "min": Vector3(c.x, c.y, 0.0), "max": Vector3(c.x + s.x, c.y + s.y, it["blocks"] * BLOCK_HEIGHT_LOW_PX)})

	boxes.append({"id": "actor", "min": Vector3(actor_logic_pos.x - actor_half, actor_logic_pos.z - actor_half, 0.0), "max": Vector3(actor_logic_pos.x + actor_half, actor_logic_pos.z + actor_half, 21.0)})
	var result: Dictionary = IsoSorter.sort_items(boxes)
	var rank_of: Dictionary = {}

	for i in range(result["order"].size()):
		rank_of[result["order"][i]] = float(i)

	var count: float = float(boxes.size())

	for it in items:
		var m: ShaderMaterial = it["material"]
		var c2: Vector2 = it["cell"]
		var s2: Vector2 = it["size"]
		m.set_shader_parameter("use_sort", sorted_mode)
		m.set_shader_parameter("rank", rank_of[it["id"]])
		m.set_shader_parameter("rank_count", count)
		m.set_shader_parameter("center_world", Vector3(c2.x + s2.x * 0.5, block_height(it["blocks"]) * 0.5, c2.y + s2.y * 0.5))

	ground_material.set_shader_parameter("use_sort", sorted_mode)
	ground_material.set_shader_parameter("rank", -1.0)
	ground_material.set_shader_parameter("rank_count", count)
	ground_material.set_shader_parameter("center_world", Vector3(5.0, 0.0, 4.0))
	sprite_material.set_shader_parameter("use_sort", sorted_mode)
	sprite_material.set_shader_parameter("rank", rank_of["actor"])
	sprite_material.set_shader_parameter("rank_count", count)
	sprite_material.set_shader_parameter("center_world", actor_mesh.position)


func _apply_shrink() -> void:
	super._apply_shrink()

	for it in items:
		it["material"].set_shader_parameter("albedo_tex", BaseSpike.make_texture(str(it["kind"]), _texture_size()))

	if ground_material != null:
		ground_material.set_shader_parameter("albedo_tex", BaseSpike.make_texture(GRASS, _texture_size()))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		sorted_mode = not sorted_mode
		_update_sorting()
		_update_label()
		return

	super._unhandled_key_input(event)


func _update_label() -> void:
	super._update_label()
	label.text += " / O 정렬 순서 깊이 %s" % ("켬" if sorted_mode else "끔(깊이 버퍼 그대로)")
