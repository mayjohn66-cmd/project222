extends "res://dev/spike3d/iso_sorted_spike.gd"
## 시험 방 3: 실제 매장 한 구석(진열대·계산대·문 2칸 폭)을 새 방식(낮은 해상도 3D + 정렬 순서 깊이 + 윤곽선)으로 그린다.
## 손님은 3등신 상자 캐릭터(머리 크기는 2.5등신과 같고 팔다리만 긺)이고, 걷기는 CrowdSteering(겹침 허용 모드)으로 한다.
##   N = 법선 맵 켜기/끄기 / [ ] = 시간 ∓1시간 / Y = 시간 자동 흐름(하루 16초) / U 윤곽선 / O 정렬 깊이 / K 군중 피하기 / SPACE 손님 추가 / 1·2·3 배율(기본 3배, 칸 36x18)
## 기존 매장 규격: 한 칸 96x48, 진열대는 2x1칸.

# 3등신: 머리는 기존 2.5등신 캐릭터와 같은 크기(0.38칸)로 두고 몸통도 그대로, 팔다리만 늘려서 키 1.14칸(36px 칸 기준 약 25px).
const HEAD_RATIO: float = 3.0
const ACTOR_TOTAL: float = 1.14
const ACTOR_TORSO: float = 0.308
const ACTOR_HEIGHT_PX: float = 25.0  # 정렬 상자 높이(블록 픽셀 단위)
const MAX_CUSTOMERS: int = 9
const SPAWN_EVERY: float = 2.2
const WALK_SPEED: float = 1.6
const ARRIVE: float = 0.22
const BLOCKED_GIVE_UP: float = 5.0
const SPAWN_POINT := Vector2(-1.6, 4.0)
const DOOR_IN := Vector2(1.0, 4.0)
const HUB := Vector2(1.6, 2.2)
const SHELF_STANDS: Array = [Vector2(2.0, 1.3), Vector2(4.5, 1.3), Vector2(7.0, 1.3), Vector2(3.5, 2.2)]
const REGISTER_STAND := Vector2(6.0, 4.0)
const BACK_ROUTE := Vector2(5.5, 5.2)

var actors: Array = []  # {id, node, pos, plan, wait, blocked, speed, static}
var crowd_steering_on: bool = true
var spawn_timer: float = 0.0
var next_id: int = 0
var rng := RandomNumberGenerator.new()
var hour: float = 12.0  # 하루 시간(0~24)
var auto_time: bool = false
var freeze_crowd: bool = false
var sun_light: DirectionalLight3D
var scene_env: Environment
var lamps: Array = []


func _ready() -> void:
	shrink = 3
	tile_px = 108.0  # 3배에서 낮은 해상도 칸 36x18 (2.5배에 가까운 쪽)
	low_tile_px = 36.0
	block_px = 22.0
	toon = true
	cam_target = Vector3(4.0, 0.0, 3.0)
	rng.seed = 7
	super._ready()
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)


func _build_world() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(10.5, 6)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	ground_material = _surface_material(WOOD, Color(0.95, 0.9, 0.85))
	floor_inst.material_override = ground_material
	floor_inst.position = Vector3(3.25, 0.0, 3.0)
	viewport.add_child(floor_inst)
	ground_mesh_node = floor_inst

	# 벽: 뒤쪽(y=0 위) 긴 벽, 왼쪽(x=0 옆) 벽은 문 2칸(y 3~5)을 비운다.
	_add_item("wall_back", Vector2(0, -0.5), Vector2(8, 0.5), 3.0, PAVING)
	_add_item("wall_left_a", Vector2(-0.5, 0), Vector2(0.5, 3), 3.0, PAVING)
	_add_item("wall_left_b", Vector2(-0.5, 5), Vector2(0.5, 1), 3.0, PAVING)
	_add_item("shelf_a", Vector2(1, 0), Vector2(2, 0.6), 1.6, WOOD, Color(0.9, 0.95, 1.0))
	_add_item("shelf_b", Vector2(3.5, 0), Vector2(2, 0.6), 1.6, WOOD, Color(0.9, 0.95, 1.0))
	_add_item("shelf_c", Vector2(6, 0), Vector2(2, 0.6), 1.6, WOOD, Color(0.9, 0.95, 1.0))
	_add_item("table", Vector2(3, 3.1), Vector2(2, 0.9), 0.9, WOOD, Color(1.0, 0.85, 0.7))
	_add_item("counter", Vector2(6.5, 3.5), Vector2(1.5, 1.0), 1.1, WOOD, Color(0.8, 1.0, 0.85))

	light = DirectionalLight3D.new()
	light.shadow_enabled = true
	viewport.add_child(light)
	sun_light = light
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	scene_env = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	# 매장 천장 등(밤에 켜짐): 진열대 앞, 테이블 위, 계산대 위
	for pos in [Vector2(2.2, 2.0), Vector2(5.5, 2.0), Vector2(7.2, 4.0)]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(pos.x, block_height(2.6), pos.y)
		lamp.omni_range = 4.2
		lamp.light_color = Color(1.0, 0.82, 0.5)
		lamp.shadow_enabled = false
		viewport.add_child(lamp)
		lamps.append(lamp)

	_add_actor(Vector2(7.25, 5.0), true)  # 계산대 뒤 점원
	_build_outline_pass()
	apply_time(hour)
	_update_sorting()


