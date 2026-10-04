extends Node
## 원정 방 베기 궤적·적 공격·피격 연출 점검(개발용). 인자: --out <폴더> [--region mine]
func _ready() -> void:
	var out := ""
	var region := "mine"
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
	model.setup(settings, settings.default_attack, 100, 100, 12, 3, {"id": "", "name": "슬라임", "max_hp": 400, "attack": 9, "defense": 0}, 1, false, "")
	model.obstacles.clear()
	model.player_position = Vector2(3.6, 4.2)
	model.enemies[0]["position"] = Vector2(4.7, 4.2)
	model.enemies[0]["cooldown"] = 5.0
	model.enemies[1]["position"] = Vector2(0.8, 7.2)
	view.region_id = region
	view.model = model
	model.facing = Vector2(1, 0)
	for i in 12: await get_tree().process_frame
	var im0 := get_viewport().get_texture().get_image()
	var c0: Vector2 = view.stage.project(model.player_position, 0.5)
	im0.get_region(Rect2i(int(c0.x) - 140, int(c0.y) - 130, 280, 220)).save_png("%s/idle.png" % out)
	model.basic_attack()
	for k in 14:
		await get_tree().create_timer(0.025).timeout
		var img := get_viewport().get_texture().get_image()
		var c: Vector2 = view.stage.project(model.player_position, 0.5)
		img.get_region(Rect2i(int(c.x) - 140, int(c.y) - 130, 280, 220)).save_png("%s/fx_%02d.png" % [out, k])
	get_tree().quit()
