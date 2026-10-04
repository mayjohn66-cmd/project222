extends Node
## 개발용: 마을의 모든 건물을 연 상태(정착 이야기 진행 무시)로 3D 겹침/3D만 화면을 본다.
## 실행: 이 씬을 열고 F6. 조작은 게임과 같고 F10 = 끔→겹침→3D만. 숫자키 1~5 = 마을 구역으로 순간이동.
## 인자(스크린샷용): --shot <폴더>
var _scene: Node
var _terrain: Node2D
var _player: Node2D
var _label: Label

const SPOTS: Array = [
	["1 마을 광장", Vector2i(17, 4)],
	["2 빵집·가판대", Vector2i(18, 10)],
	["3 서쪽 집들", Vector2i(-2, 20)],
	["4 시장(남쪽)", Vector2i(0, 31)],
	["5 동쪽 집들", Vector2i(24, 20)],
]

func _ready() -> void:
	_scene = load("res://scenes/shop/main.tscn").instantiate()
	add_child(_scene)
	for i in range(30):
		await get_tree().process_frame
	_terrain = _scene.get_node("StoreExterior")
	_player = _scene.get_node("Actors/Player")
	var settlement := _scene.get_node_or_null("VillageSettlement")
	if settlement != null:
		settlement.free()
	_open_all()
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	_label.text = "F10 3D 전환 · 1~5 구역 이동 · 이동은 게임과 동일"
	var view := _scene.get_node("StoreView3D")
	view.mode = StoreView3D.Mode.OVERLAY
	_teleport(0)
	var args := OS.get_cmdline_user_args()
	var i_season := args.find("--season")
	if i_season >= 0 and i_season + 1 < args.size():
		view.season_override = args[i_season + 1]
	var i_weather := args.find("--weather")
	if i_weather >= 0 and i_weather + 1 < args.size():
		view.weather_override = args[i_weather + 1]
		view.weather["kind"] = args[i_weather + 1]
		view.weather["intensity"] = view.weather_override_intensity
		if args[i_weather + 1] == "rain":
			view.wetness = view.weather_override_intensity
	var i_shot := args.find("--shot")
	if i_shot >= 0 and i_shot + 1 < args.size():
		await _shots(args[i_shot + 1], view)

func _open_all() -> void:
	for group_name in ResidentStoryFlow.SETTINGS.managed_groups:
		var group := _scene.get_node_or_null(NodePath(group_name))
		if group == null:
			continue
		for obj in group.get_children():
			if obj is StaticBody2D and not bool(obj.get_meta("settlement_layout_removed", false)):
				obj.visible = true
				obj.collision_layer = 1

func _teleport(i: int) -> void:
	var spot: Array = SPOTS[i]
	_player.global_position = _terrain.to_global(_terrain.grid_to_local(spot[1]))
	var cam: Camera2D = _player.get_node("Camera2D")
	cam.zoom = Vector2(0.55, 0.55)
	cam.position = Vector2(0, -60)
	_label.text = "%s · F10 3D 전환 · 1~5 구역 이동" % spot[0]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode - KEY_1
		if k >= 0 and k < SPOTS.size():
			_teleport(k)

func _shots(dir: String, view: Node) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in range(SPOTS.size()):
		_teleport(i)
		for m in [[StoreView3D.Mode.OFF, "2d"], [StoreView3D.Mode.OVERLAY, "ov"], [StoreView3D.Mode.ON, "3d"]]:
			view.mode = m[0]
			for f in range(40):
				await get_tree().process_frame
			_label.visible = false
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/spot%d_%s.png" % [dir, i + 1, m[1]])
			_label.visible = true
	get_tree().quit()
