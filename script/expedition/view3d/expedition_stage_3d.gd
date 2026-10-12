class_name ExpeditionStage3D
extends SubViewportContainer
## 원정 던전 방(8×8)의 도트 그림과 조명을 표시하는 무대. ExpeditionRoomView 뒤에 깔리고 방 모델을 그대로 읽는다.
## 등각 카메라와 깊이 가림은 유지하고 화면 해상도 그대로 그린다. 도트 느낌은 원본 그림에서 가져온다.
## 방 안 좌표(타일) (x, y) 는 3D 의 (x, 0, y) 이다. 지역(숲·광산·늪·유적)마다 바닥·벽·소품 모양과 빛이 다르다.

const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0
const WALL_H: float = 1.7
const WALL_T: float = 0.4
const GRID: int = 8

# 지역별 꾸밈: floor(질감 종류)·floor_tint·wall_tint·wall_kind·bg(배경색)·ambient·sun(빛 세기)·torch(횃불 불빛)
const THEMES: Dictionary = {
	"forest": {"slab": Color(0.36, 0.26, 0.17), "ring_tint": 0.82, "floor": "grass", "floor_tint": Color(0.5, 0.72, 0.44), "wall_kind": "hedge", "wall_tint": Color(0.42, 0.6, 0.4), "bg": Color(0.09, 0.15, 0.1), "ambient": Color(0.72, 0.82, 0.68), "sun": 0.75, "torch": Color(1.0, 0.85, 0.6), "obstacle": "tree"},
	"mine": {"slab": Color(0.26, 0.27, 0.33), "ring_tint": 0.7, "floor": "brick", "floor_tint": Color(0.62, 0.66, 0.78), "wall_kind": "rock", "wall_tint": Color(0.5, 0.54, 0.66), "bg": Color(0.06, 0.07, 0.1), "ambient": Color(0.55, 0.6, 0.78), "sun": 0.3, "torch": Color(1.0, 0.7, 0.4), "obstacle": "rock"},
	"swamp": {"slab": Color(0.2, 0.23, 0.16), "ring_tint": 0.75, "floor": "grass", "floor_tint": Color(0.44, 0.6, 0.42), "wall_kind": "rock", "wall_tint": Color(0.46, 0.6, 0.5), "bg": Color(0.06, 0.1, 0.08), "ambient": Color(0.5, 0.66, 0.56), "sun": 0.35, "torch": Color(0.7, 1.0, 0.7), "obstacle": "stump"},
	"hidden_ruins": {"slab": Color(0.3, 0.27, 0.36), "ring_tint": 0.72, "floor": "brick", "floor_tint": Color(0.7, 0.62, 0.8), "wall_kind": "ruin", "wall_tint": Color(0.66, 0.6, 0.78), "bg": Color(0.08, 0.06, 0.12), "ambient": Color(0.66, 0.6, 0.8), "sun": 0.32, "torch": Color(0.8, 0.6, 1.0), "obstacle": "column"},
}

var active: bool = true
var view: Control  # ExpeditionRoomView
var _vp: SubViewport
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _content: Node3D
var _id_dummy: Node3D
var _built_model: RefCounted = null
var _theme: Dictionary = THEMES["forest"]
var _theme_id: String = "forest"
var _scenery: ExpeditionScenery
var _wisps: Array = []
var _p: Dictionary = {"ts": 24, "block_px": 22.0, "unit_px_z": 20.0}
var _player: BlockyFigure
var _player_prev: Vector2 = Vector2.ZERO
var _prev_flash: float = 0.0
var _prev_hurt: float = 0.0
var _fx: Array = []  # 일시 효과: {kind, node, t, ...}
var _proj_nodes: Array = []
var _fx_mat: StandardMaterial3D
var _weapon_method: int = -1
var _enemy_nodes: Array = []  # {node, enemy}
var _object_nodes: Array = []
var _exit_glow: MeshInstance3D
var _exit_bars: MeshInstance3D
var _torches: Array = []  # OmniLight3D
var _anims: Array = []  # {node, mats, an}
var _time: float = 0.0
var _tile_scale: float = 1.0
var _pixel_floor_material: ShaderMaterial
var _pixel_floor: MeshInstance3D
var _backdrop: ExpeditionBackdrop


func _ready() -> void:
	stretch = true
	stretch_shrink = 1  # 화면 전체를 저해상도로 줄였다 확대하지 않는다.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_behind_parent = true
	_vp = SubViewport.new()
	_vp.own_world_3d = true  # 마을 3D 와 세계를 섞지 않는다
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.1
	_cam.far = 120.0
	_cam.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	_vp.add_child(_cam)
	_backdrop = ExpeditionBackdrop.new()
	_vp.add_child(_backdrop)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.rotation_degrees = Vector3(-52.0, 110.0, 0.0)
	_vp.add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, -60.0, 0.0)
	fill.light_energy = 0.22
	_vp.add_child(fill)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we := WorldEnvironment.new()
	we.environment = _env
	_vp.add_child(we)
	_content = Node3D.new()
	_vp.add_child(_content)
	_scenery = ExpeditionScenery.new(self)
	_id_dummy = Node3D.new()
	_id_dummy.visible = false
	_vp.add_child(_id_dummy)
	var player_key := "player_" + PlayerProgress.player_gender
	var player_frames := ActorSpriteFrames.load_set(player_key)
	if not player_frames.is_empty():
		var pixel := ExpeditionPixelPlayer.new()
		pixel.sprite_key = player_key
		pixel.frame_set = player_frames
		_player = pixel
	else:
		_player = BlockyFigure.new()
	_player.build(_content, _id_dummy, 3.0, 1.14, 0.308)
	_player.set_sorted(false)
	_player.weapon_always = true
	set_process(true)


# ---------------------------------------------------------------- 화면 좌표

# 방 안 타일 좌표(+높이)를 이 컨트롤의 화면 좌표로. 방 뷰의 2D 겹침 그림(체력 막대·표시)이 3D 와 같은 자리에 오게 한다.
func project(tile: Vector2, height: float = 0.0) -> Vector2:
	if _cam == null or _vp.size.x <= 0:
		return Vector2.ZERO

	var p: Vector2 = _cam.unproject_position(Vector3(tile.x, height, tile.y))
	return p * (size / Vector2(_vp.size))


func _layout() -> void:
	if view == null:
		return

	view._layout_board()
	var tile_w: float = float(view.tile_size.x) * float(view.tile_scale)
	# 한 칸 가로 폭(화면 px) tile_w ↔ 카메라: 월드 1칸 이동 = 화면 가로 tile_w/2
	var ppu_ctrl: float = tile_w / sqrt(2.0)  # 월드 길이 1 당 화면 px
	_cam.size = size.y / ppu_ctrl
	_cam.position = Vector3(GRID * 0.5, 0.0, GRID * 0.5) + _cam.basis.z * 40.0
	_cam.h_offset = 0.0
	_cam.v_offset = 0.0
	# 방 한가운데가 2D 판(board)의 가운데에 오도록 카메라를 옮긴다.
	var want: Vector2 = view.board.position + view.board.size * 0.5
	var got: Vector2 = project(Vector2(GRID * 0.5, GRID * 0.5), 0.0)
	_cam.h_offset = -(want.x - got.x) / ppu_ctrl
	_cam.v_offset = (want.y - got.y) / ppu_ctrl
	_tile_scale = float(view.tile_scale)
	_backdrop.layout(_cam, _vp.size)