func _build_outline_pass() -> void:
	id_viewport = SubViewport.new()
	id_viewport.world_3d = viewport.world_3d
	id_viewport.transparent_bg = false
	id_viewport.msaa_3d = Viewport.MSAA_DISABLED
	id_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	id_viewport.size = viewport.size
	add_child(id_viewport)
	id_camera = Camera3D.new()
	id_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	id_camera.near = camera.near
	id_camera.far = camera.far
	id_camera.cull_mask = 2
	id_viewport.add_child(id_camera)
	camera.cull_mask = 1
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var id_env := WorldEnvironment.new()
	id_env.environment = env
	id_viewport.add_child(id_env)
	_add_id_pair(ground_mesh_node, "ground", false)

	for it in items:
		_add_id_pair(it["mesh"], it["id"], false)

	post_material.shader = OUTLINE_SHADER
	post_material.set_shader_parameter("id_tex", id_viewport.get_texture())


func _add_actor(pos: Vector2, is_static: bool) -> Dictionary:
	var node := BlockyActor.new()
	node.build(viewport, viewport, HEAD_RATIO, ACTOR_TOTAL, ACTOR_TORSO)
	var a: Dictionary = {"id": "p%d" % next_id, "node": node, "pos": pos, "plan": [], "wait": 0.0, "blocked": 0.0, "speed": WALK_SPEED * rng.randf_range(0.85, 1.15), "static": is_static}
	next_id += 1
	actors.append(a)
	return a


func _spawn_customer() -> void:
	var walkers: int = 0

	for a in actors:
		if not a["static"]:
			walkers += 1

	if walkers >= MAX_CUSTOMERS:
		return

	var a: Dictionary = _add_actor(SPAWN_POINT + Vector2(0, rng.randf_range(-0.4, 0.4)), false)
	var stand: Vector2 = SHELF_STANDS[rng.randi() % SHELF_STANDS.size()]
	stand += Vector2(rng.randf_range(-0.25, 0.25), 0.0)
	a["plan"] = [
		{"to": DOOR_IN, "wait": 0.0}, {"to": HUB, "wait": 0.0}, {"to": stand, "wait": rng.randf_range(1.0, 2.4)},
		{"to": Vector2(REGISTER_STAND.x, HUB.y), "wait": 0.0}, {"to": REGISTER_STAND, "wait": rng.randf_range(1.2, 2.0)},
		{"to": BACK_ROUTE, "wait": 0.0}, {"to": DOOR_IN, "wait": 0.0}, {"to": SPAWN_POINT, "wait": 0.0, "leave": true},
	]
	_update_label()


func _step_crowd(delta: float) -> void:
	spawn_timer += delta

	if spawn_timer >= SPAWN_EVERY:
		spawn_timer = 0.0
		_spawn_customer()

	var gone: Array = []

	for a in actors:
		var node: BlockyActor = a["node"]

		if a["static"]:
			node.facing_yaw_deg = 0.0
			node.walking = false
			node.animate(delta)
			continue

		var plan: Array = a["plan"]

		if plan.is_empty():
			gone.append(a)
			continue

		var step: Dictionary = plan[0]
		var pos: Vector2 = a["pos"]
		var to_target: Vector2 = step["to"] - pos

		if a["wait"] > 0.0:
			a["wait"] -= delta
			node.walking = false
			node.animate(delta)

			if a["wait"] <= 0.0:
				plan.pop_front()

			continue

		if to_target.length() <= ARRIVE or a["blocked"] > BLOCKED_GIVE_UP:
			a["blocked"] = 0.0

			if step.get("leave", false):
				gone.append(a)
			elif float(step["wait"]) > 0.0:
				a["wait"] = float(step["wait"])
			else:
				plan.pop_front()

			continue

		var heading: Vector2 = to_target.normalized()
		var move: Vector2 = heading * a["speed"]

		if crowd_steering_on:
			var offsets: Array = []

			for other in actors:
				if other != a:
					offsets.append((other["pos"] as Vector2) - pos)

			var res: Dictionary = CrowdSteering.compute(heading, offsets, true)
			move = heading * a["speed"] * float(res["slow"]) + (res["push"] as Vector2)
			a["blocked"] = (a["blocked"] + delta) if float(res["slow"]) < 0.6 else 0.0

		a["pos"] = pos + move * delta
		node.walking = true
		node.facing_yaw_deg = rad_to_deg(atan2(move.x, move.y))
		node.animate(delta)

	for a in gone:
		(a["node"] as BlockyActor).destroy()
		actors.erase(a)

	if not gone.is_empty():
		_update_label()


