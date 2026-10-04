class_name ExpeditionStage3D
extends SubViewportContainer
## 원정 던전 방(8×8)을 3D 로 그리는 무대. ExpeditionRoomView 의 뒤(show_behind_parent)에 깔리고, 방 모델(ExpeditionRoomModel)을 그대로 읽는다.
## 마을 3D(StoreView3D)와 같은 카메라 각도·낮은 해상도 도트 느낌을 쓰지만, 정렬 순번 대신 진짜 깊이로 가려서 기둥 뒤에 서면 캐릭터가 가려진다.
## 방 안 좌표(타일) (x, y) 는 3D 의 (x, 0, y) 이다. 지역(숲·광산·늪·유적)마다 바닥·벽·소품 모양과 빛이 다르다.

const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0
const WALL_H: float = 1.7
const WALL_T: float = 0.4
const GRID: int = 8
const SHRINK: int = 3

# 지역별 꾸밈: floor(질감 종류)·floor_tint·wall_tint·wall_kind·bg(배경색)·ambient·sun(빛 세기)·torch(횃불 불빛)
const THEMES: Dictionary = {
	"forest": {"floor": "grass", "floor_tint": Color(0.5, 0.72, 0.44), "wall_kind": "hedge", "wall_tint": Color(0.42, 0.6, 0.4), "bg": Color(0.1, 0.16, 0.14), "ambient": Color(0.62, 0.74, 0.62), "sun": 0.42, "torch": Color(1.0, 0.85, 0.6), "obstacle": "tree"},
	"mine": {"floor": "brick", "floor_tint": Color(0.62, 0.66, 0.78), "wall_kind": "rock", "wall_tint": Color(0.5, 0.54, 0.66), "bg": Color(0.06, 0.07, 0.1), "ambient": Color(0.55, 0.6, 0.78), "sun": 0.3, "torch": Color(1.0, 0.7, 0.4), "obstacle": "rock"},
	"swamp": {"floor": "grass", "floor_tint": Color(0.44, 0.6, 0.42), "wall_kind": "rock", "wall_tint": Color(0.46, 0.6, 0.5), "bg": Color(0.06, 0.1, 0.08), "ambient": Color(0.5, 0.66, 0.56), "sun": 0.35, "torch": Color(0.7, 1.0, 0.7), "obstacle": "stump"},
	"hidden_ruins": {"floor": "brick", "floor_tint": Color(0.7, 0.62, 0.8), "wall_kind": "ruin", "wall_tint": Color(0.66, 0.6, 0.78), "bg": Color(0.08, 0.06, 0.12), "ambient": Color(0.66, 0.6, 0.8), "sun": 0.32, "torch": Color(0.8, 0.6, 1.0), "obstacle": "column"},
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


func _ready() -> void:
	stretch = true
	stretch_shrink = SHRINK
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
	_id_dummy = Node3D.new()
	_id_dummy.visible = false
	_vp.add_child(_id_dummy)
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
	return p * (size.x / float(_vp.size.x))


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


# ---------------------------------------------------------------- 방 만들기

func _ready_theme(region: String) -> void:
	_theme = THEMES.get(region, THEMES["forest"])
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
	_build_floor()
	_build_walls()

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
	var ts: int = int(_p["ts"])
	var kind: String = str(_theme["floor"])
	var tint: Color = _theme["floor_tint"]
	var b := VillageAssets.PartBuilder.new()

	# 타일마다 살짝 다른 밝기(3종)로 격자·얼룩이 보이게
	for y in range(GRID):
		for x in range(GRID):
			var v: int = (x * 7 + y * 13 + x * y) % 3
			var spec: Dictionary = _spec_tex(kind, tint * Color(0.9 + 0.07 * v, 0.9 + 0.07 * v, 0.9 + 0.07 * v), "floor_%d" % v)
			var st: SurfaceTool = b.new_part(spec, Vector3(x, 0, y), Vector3(x + 1, 0, y + 1))
			BuildingMesh._quad(st, Vector3(x, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1), Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

	# 판 옆면(앞쪽 둘): 어두운 돌
	var side: Dictionary = _spec_tex("brick", Color(0.32, 0.3, 0.34), "floor_side")
	VillageAssets.box(b, "slab", side, Vector3(0, -0.7, 0), Vector3(GRID, -0.02, GRID))
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


func _add_torch(pos: Vector3) -> void:
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

	if kind == "column":
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
		_object_nodes.append(_make_object(str(model.object_kind), model.object_position, Color("edd18a")))
	else:
		for site in model.gathering_sites:
			_object_nodes.append(_make_object("gather_site", Vector2(float(site["x"]), float(site["y"])), Color(str(site["color"]))))


func _make_object(kind: String, at: Vector2, color: Color) -> Node3D:
	var b := VillageAssets.PartBuilder.new()
	var ts: int = int(_p["ts"])

	if kind == "chest":
		var wood_s: Dictionary = VillageAssets.wood(_p, Color(0.62, 0.42, 0.24), "chest_wood")
		var gold: Dictionary = VillageAssets._flat_spec(ts, Color(0.95, 0.78, 0.25), "chest_gold")
		gold["emit"] = 0.25
		VillageAssets.box(b, "body", wood_s, Vector3(-0.3, 0, -0.22), Vector3(0.3, 0.3, 0.22))
		VillageAssets.box(b, "lid", wood_s, Vector3(-0.32, 0.3, -0.24), Vector3(0.32, 0.46, 0.24))
		VillageAssets.box(b, "band", gold, Vector3(-0.34, 0.1, -0.06), Vector3(0.34, 0.2, 0.06))
		VillageAssets.box(b, "lock", gold, Vector3(-0.06, 0.28, 0.22), Vector3(0.06, 0.4, 0.28))
	elif kind == "heal":
		var spring: Dictionary = VillageAssets._flat_spec(ts, Color(0.45, 0.8, 0.95), "heal_water")
		spring["emit"] = 0.5
		var rim: Dictionary = VillageAssets.stone_spec(_p, Color(0.8, 0.82, 0.88), "heal_rim")
		VillageAssets.oct(b, "rim", rim, 0.0, 0.0, 0.45, 0.0, 0.22, 0.42)
		VillageAssets.oct(b, "water", spring, 0.0, 0.0, 0.34, 0.2, 0.26, 0.33)
	else:
		# 채집 지점: 색 수정/풀 다발 여러 개
		var cry: Dictionary = VillageAssets._flat_spec(ts, color, "gather_crystal")
		cry["emit"] = 0.6
		var dark: Dictionary = VillageAssets._flat_spec(ts, color.darkened(0.35), "gather_crystal_dark")
		VillageAssets.oct(b, "c1", dark, 0.0, 0.0, 0.2, 0.0, 0.42, 0.03)
		VillageAssets.oct(b, "c2", cry, -0.2, 0.08, 0.13, 0.0, 0.62, 0.02)
		VillageAssets.oct(b, "c3", cry, 0.18, -0.1, 0.12, 0.0, 0.5, 0.02)
		VillageAssets.oct(b, "c4", dark, 0.08, 0.2, 0.1, 0.0, 0.34, 0.02)

	var inst: MeshInstance3D = _node(b)
	inst.position = Vector3(at.x, 0.0, at.y)
	return inst


func _build_enemies(model: RefCounted) -> void:
	for e in model.enemies:
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


func _snap(p: Vector3) -> Vector3:
	var px: float = _cam.size / float(maxi(1, _vp.size.y))
	var right: Vector3 = _cam.basis.x
	var up: Vector3 = _cam.basis.y
	var r: float = p.dot(right)
	var u: float = p.dot(up)
	return p + (roundf(r / px) * px - r) * right + (roundf(u / px) * px - u) * up


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
	_player.position = _snap(Vector3(pos.x + _hurt_dir.x * 0.3 * hk, 0.0, pos.y + _hurt_dir.y * 0.3 * hk))
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

		node.position = _snap(Vector3(ep.x + off.x, absf(bob) + (0.12 * sin(clampf(float(en["lunge"]) / 0.26, 0.0, 1.0) * PI) if float(en["lunge"]) >= 0.0 else 0.0), ep.y + off.y))
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

	# ---- 투사체(멀리 쏘는 무기): 빛나는 구슬
	_sync_projectiles(model)
	# ---- 오브젝트: 사용했으면 숨김
	for o in _object_nodes:
		(o as Node3D).visible = not model.object_consumed

	# 출구: 열렸으면 초록 빛, 닫혔으면 창살
	if _exit_glow != null:
		_exit_glow.visible = bool(model.exit_open)
		_exit_bars.visible = not bool(model.exit_open)

	for i in range(_torches.size()):
		(_torches[i] as OmniLight3D).light_energy = 0.9 + 0.2 * sin(_time * 7.0 + float(i) * 1.7) + 0.1 * sin(_time * 13.0 + float(i))

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
	var a0: float = float(f["angle"]) + float(f["half"])  # 시작(위쪽 오른쪽)
	var a1: float = float(f["angle"]) - float(f["half"])
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