# ---------------------------------------------------------------- 방 만들기

func _ready_theme(region: String) -> void:
	# 새 지역도 기존 자연물 메시를 재사용하고, 원정 출발 환경으로 바닥 색을 정한다.
	var style_id: String = {"meadow":"forest", "river_valley":"swamp"}.get(region, region)
	_theme = THEMES.get(style_id, THEMES["forest"]).duplicate(true)
	_theme_id = style_id if THEMES.has(style_id) else "forest"
	if region in ["meadow", "river_valley"]:
		var profile: Dictionary = view.model.CONTENT.region_profile(region)
		_theme["floor_tint"] = Color(str(profile["color"])).lightened(0.2)
	_theme["floor_tint"] = ExpeditionEnvironment.floor_tint(_theme["floor_tint"], view.weather_overlay.environment, _theme["floor"] == "grass")
	_env.background_color = _theme["bg"]
	_env.ambient_light_color = _theme["ambient"]
	_env.ambient_light_energy = 0.62
	_sun.light_energy = float(_theme["sun"])
	_sun.light_color = Color(1.0, 0.96, 0.9)


func rebuild(model: RefCounted, region: String) -> void:
	_built_model = model

	for c in _content.get_children():
		if c != _player:
			c.queue_free()

	_enemy_nodes.clear()
	_object_nodes.clear()
	_anims.clear()
	_torches.clear()
	_exit_glow = null
	_exit_bars = null
	_ready_theme(region)
	_backdrop.configure(self, region)
	_scenery.clear_cache()
	_wisps.clear()
	_build_floor()
	var srng := RandomNumberGenerator.new()
	srng.randomize()
	_scenery.build(_theme_id, srng, model)

	for r in model.obstacles:
		_build_obstacle(r)

	_build_objects(model)
	_build_enemies(model)
	_player_prev = model.player_position
	_prev_flash = 0.0
	_prev_hurt = 0.0
	_weapon_method = -1
	_clear_fx()
	_player.set_shown(true)


func _spec_tex(kind: String, tint: Color, name: String) -> Dictionary:
	return VillageAssets.spec(VillageAssets._tex(kind, int(_p["ts"])), tint, name, "던전 " + name)


func _node(b: VillageAssets.PartBuilder) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	var mats: Array = VillageAssets.make_materials(specs)

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var inst := MeshInstance3D.new()
	inst.mesh = mesh

	for i in range(mats.size()):
		inst.set_surface_override_material(i, mats[i])

	inst.set_meta("mats", mats)
	_content.add_child(inst)
	return inst