# 하루 시간(0~24)에 맞춰 해/달 방향·색·세기, 환경광, 매장 등을 정한다. 낮 6~18시, 5~7시와 17~19시는 서서히 바뀐다.
func apply_time(h: float) -> void:
	hour = fposmod(h, 24.0)
	var day_amt: float = smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(17.0, 19.0, hour))
	var sun_curve: float = clampf(sin((hour - 6.0) / 12.0 * PI), 0.0, 1.0)
	var elev_sun: float = lerpf(10.0, 62.0, sun_curve)
	var yaw_sun: float = lerpf(-75.0, 75.0, clampf((hour - 6.0) / 12.0, 0.0, 1.0))
	var warm: Color = Color(1.0, 0.58, 0.32).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.1, 0.55, sun_curve))
	var sun_energy: float = lerpf(0.8, 1.2, sun_curve)
	var moon_color := Color(0.38, 0.5, 1.0)
	sun_light.rotation_degrees = Vector3(-lerpf(42.0, elev_sun, day_amt), lerpf(-110.0, yaw_sun, day_amt), 0.0)
	sun_light.light_color = moon_color.lerp(warm, day_amt)
	sun_light.light_energy = lerpf(0.4, sun_energy, day_amt)
	sun_light.shadow_enabled = shadows
	scene_env.ambient_light_color = Color(0.12, 0.16, 0.34).lerp(Color(0.7, 0.72, 0.8), day_amt)
	scene_env.ambient_light_energy = lerpf(0.5, 0.55, day_amt)
	scene_env.background_color = Color(0.04, 0.05, 0.1).lerp(Color(0.2, 0.24, 0.32), day_amt)

	for lamp in lamps:
		(lamp as OmniLight3D).light_energy = lerpf(2.2, 0.0, day_amt)
		(lamp as OmniLight3D).visible = day_amt < 0.98


# 질감을 PNG 파일 ↔ 코드로 만든 임시 질감으로 바꾼다.
func set_png_textures(on: bool) -> void:
	use_png_textures = on
	_apply_shrink()


func set_normal_map(on: bool) -> void:
	use_normal_map = on

	for it in items:
		(it["material"] as ShaderMaterial).set_shader_parameter("use_normal", on)

	ground_material.set_shader_parameter("use_normal", on)


func _process(delta: float) -> void:
	if auto_time:
		apply_time(hour + delta * 1.5)  # 1초에 1.5시간(하루 16초)

	if not freeze_crowd:
		_step_crowd(delta)

	super._process(delta)


func _update_actor() -> void:
	for a in actors:
		var p: Vector2 = a["pos"]
		var foot := Vector3(p.x, 0.0, p.y)
		(a["node"] as Node3D).position = snap_to_pixels(foot) if snap else foot
		(a["node"] as Node3D).visible = true

	_update_sorting()


func _update_sorting() -> void:
	if items.is_empty():
		return

	var boxes: Array = []

	for it in items:
		var c: Vector2 = it["cell"]
		var s: Vector2 = it["size"]
		boxes.append({"id": it["id"], "min": Vector3(c.x, c.y, 0.0), "max": Vector3(c.x + s.x, c.y + s.y, it["blocks"] * BLOCK_HEIGHT_LOW_PX)})

	for a in actors:
		var p: Vector2 = a["pos"]
		boxes.append({"id": a["id"], "min": Vector3(p.x - actor_half, p.y - actor_half, 0.0), "max": Vector3(p.x + actor_half, p.y + actor_half, ACTOR_HEIGHT_PX)})

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
	ground_material.set_shader_parameter("center_world", Vector3(4.0, 0.0, 3.0))
	_sync_outline_pass(rank_of, count)

	for a in actors:
		var r: float = rank_of[a["id"]]
		(a["node"] as BlockyActor).sync_sort(r, count, camera, (r + 1.0) / (count + 1.0))


func _apply_shrink() -> void:
	super._apply_shrink()

	if ground_material != null:
		var ground_pair: Dictionary = _texture_pair(WOOD)
		ground_material.set_shader_parameter("albedo_tex", ground_pair["albedo"])
		ground_material.set_shader_parameter("normal_tex", ground_pair["normal"])


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R, KEY_B:
				return
			KEY_G:
				set_png_textures(not use_png_textures)
				_update_label()
				return
			KEY_N:
				set_normal_map(not use_normal_map)
				_update_label()
				return
			KEY_BRACKETLEFT:
				apply_time(hour - 1.0)
				_update_label()
				return
			KEY_BRACKETRIGHT:
				apply_time(hour + 1.0)
				_update_label()
				return
			KEY_Y:
				auto_time = not auto_time
				return
			KEY_K:
				crowd_steering_on = not crowd_steering_on
				_update_label()
				return
			KEY_SPACE:
				_spawn_customer()
				return

	super._unhandled_key_input(event)


func _update_label() -> void:
	label.text = "시간 %02d시 ([ ] 1시간, Y 자동) / N 법선 맵 %s / G PNG 질감 %s / U 윤곽선 %s / O 정렬 깊이 %s / K 군중 피하기 %s / SPACE 손님 (%d명)" % [int(hour), "켬" if use_normal_map else "끔", "켬" if use_png_textures else "끔", "켬" if outline else "끔", "켬" if sorted_mode else "끔", "켬" if crowd_steering_on else "끔", actors.size() - 1]
