extends Node
## 원정 방 플레이어 방향 4가지와 공격 동작 점검(개발용). 인자: --out <폴더> [--region forest]
func _ready() -> void:
	var out := ""
	var region := "forest"
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--region" and i + 1 < args.size():
			region = args[i + 1]
	var settings: ExpeditionRoomSettings = load("res://scenes/expedition/rooms/default_room_settings.tres")
	var view: ExpeditionRoomView = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
	add_child(view)
	var model := ExpeditionRoomModel.new()
	model.setup(settings, settings.default_attack, 100, 100, 12, 3, {"id": "", "name": "슬라임", "max_hp": 400, "attack": 1, "defense": 0}, 1, false, "")
	model.obstacles.clear()
	model.enemies[0]["position"] = Vector2(5.2, 4.0)
	model.enemies[1]["position"] = Vector2(0.8, 7.2)
	model.player_position = Vector2(4.0, 4.0)
	view.region_id = region
	view.model = model
	for i in 10: await get_tree().process_frame
	var dirs := {"down_right": Vector2(1, 0), "down_left": Vector2(0, 1), "up_left": Vector2(-1, 0), "up_right": Vector2(0, -1)}
	for name in dirs:
		var d: Vector2 = IsometricGrid.screen_direction(dirs[name], view.tile_size)
		model.facing = d
		for i in 14:
			model.player_position = Vector2(4.0, 4.0)
			await get_tree().process_frame
		for i in 12: await get_tree().process_frame
		_shot(view, model, "%s/face_%s.png" % [out, name])
	# 공격: 오른쪽 아래(적 쪽)를 보고 휘두른다
	var d2: Vector2 = IsometricGrid.screen_direction(Vector2(1, 0), view.tile_size)
	model.facing = d2
	model.player_position = Vector2(4.0, 4.0)
	for i in 8: await get_tree().process_frame
	model.basic_attack()
	for k in 9:
		await get_tree().create_timer(0.06).timeout
		model.player_position = Vector2(4.0, 4.0)
		_shot(view, model, "%s/atk_%02d.png" % [out, k])
	get_tree().quit()

func _shot(view, model, path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var c: Vector2 = view.stage.project(model.player_position, 0.5)
	var r := Rect2i(int(c.x) - 90, int(c.y) - 110, 180, 180)
	img.get_region(r).save_png(path)