func _build_floor() -> void:
	if ExpeditionEnvironmentArt.build_floor(self): return
	var ts: int = int(_p["ts"])
	var kind: String = str(_theme["floor"])
	var tint: Color = _theme["floor_tint"]
	var b := VillageAssets.PartBuilder.new()

	# 타일마다 살짝 다른 밝기(3종)로 격자·얼룩이 보이게. 방 바깥(뒤쪽 두 변 너머 2칸)도 어둡게 이어 깔아 주변 풍경이 떠 보이지 않게 한다.
	var ring: float = float(_theme["ring_tint"])

	for y in range(-3, GRID + 2):
		for x in range(-3, GRID + 2):
			var v: int = absi(x * 7 + y * 13 + x * y) % 3
			# 방 안(0~7)은 그대로, 바깥은 방에서 멀수록 조금씩 어둡게. 주변 풍경이 놓인 곳 전부 바닥 위에 서게 사방으로 넓게 깐다.
			var out_d: int = maxi(maxi(-x, x - (GRID - 1)), maxi(-y, y - (GRID - 1)))
			var dim: float = 1.0 if out_d <= 0 else maxf(0.55, ring - 0.05 * float(out_d - 1))
			var br: float = (0.9 + 0.07 * float(v)) * dim
			var spec: Dictionary = _spec_tex(kind, tint * Color(br, br, br), "floor_%d_%d" % [v, clampi(out_d, 0, 4)])
			var st: SurfaceTool = b.new_part(spec, Vector3(x, 0, y), Vector3(x + 1, 0, y + 1))
			BuildingMesh._quad(st, Vector3(x, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1), Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

	# 판 옆면(앞쪽 둘): 지역 색(숲 = 흙, 광산 = 바위 …)
	var side: Dictionary = VillageAssets._noise_spec(ts, _theme["slab"], (_theme["slab"] as Color).lightened(0.12), "floor_side", 63, Color.WHITE, 0.1)
	VillageAssets.box(b, "slab", side, Vector3(-3, -0.7, -3), Vector3(GRID + 2, -0.02, GRID + 2))
	_node(b)

	# 바닥 이음 틈과 잔돌·풀(작은 소품): 칸 해시로 흩뿌림
	var deco := VillageAssets.PartBuilder.new()
	var pebble: Dictionary = _spec_tex("stone", Color(0.8, 0.8, 0.85), "pebble")

	for y in range(GRID):
		for x in range(GRID):
			var h: int = absi((x * 73856093) ^ (y * 19349663)) % 100

			if h < 14:
				VillageAssets.dome(deco, "pebble", pebble, float(x) + 0.2 + float(h % 6) * 0.1, float(y) + 0.25 + float((h / 3) % 6) * 0.09, 0.07 + float(h % 3) * 0.02, 0.0, 0.07, 2, 6)

	_node(deco)


func _wall_spec() -> Dictionary:
	var kind: String = "plank" if _theme["wall_kind"] == "hedge" else "brick"
	return _spec_tex(kind, _theme["wall_tint"], "wall")


func _build_walls() -> void:
	var b := VillageAssets.PartBuilder.new()
	var wall: Dictionary = _wall_spec()
	var cap: Dictionary = _spec_tex("stone", Color(0.9, 0.9, 0.95) * _theme["wall_tint"], "wall_cap")
	var exit_x: float = 3.5
	var gate_half: float = 0.85
	# 뒤쪽 벽 둘: z=0 줄(출구 문 틈 포함)과 x=0 줄
	VillageAssets.box(b, "wall_a", wall, Vector3(-WALL_T, 0, -WALL_T), Vector3(exit_x - gate_half, WALL_H, 0))
	VillageAssets.box(b, "wall_a2", wall, Vector3(exit_x + gate_half, 0, -WALL_T), Vector3(GRID, WALL_H, 0))
	VillageAssets.box(b, "lintel", wall, Vector3(exit_x - gate_half, WALL_H * 0.72, -WALL_T), Vector3(exit_x + gate_half, WALL_H, 0))
	VillageAssets.box(b, "wall_b", wall, Vector3(-WALL_T, 0, 0), Vector3(0, WALL_H, GRID))
	# 윗단(돌 덮개)
	VillageAssets.box(b, "cap_a", cap, Vector3(-WALL_T - 0.06, WALL_H, -WALL_T - 0.06), Vector3(GRID + 0.06, WALL_H + 0.1, 0.06))
	VillageAssets.box(b, "cap_b", cap, Vector3(-WALL_T - 0.06, WALL_H, 0.06), Vector3(0.06, WALL_H + 0.1, GRID + 0.06))
	# 문틀 기둥
	VillageAssets.box(b, "jamb", cap, Vector3(exit_x - gate_half - 0.14, 0, -WALL_T - 0.05), Vector3(exit_x - gate_half + 0.06, WALL_H * 0.74, 0.1))
	VillageAssets.box(b, "jamb", cap, Vector3(exit_x + gate_half - 0.06, 0, -WALL_T - 0.05), Vector3(exit_x + gate_half + 0.14, WALL_H * 0.74, 0.1))
	_node(b)
	# 출구: 닫힘이면 쇠창살, 열림이면 초록 빛
	var gb := VillageAssets.PartBuilder.new()
	var glow: Dictionary = VillageAssets._flat_spec(int(_p["ts"]), Color(0.45, 0.95, 0.5), "exit_glow")
	glow["emit"] = 1.0
	var st: SurfaceTool = gb.new_part(glow, Vector3(exit_x - gate_half, 0, -0.18), Vector3(exit_x + gate_half, WALL_H * 0.72, -0.18))
	BuildingMesh._quad(st, Vector3(exit_x - gate_half, 0, -0.18), Vector3(exit_x + gate_half, 0, -0.18), Vector3(exit_x + gate_half, WALL_H * 0.72, -0.18), Vector3(exit_x - gate_half, WALL_H * 0.72, -0.18), Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	_exit_glow = _node(gb)
	var bars := VillageAssets.PartBuilder.new()
	var iron: Dictionary = VillageAssets._flat_spec(int(_p["ts"]), Color(0.2, 0.2, 0.24), "gate_iron")

	for k in range(6):
		var bx: float = exit_x - gate_half + 0.16 + float(k) * ((gate_half * 2.0 - 0.32) / 5.0)
		VillageAssets.box(bars, "bar", iron, Vector3(bx - 0.03, 0, -0.12), Vector3(bx + 0.03, WALL_H * 0.72, -0.06))

	VillageAssets.box(bars, "bar_h", iron, Vector3(exit_x - gate_half, WALL_H * 0.3, -0.12), Vector3(exit_x + gate_half, WALL_H * 0.3 + 0.06, -0.06))
	_exit_bars = _node(bars)
	# 횃불: 문 양옆과 벽 가운데
	for tp in [Vector3(exit_x - gate_half - 0.45, WALL_H * 0.62, 0.12), Vector3(exit_x + gate_half + 0.45, WALL_H * 0.62, 0.12), Vector3(0.12, WALL_H * 0.62, 4.0), Vector3(6.4, WALL_H * 0.62, 0.12)]:
		_add_torch(tp)


func add_glow_light(pos: Vector3, color: Color, energy: float, rng_range: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = rng_range
	light.position = pos
	light.set_meta("base", energy)
	_content.add_child(light)
	_torches.append(light)


# 늪의 도깨비불: 떠다니는 작은 빛(초록)
func add_wisp(pos: Vector3, color: Color) -> void:
	var b := VillageAssets.PartBuilder.new()
	var glow: Dictionary = _flat(color, "wisp", 1.0)
	VillageAssets.dome(b, "wisp", glow, 0.0, 0.0, 0.08, -0.08, 0.1, 2, 8)
	var node: MeshInstance3D = _node(b)
	node.position = pos
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.7
	light.omni_range = 2.6
	node.add_child(light)
	_wisps.append({"node": node, "base": pos, "phase": randf() * 6.0})


func _add_torch(pos: Vector3) -> void:
	var sprite := ExpeditionSpriteArt.create(_content, "wall_torch", pos)
	if sprite != null:
		var sprite_light := OmniLight3D.new()
		sprite_light.light_color = _theme["torch"]
		sprite_light.light_energy = 0.9
		sprite_light.omni_range = 3.6
		sprite_light.position = pos + Vector3(0.1, 0.25, 0.1)
		_content.add_child(sprite_light)
		_torches.append(sprite_light)
		return
	var b := VillageAssets.PartBuilder.new()
	var wood_s: Dictionary = VillageAssets._flat_spec(int(_p["ts"]), Color(0.3, 0.2, 0.12), "torch_wood")
	var fire: Dictionary = VillageAssets._flat_spec(int(_p["ts"]), Color(1.0, 0.7, 0.2), "torch_fire")
	fire["emit"] = 1.0
	VillageAssets.box(b, "stick", wood_s, Vector3(-0.04, -0.3, -0.04), Vector3(0.04, 0.12, 0.04))
	VillageAssets.dome(b, "flame", fire, 0.0, 0.0, 0.09, 0.1, 0.34, 2, 6)
	var inst: MeshInstance3D = _node(b)
	inst.position = pos
	var light := OmniLight3D.new()
	light.light_color = _theme["torch"]
	light.light_energy = 0.9
	light.omni_range = 3.6
	light.position = pos + Vector3(0.1, 0.25, 0.1)
	_content.add_child(light)
	_torches.append(light)
	_anims.append({"node": inst, "mats": [], "kind": "torch_flicker", "phase": randf() * 6.0})


func _build_obstacle(r: Rect2) -> void:
	var c: Vector2 = r.get_center()
	var kind: String = str(_theme["obstacle"])
	var half := Vector2(0.5, 0.5)
	if kind != "column":
		if ExpeditionEnvironmentArt.create(self,"obstacle_"+kind,c,1.25 if kind=="rock" else 1.0) != null: return

	if kind == "column":
		if ExpeditionSpriteArt.create(_content, "broken_column", Vector3(c.x, 0, c.y)) != null:
			return
		var b := VillageAssets.PartBuilder.new()
		var stone: Dictionary = _spec_tex("stone", Color(0.82, 0.78, 0.9), "column")
		VillageAssets.box(b, "base", stone, Vector3(c.x - 0.38, 0, c.y - 0.38), Vector3(c.x + 0.38, 0.22, c.y + 0.38))
		VillageAssets.oct(b, "shaft", stone, c.x, c.y, 0.3, 0.2, 1.1, 0.27)
		VillageAssets.box(b, "broken", stone, Vector3(c.x - 0.24, 1.08, c.y - 0.2), Vector3(c.x + 0.2, 1.3, c.y + 0.26))
		var inst: MeshInstance3D = _node(b)
		return

	var rule: Dictionary = {"variant": "pine" if _theme["obstacle"] == "tree" else ""}
	var built: Dictionary = VillageAssets.build_prop(kind, -half, half, rule, _p)
	var mats: Array = VillageAssets.make_materials(built["specs"])

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var node := MeshInstance3D.new()
	node.mesh = built["mesh"]

	for i in range(mats.size()):
		node.set_surface_override_material(i, mats[i])

	node.position = Vector3(c.x, 0.0, c.y)
	node.scale = Vector3.ONE * (1.25 if kind == "rock" else 1.0)
	_content.add_child(node)


func _build_objects(model: RefCounted) -> void:
	if str(model.object_kind) == "":
		return

	if model.gathering_sites.is_empty():
		_object_nodes.append(_make_object(str(model.object_kind), str(model.object_loot_table), model.object_position, Color("edd18a")))
	else:
		for site in model.gathering_sites:
			_object_nodes.append(_make_object("gather_site", str(site.get("table", "")), Vector2(float(site["x"]), float(site["y"])), Color(str(site["color"]))))


func _rng_for(at: Vector2, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector3i(roundi(at.x * 100.0), roundi(at.y * 100.0), salt))
	return r


# 한 부품(면)에 여러 도형을 모으는 도우미: 같은 재질 여러 개를 한 면으로 합쳐 면 수를 줄인다.
func _part(b: VillageAssets.PartBuilder, spec: Dictionary) -> SurfaceTool:
	return b.new_part(spec, Vector3(-1, 0, -1), Vector3(1, 1.5, 1))


func _make_object(kind: String, table: String, at: Vector2, color: Color) -> Node3D:
	var sprite := ExpeditionSpriteArt.create(_content, ExpeditionSpriteArt.object_id(kind, table), Vector3(at.x, 0, at.y))
	if sprite != null: return sprite
	var rng: RandomNumberGenerator = _rng_for(at, 7)
	var node: Node3D

	if kind == "chest" or kind == "heal":
		node = _object_chest(rng) if kind == "chest" else _object_spring(rng)
	else:
		match table:
			"choice_forest_herb", "climate_spring_bud", "climate_summer_mint":
				node = _object_herbs(rng)
			"choice_wild_berry", "climate_autumn_nut":
				node = _object_berry_tree(rng)
			"choice_iron_ore":
				node = _object_ore(rng)
			"choice_stone_shard":
				node = _object_stones(rng)
			"choice_swamp_moss", "climate_snow_bloom":
				node = _object_moss(rng)
			"choice_marsh_reed", "gather_wheat":
				node = _object_reeds(rng)
			"gather_water":
				node = _object_spring(rng)
			"choice_ancient_fragment":
				node = _object_ruin_fragments(rng)
			"choice_rune_dust":
				node = _object_rune_crystals(rng)
			_:
				node = _object_crystals(rng, color)

	node.position = Vector3(at.x, 0.0, at.y)
	node.rotation.y = rng.randf() * TAU

	if kind == "gather_site" and table != "choice_wild_berry":
		node.scale = Vector3.ONE * 1.25  # 방에 비해 작아 보이던 채집 오브젝트를 조금 키운다

	return node


func _flat(color: Color, name: String, emit: float = 0.0) -> Dictionary:
	var sp: Dictionary = VillageAssets._flat_spec(int(_p["ts"]), color, name)

	if emit > 0.0:
		sp["emit"] = emit

	return sp


func _object_chest(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var ornate: bool = rng.randf() < 0.4
	var wood_s: Dictionary = VillageAssets.wood(_p, Color(0.5, 0.32, 0.2) if ornate else Color(0.62, 0.42, 0.24), "chest_wood")
	var gold: Dictionary = _flat(Color(0.95, 0.78, 0.25), "chest_gold", 0.25)
	VillageAssets.box(b, "body", wood_s, Vector3(-0.3, 0, -0.22), Vector3(0.3, 0.3, 0.22))
	VillageAssets.box(b, "lid", wood_s, Vector3(-0.32, 0.3, -0.24), Vector3(0.32, 0.46, 0.24))
	VillageAssets.box(b, "band", gold, Vector3(-0.34, 0.1, -0.06), Vector3(0.34, 0.2, 0.06))
	VillageAssets.box(b, "lock", gold, Vector3(-0.06, 0.28, 0.22), Vector3(0.06, 0.4, 0.28))

	if ornate:
		VillageAssets.box(b, "corner", gold, Vector3(-0.34, 0, -0.26), Vector3(-0.26, 0.46, -0.18))
		VillageAssets.box(b, "corner", gold, Vector3(0.26, 0, -0.26), Vector3(0.34, 0.46, -0.18))

	return _node(b)


func _object_spring(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var water: Dictionary = _flat(Color(0.45, 0.8, 0.95), "heal_water", 0.5)
	var rim: Dictionary = VillageAssets.stone_spec(_p, Color(0.8, 0.82, 0.88), "heal_rim")
	var r: float = 0.4 + rng.randf() * 0.1
	VillageAssets.oct(b, "rim", rim, 0.0, 0.0, r, 0.0, 0.22, r - 0.03)
	VillageAssets.oct(b, "water", water, 0.0, 0.0, r - 0.11, 0.2, 0.26, r - 0.12)
	# 샘 옆에 빛나는 작은 돌 둘(형태 변주)
	var glow: Dictionary = _flat(Color(0.55, 0.8, 0.9), "heal_glow", 0.35)

	for k in range(2):
		var a: float = rng.randf() * TAU
		VillageAssets.oct(b, "stone", glow, cos(a) * (r + 0.14), sin(a) * (r + 0.14), 0.09, 0.0, 0.2, 0.02)

	return _node(b)


# 약초: 풀 무더기 — 여러 갈래의 풀잎(가늘고 뾰족)과 몇 송이 꽃
func _object_herbs(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var greens: Array = [Color(0.22, 0.52, 0.22), Color(0.3, 0.62, 0.26), Color(0.4, 0.72, 0.3)]
	var sts: Array = []

	for k in range(3):
		sts.append(_part(b, _flat(greens[k], "herb_%d" % k)))

	var n: int = 15 + rng.randi() % 8

	for i in range(n):
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * 0.44
		var h: float = 0.2 + rng.randf() * 0.34
		VillageAssets.oct_st(sts[i % 3], cos(a) * d, sin(a) * d, 0.04 + rng.randf() * 0.03, 0.0, h, 0.0)

	var flower_cols: Array = [Color(1.0, 0.95, 0.95), Color(1.0, 0.8, 0.25), Color(0.85, 0.6, 1.0)]
	var fst: SurfaceTool = _part(b, _flat(flower_cols[rng.randi() % 3], "herb_flower", 0.2))

	for i in range(3 + rng.randi() % 3):
		var a2: float = rng.randf() * TAU
		var d2: float = sqrt(rng.randf()) * 0.36
		VillageAssets.dome_st(fst, cos(a2) * d2, sin(a2) * d2, 0.05, 0.3, 0.42, 2, 6)

	return _node(b)


# 열매 따기: 열매가 맺힌 나무(작은 나무 + 붉은 열매 알갱이)
func _object_berry_tree(rng: RandomNumberGenerator) -> Node3D:
	var half := Vector2(0.5, 0.5)
	var variant: String = ["round", "round", "big_oak"][rng.randi() % 3]
	var built: Dictionary = VillageAssets.build_prop("tree", -half, half, {"variant": variant}, _p)
	var mats: Array = VillageAssets.make_materials(built["specs"])

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var tree := MeshInstance3D.new()
	tree.mesh = built["mesh"]

	for i in range(mats.size()):
		tree.set_surface_override_material(i, mats[i])

	var sc: float = 0.62 + rng.randf() * 0.1
	tree.scale = Vector3.ONE * sc
	_content.add_child(tree)
	# 열매: 실제 잎 덩어리 표면(정점)에서 위치를 골라 박는다 — 허공에 뜨지 않게(나무 좌표계 = 확대 전)
	var b := VillageAssets.PartBuilder.new()
	var cols: Array = [Color(0.9, 0.15, 0.2), Color(0.95, 0.35, 0.15), Color(0.8, 0.1, 0.45)]
	var st: SurfaceTool = _part(b, _flat(cols[rng.randi() % 3], "berry", 0.35))
	var verts: Array = []
	var specs: Array = built["specs"]
	var mesh: ArrayMesh = built["mesh"]

	for si in range(mini(specs.size(), mesh.get_surface_count())):
		if str((specs[si] as Dictionary).get("name", "")).contains("foliage"):
			var arr: Array = mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]

			for vi in range(vs.size()):
				# 위쪽·바깥쪽을 향한 표면만(아래 그늘진 면 제외)
				if vs[vi].y > 0.9 and ns[vi].y > -0.1:
					verts.append(vs[vi] + ns[vi].normalized() * 0.03)

	for i in range(mini(14, verts.size())):
		var v: Vector3 = verts[rng.randi() % verts.size()]
		VillageAssets.dome_st(st, v.x, v.z, 0.07, v.y - 0.05, v.y + 0.06, 2, 6)

	var berries: MeshInstance3D = _node(b)
	_content.remove_child(berries)
	tree.add_child(berries)
	return tree


# 철광맥: 어두운 바위 무더기 + 녹슨 쇳덩이와 은빛 광석 알갱이
func _object_ore(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var rock: Dictionary = VillageAssets._noise_spec(int(_p["ts"]), Color(0.3, 0.3, 0.34), Color(0.45, 0.45, 0.5), "ore_rock", 51, Color.WHITE, 0.12)
	var rst: SurfaceTool = _part(b, rock)
	var rocks: Array = []

	for i in range(4 + rng.randi() % 2):
		var a: float = rng.randf() * TAU
		var d: float = 0.12 + rng.randf() * 0.22
		var rr: float = 0.2 + rng.randf() * 0.12
		var hh: float = 0.3 + rng.randf() * 0.3
		rocks.append([cos(a) * d, sin(a) * d, rr, hh])
		VillageAssets.dome_st(rst, cos(a) * d, sin(a) * d, rr, 0.0, hh, 2, 8)

	var rust: SurfaceTool = _part(b, _flat(Color(0.62, 0.34, 0.2), "ore_rust"))
	var silver: SurfaceTool = _part(b, _flat(Color(0.72, 0.8, 0.9), "ore_silver", 0.25))

	# 광석 알갱이는 바위 표면에 박힌다(바위 높이 곡선 위): 바위 중심에서 반지름의 55~80% 지점
	for i in range(8):
		var rk: Array = rocks[rng.randi() % rocks.size()]
		var a2: float = rng.randf() * TAU
		var frac: float = 0.45 + rng.randf() * 0.35
		var x: float = float(rk[0]) + cos(a2) * float(rk[2]) * frac
		var z: float = float(rk[1]) + sin(a2) * float(rk[2]) * frac
		var y: float = float(rk[3]) * sqrt(maxf(0.0, 1.0 - frac * frac)) - 0.05
		VillageAssets.box_st(rust if i % 2 == 0 else silver, Vector3(x - 0.05, y, z - 0.05), Vector3(x + 0.05, y + 0.09, z + 0.05))

	return _node(b)


# 돌 조각: 납작한 작은 돌 여러 개
func _object_stones(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var st: SurfaceTool = _part(b, VillageAssets._noise_spec(int(_p["ts"]), Color(0.52, 0.55, 0.58), Color(0.7, 0.72, 0.76), "shard_stone", 53, Color.WHITE, 0.12))

	for i in range(7 + rng.randi() % 4):
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * 0.42
		VillageAssets.dome_st(st, cos(a) * d, sin(a) * d, 0.07 + rng.randf() * 0.1, 0.0, 0.05 + rng.randf() * 0.1, 2, 6)

	return _node(b)


# 이끼: 낮고 넓은 초록 이끼 덩이와 작은 버섯
func _object_moss(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var moss_a: SurfaceTool = _part(b, VillageAssets._noise_spec(int(_p["ts"]), Color(0.3, 0.5, 0.24), Color(0.5, 0.7, 0.34), "moss_a", 55, Color.WHITE, 0.14))
	var moss_b: SurfaceTool = _part(b, VillageAssets._noise_spec(int(_p["ts"]), Color(0.22, 0.42, 0.28), Color(0.4, 0.6, 0.4), "moss_b", 57, Color.WHITE, 0.14))

	for i in range(7 + rng.randi() % 3):
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * 0.4
		VillageAssets.dome_st(moss_a if i % 2 == 0 else moss_b, cos(a) * d, sin(a) * d, 0.16 + rng.randf() * 0.14, 0.0, 0.1 + rng.randf() * 0.12, 2, 8)

	var stem: SurfaceTool = _part(b, _flat(Color(0.9, 0.88, 0.8), "mush_stem"))
	var cap: SurfaceTool = _part(b, _flat(Color(0.8, 0.3, 0.3), "mush_cap"))

	for i in range(2 + rng.randi() % 2):
		var a2: float = rng.randf() * TAU
		var d2: float = 0.15 + rng.randf() * 0.25
		var x: float = cos(a2) * d2
		var z: float = sin(a2) * d2
		VillageAssets.box_st(stem, Vector3(x - 0.02, 0.1, z - 0.02), Vector3(x + 0.02, 0.24, z + 0.02))
		VillageAssets.dome_st(cap, x, z, 0.07, 0.22, 0.31, 2, 6)

	return _node(b)


# 갈대: 가늘고 긴 줄기 다발과 끝의 갈색 이삭
func _object_reeds(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var cols: Array = [Color(0.72, 0.7, 0.4), Color(0.6, 0.66, 0.34)]
	var sts: Array = [_part(b, _flat(cols[0], "reed_a")), _part(b, _flat(cols[1], "reed_b"))]
	var tip: SurfaceTool = _part(b, _flat(Color(0.45, 0.3, 0.18), "reed_tip"))

	for i in range(16 + rng.randi() % 6):
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * 0.4
		var h: float = 0.6 + rng.randf() * 0.5
		var x: float = cos(a) * d
		var z: float = sin(a) * d
		VillageAssets.oct_st(sts[i % 2], x, z, 0.03, 0.0, h, 0.012)

		if i % 3 == 0:
			VillageAssets.oct_st(tip, x, z, 0.04, h - 0.02, h + 0.14, 0.03)

	return _node(b)


# 고대 파편: 부서진 석판·기둥 조각과 희미하게 빛나는 문양
func _object_ruin_fragments(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var stone: Dictionary = VillageAssets._noise_spec(int(_p["ts"]), Color(0.62, 0.58, 0.5), Color(0.78, 0.74, 0.66), "frag_stone", 59, Color.WHITE, 0.1)
	var sst: SurfaceTool = _part(b, stone)

	for i in range(3 + rng.randi() % 2):
		var a: float = rng.randf() * TAU
		var d: float = rng.randf() * 0.32
		var x: float = cos(a) * d
		var z: float = sin(a) * d
		var w: float = 0.1 + rng.randf() * 0.12
		VillageAssets.box_st(sst, Vector3(x - w, 0.0, z - 0.05), Vector3(x + w, 0.18 + rng.randf() * 0.4, z + 0.06))

	for i in range(4):
		VillageAssets.dome_st(sst, rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4), 0.08 + rng.randf() * 0.05, 0.0, 0.07, 2, 6)

	var rune: SurfaceTool = _part(b, _flat(Color(0.5, 0.9, 1.0), "frag_rune", 1.0))
	var rx: float = rng.randf_range(-0.1, 0.1)
	VillageAssets.box_st(rune, Vector3(rx - 0.03, 0.12, 0.07), Vector3(rx + 0.03, 0.34, 0.1))
	return _node(b)


# 룬 가루: 보랏빛 룬 수정 몇 개와 바닥에 희미하게 빛나는 원
func _object_rune_crystals(rng: RandomNumberGenerator) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var glow: SurfaceTool = _part(b, _flat(Color(0.7, 0.45, 1.0), "rune_crystal", 0.8))
	var dark: SurfaceTool = _part(b, _flat(Color(0.4, 0.25, 0.65), "rune_crystal_dark", 0.3))

	for i in range(4 + rng.randi() % 3):
		var a: float = rng.randf() * TAU
		var d: float = rng.randf() * 0.28
		var h: float = 0.3 + rng.randf() * 0.42
		VillageAssets.oct_st(glow if i % 2 == 0 else dark, cos(a) * d, sin(a) * d, 0.09 + rng.randf() * 0.05, 0.0, h, 0.0)

	var ring: SurfaceTool = _part(b, _flat(Color(0.42, 0.3, 0.62), "rune_ring", 0.15))
	VillageAssets.oct_st(ring, 0.0, 0.0, 0.36, 0.0, 0.012, 0.35)
	return _node(b)


# 그 밖의 채집 지점: 색 수정 다발(기본)
func _object_crystals(rng: RandomNumberGenerator, color: Color) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var cry: Dictionary = _flat(color, "gather_crystal", 0.6)
	var dark: Dictionary = _flat(color.darkened(0.35), "gather_crystal_dark")
	VillageAssets.oct(b, "c1", dark, 0.0, 0.0, 0.2, 0.0, 0.42, 0.03)
	VillageAssets.oct(b, "c2", cry, -0.2, 0.08, 0.13, 0.0, 0.62, 0.02)
	VillageAssets.oct(b, "c3", cry, 0.18, -0.1, 0.12, 0.0, 0.5, 0.02)
	return _node(b)


func _build_enemies(model: RefCounted) -> void:
	for e in model.enemies:
		var sprite := ExpeditionSpriteArt.create(_content, str(e.get("id", "")), Vector3.ZERO)
		if sprite != null:
			_enemy_nodes.append({"node": sprite, "enemy": e, "hp_prev": int(e["hp"]), "flash": 0.0, "prev_windup": -1.0, "wmax": 0.65, "lunge": -1.0, "lunge_dir": Vector2.ZERO})
			continue
		var boss: bool = bool(e["boss"])
		var r: float = 0.55 if boss else 0.3
		var col: Color = Color(str(e.get("color", "85bad4")))
		var b := VillageAssets.PartBuilder.new()
		var ts: int = int(_p["ts"])
		var body: Dictionary = VillageAssets._noise_spec(ts, col, col.lightened(0.18), "enemy_body", 41, Color.WHITE, 0.1)
		var eye: Dictionary = VillageAssets._flat_spec(ts, Color(0.08, 0.1, 0.16), "enemy_eye")
		VillageAssets.dome(b, "body", body, 0.0, 0.0, r, 0.0, r * 1.5, 3, 12)
		VillageAssets.box(b, "eye_l", eye, Vector3(r * 0.55, r * 0.8, r * 0.3), Vector3(r * 0.55 + 0.06, r * 0.8 + 0.09, r * 0.3 + 0.06))
		VillageAssets.box(b, "eye_r", eye, Vector3(r * 0.3, r * 0.8, r * 0.55), Vector3(r * 0.3 + 0.06, r * 0.8 + 0.09, r * 0.55 + 0.06))

		if boss:
			var horn: Dictionary = VillageAssets._flat_spec(ts, Color(0.92, 0.88, 0.7), "boss_horn")
			VillageAssets.oct(b, "horn_l", horn, -r * 0.4, 0.0, 0.1, r * 1.3, r * 1.9, 0.0)
			VillageAssets.oct(b, "horn_r", horn, r * 0.4, 0.0, 0.1, r * 1.3, r * 1.9, 0.0)

		var inst: MeshInstance3D = _node(b)
		_enemy_nodes.append({"node": inst, "enemy": e, "hp_prev": int(e["hp"]), "flash": 0.0, "prev_windup": -1.0, "wmax": 0.65, "lunge": -1.0, "lunge_dir": Vector2.ZERO})


# ---------------------------------------------------------------- 매 프레임

func _process(delta: float) -> void:
	if not active or view == null or view.model == null:
		return

	visible = true
	_time += delta
	var model: RefCounted = view.model

	if model != _built_model:
		rebuild(model, str(view.region_id))

	_layout()
	_sync(model, delta)


var _hurt_dir: Vector2 = Vector2.ZERO


# 가장 가까운 살아 있는 적에게서 멀어지는 방향(피격 때 밀려나는 쪽)
func _away_from_enemies(model: RefCounted) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_d: float = INF

	for e in model.enemies:
		if int(e["hp"]) <= 0:
			continue

		var d: float = model.player_position.distance_to(e["position"])

		if d < best_d:
			best_d = d
			best = (model.player_position - (e["position"] as Vector2)).normalized()

	return best


func _sync(model: RefCounted, delta: float) -> void:
	# ---- 플레이어
	var pos: Vector2 = model.player_position
	var moved: float = pos.distance_to(_player_prev)
	_player_prev = pos
	_player.walking = moved > 0.0005
	_player.facing_yaw_deg = rad_to_deg(atan2(model.facing.x, model.facing.y))

	if _player.walking:
		_player.move_speed = lerpf(_player.move_speed, clampf(moved / maxf(delta, 0.0001), 0.5, 5.0), 0.3)

	# 무기 모양(공격 방식이 바뀌면 다시 쥐게 한다)과 공격 동작: 모델이 공격을 시작하면(attack_flash 가 0 → 양수) 휘두른다.
	var method: int = int(model.attack_profile.method)

	if method != _weapon_method:
		_weapon_method = method
		_player.set_weapon("staff" if method == ExpeditionAttackProfile.Method.PROJECTILE else "sword")

	if float(model.attack_flash) > 0.0 and _prev_flash <= 0.0:
		var dur: float = maxf(0.3, float(model.attack_profile.cooldown) * 0.85)
		_player.play_attack(dur, method == ExpeditionAttackProfile.Method.PROJECTILE, float(model.attack_profile.arc_degrees))

		if method == ExpeditionAttackProfile.Method.MELEE:
			_spawn_slash(model, dur)

	_prev_flash = float(model.attack_flash)

	# 피격: 몸이 젖혀지고 붉게 번쩍이며 적에게서 밀려난다. 무적 시간 끝 무렵엔 깜빡인다.
	if float(model.hurt_remaining) > 0.0 and _prev_hurt <= 0.0:
		_player.play_hurt(0.4)
		_hurt_dir = _away_from_enemies(model)

	_prev_hurt = float(model.hurt_remaining)
	_player.animate(delta)
	var hk: float = _player.hurt_amount()
	_player.set_tint(Color.WHITE.lerp(Color(2.3, 0.5, 0.5), hk))
	_player.position = Vector3(pos.x + _hurt_dir.x * 0.3 * hk, 0.0, pos.y + _hurt_dir.y * 0.3 * hk)
	var blink: bool = float(model.hurt_remaining) > 0.0 and float(model.hurt_remaining) < 0.32 and int(_time * 16.0) % 2 == 0
	_player.set_shown(not blink)

	# ---- 적: 위치·방향·출렁임. 공격 준비(웅크리며 붉어짐) → 도약(내려찍기) → 충격 고리. 맞으면 하얗게 번쩍이며 떨린다.
	var reach_e: float = 0.9

	for en in _enemy_nodes:
		var e: Dictionary = en["enemy"]
		var node: MeshInstance3D = en["node"]
		node.visible = int(e["hp"]) > 0
		var ep: Vector2 = e["position"]
		var winding: bool = float(e["windup"]) >= 0.0
		var wprev: float = float(en["prev_windup"])

		if winding and wprev < 0.0:
			en["wmax"] = maxf(0.1, float(e["windup"]))  # 준비 시작: 전체 준비 시간 기억

		if not winding and wprev >= 0.0 and int(e["hp"]) > 0:
			# 준비가 끝나 공격이 나갔다: 목표 쪽으로 도약하고 땅에 충격 고리
			var tgt: Vector2 = e["target"]
			en["lunge"] = 0.0
			en["lunge_dir"] = (tgt - ep).normalized()
			reach_e = 1.35 if bool(e["boss"]) else 0.9
			_spawn_ring(tgt, reach_e, Color(1.0, 0.45, 0.25), 0.35)

		en["prev_windup"] = float(e["windup"])
		var q: float = clampf(1.0 - float(e["windup"]) / float(en["wmax"]), 0.0, 1.0) if winding else 0.0
		var to_p: Vector2 = (e["target"] as Vector2 - ep).normalized() if winding else (model.player_position - ep).normalized()
		var bob: float = 0.04 * sin(_time * 5.0 + ep.x * 3.0) * (1.0 - q)
		var off: Vector2 = -to_p * 0.22 * q  # 준비: 뒤로 웅크림
		var sx: float = 1.0 + 0.2 * q
		var sy: float = 1.0 - 0.3 * q

		if float(en["lunge"]) >= 0.0:
			en["lunge"] = float(en["lunge"]) + delta
			var lt: float = clampf(float(en["lunge"]) / 0.26, 0.0, 1.0)
			var f: float = sin(lt * PI)
			off = (en["lunge_dir"] as Vector2) * 0.7 * f
			sx = 1.0 - 0.2 * f
			sy = 1.0 + 0.32 * f

			if lt >= 1.0:
				en["lunge"] = -1.0

		node.position = Vector3(ep.x + off.x, absf(bob) + (0.12 * sin(clampf(float(en["lunge"]) / 0.26, 0.0, 1.0) * PI) if float(en["lunge"]) >= 0.0 else 0.0), ep.y + off.y)
		if node.has_meta("expedition_sprite_id"):
			# 정지 도트의 자세/종횡비 유지. 예고·도약은 위치와 색으로 표현한다.
			node.rotation = Vector3.ZERO
			node.scale = Vector3.ONE
		else:
			node.rotation.y = atan2(to_p.x, to_p.y) - PI * 0.25
			node.scale = Vector3(sx, sy, sx)

		# 맞으면 하얗게 번쩍이며 뒤로 떨린다
		if int(e["hp"]) < int(en["hp_prev"]):
			en["flash"] = 0.16

		en["hp_prev"] = int(e["hp"])
		en["flash"] = maxf(0.0, float(en["flash"]) - delta)
		var flash_on: bool = float(en["flash"]) > 0.0
		var tint: Color = Color(1.0 + 1.1 * q, 1.0 - 0.45 * q, 1.0 - 0.45 * q)

		if flash_on:
			tint = Color(2.4, 2.4, 2.4)
			node.position += Vector3(sin(_time * 90.0), 0.0, cos(_time * 90.0)) * 0.03

		for m in node.get_meta("mats", []):
			(m as ShaderMaterial).set_shader_parameter("tint", tint)
		if node.has_meta("expedition_sprite_id"):
			(node.material_override as ShaderMaterial).set_shader_parameter("light_tint", tint)

	# ---- 투사체(멀리 쏘는 무기): 빛나는 구슬
	_sync_projectiles(model)
	# ---- 오브젝트: 사용했으면 숨김
	for o in _object_nodes:
		(o as Node3D).visible = not model.object_consumed

	# 길목: 전투 중에는 어둡게, 통행 가능하면 자연스러운 길 색으로 표시한다.
	if _exit_glow != null:
		_exit_glow.visible = bool(model.exit_open)
		_exit_bars.visible = not bool(model.exit_open)

	for i in range(_torches.size()):
		(_torches[i] as OmniLight3D).light_energy = float((_torches[i] as OmniLight3D).get_meta("base", 0.9)) * (1.0 + 0.2 * sin(_time * 7.0 + float(i) * 1.7) + 0.1 * sin(_time * 13.0 + float(i)))

	for w in _wisps:
		var base: Vector3 = w["base"]
		var ph: float = float(w["phase"])
		(w["node"] as Node3D).position = base + Vector3(sin(_time * 0.7 + ph) * 0.5, 0.15 * sin(_time * 1.6 + ph), cos(_time * 0.55 + ph) * 0.5)

	_tick_fx(delta)


# ---------------------------------------------------------------- 효과: 베기 궤적·충격 고리·투사체

func _fx_material() -> StandardMaterial3D:
	if _fx_mat == null:
		_fx_mat = StandardMaterial3D.new()
		_fx_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fx_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_fx_mat.vertex_color_use_as_albedo = true
		_fx_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	return _fx_mat


func _clear_fx() -> void:
	for f in _fx:
		if is_instance_valid(f["node"]):
			(f["node"] as Node).queue_free()

	_fx.clear()

	for n in _proj_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()

	_proj_nodes.clear()


# 베기 궤적: 플레이어 앞 공격 부채꼴을 따라 한 번 쓸고 가는 빛줄기(머리는 밝고 꼬리는 투명). 칼 내려치는 순간(공격 시간의 28%)에 시작한다.
func _spawn_slash(model: RefCounted, dur: float) -> void:
	var node := MeshInstance3D.new()
	node.material_override = _fx_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_content.add_child(node)
	var face: Vector2 = model.facing
	_fx.append({"kind": "slash", "node": node, "t": 0.0, "delay": dur * 0.2, "sweep": dur * 0.3, "fade": 0.2,
		"center": model.player_position, "angle": atan2(face.y, face.x), "half": deg_to_rad(float(model.attack_profile.arc_degrees)) * 0.5,
		"reach": float(model.attack_profile.reach)})


func _build_slash_mesh(f: Dictionary, head_u: float, tail_u: float, alpha: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector2 = f["center"]
	var a0: float = float(f["angle"]) - float(f["half"])  # 시작(오른쪽): 팔 휘두름과 같은 방향
	var a1: float = float(f["angle"]) + float(f["half"])
	var r_out: float = float(f["reach"]) * 1.0
	var r_in: float = float(f["reach"]) * 0.4
	var n: int = 14

	for i in range(n):
		var u0: float = lerpf(tail_u, head_u, float(i) / float(n))
		var u1: float = lerpf(tail_u, head_u, float(i + 1) / float(n))
		var al0: float = alpha * pow(float(i) / float(n), 1.6)
		var al1: float = alpha * pow(float(i + 1) / float(n), 1.6)
		var pts: Array = []

		for u in [u0, u1]:
			var ang: float = lerpf(a0, a1, u)
			var y: float = 0.62 + 0.1 * sin(u * PI)  # 마인크래프트 휩쓸기처럼 수평에 가까운 부채꼴
			var dir := Vector2(cos(ang), sin(ang))
			pts.append([c + dir * r_out, y, c + dir * r_in, y - 0.04])

		var cols0 := Color(1.0, 0.95, 0.7, al0)
		var cols1 := Color(1.0, 0.95, 0.7, al1)
		var o0: Vector2 = pts[0][0]
		var i0: Vector2 = pts[0][2]
		var o1: Vector2 = pts[1][0]
		var i1: Vector2 = pts[1][2]
		var v_o0 := Vector3(o0.x, float(pts[0][1]), o0.y)
		var v_i0 := Vector3(i0.x, float(pts[0][3]), i0.y)
		var v_o1 := Vector3(o1.x, float(pts[1][1]), o1.y)
		var v_i1 := Vector3(i1.x, float(pts[1][3]), i1.y)
		for tri in [[v_o0, cols0], [v_i0, cols0], [v_o1, cols1], [v_i0, cols0], [v_i1, cols1], [v_o1, cols1]]:
			st.set_color(tri[1])
			st.add_vertex(tri[0])

	return st.commit()


# 땅에 퍼지는 충격 고리(적 공격 착탄). 반지름 radius 까지 커지며 사라진다.
func _spawn_ring(at: Vector2, radius: float, color: Color, life: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg: int = 28

	for i in range(seg):
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		var o0 := Vector3(cos(a0), 0.05, sin(a0))
		var o1 := Vector3(cos(a1), 0.05, sin(a1))
		var n0 := o0 * 0.78
		var n1 := o1 * 0.78
		n0.y = 0.05
		n1.y = 0.05

		for v in [[o0, 1.0], [n0, 0.0], [o1, 1.0], [n0, 0.0], [n1, 0.0], [o1, 1.0]]:
			st.set_color(Color(color.r, color.g, color.b, float(v[1])))
			st.add_vertex(v[0])

	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = _fx_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(at.x, 0.0, at.y)
	node.scale = Vector3(0.2, 1.0, 0.2)
	_content.add_child(node)
	_fx.append({"kind": "ring", "node": node, "t": 0.0, "life": life, "radius": radius})


func _tick_fx(delta: float) -> void:
	var keep: Array = []

	for f in _fx:
		f["t"] = float(f["t"]) + delta
		var node: MeshInstance3D = f["node"]

		if str(f["kind"]) == "ring":
			var p: float = float(f["t"]) / float(f["life"])

			if p >= 1.0:
				node.queue_free()
				continue

			var r: float = float(f["radius"]) * (0.25 + 0.75 * (1.0 - pow(1.0 - p, 3.0)))
			node.scale = Vector3(r, 1.0, r)
			node.transparency = clampf(p * p, 0.0, 1.0)  # 뒤로 갈수록 투명
		else:
			var t: float = float(f["t"]) - float(f["delay"])
			var total: float = float(f["sweep"]) + float(f["fade"])

			if t >= total:
				node.queue_free()
				continue

			if t < 0.0:
				node.mesh = null
			else:
				var sp: float = clampf(t / float(f["sweep"]), 0.0, 1.0)
				var head: float = 1.0 - pow(1.0 - sp, 2.0)  # 빠르게 시작해 느려진다
				var tail: float = maxf(0.0, head - 0.55 - 0.4 * clampf((t - float(f["sweep"])) / float(f["fade"]), 0.0, 1.0))
				var alpha: float = 1.0 - clampf((t - float(f["sweep"])) / float(f["fade"]), 0.0, 1.0)
				node.mesh = _build_slash_mesh(f, head, tail, alpha)

		keep.append(f)

	_fx = keep


func _sync_projectiles(model: RefCounted) -> void:
	var count: int = model.projectiles.size()

	while _proj_nodes.size() < count:
		var b := VillageAssets.PartBuilder.new()
		var glow: Dictionary = VillageAssets._flat_spec(int(_p["ts"]), Color(1.0, 0.92, 0.55), "bolt")
		glow["emit"] = 1.0
		VillageAssets.dome(b, "bolt", glow, 0.0, 0.0, 0.1, -0.05, 0.12, 2, 8)
		VillageAssets.dome(b, "bolt_low", glow, 0.0, 0.0, 0.1, -0.12, 0.05, 2, 8)
		_proj_nodes.append(_node(b))

	for i in range(_proj_nodes.size()):
		var n: MeshInstance3D = _proj_nodes[i]
		n.visible = i < count

		if i < count:
			var sp: Vector2 = model.projectiles[i]["position"]
			n.position = Vector3(sp.x, 0.7, sp.y)
