extends Node
## 눈 발자국·물웅덩이·눈사람 충돌 점검(개발용). 인자: --out <폴더> --mode snow|rain
func _ready() -> void:
	var out := ""
	var mode := "snow"
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--mode" and i + 1 < args.size():
			mode = args[i + 1]
	var scene = load("res://dev/spike3d/village_all.tscn").instantiate()
	add_child(scene)
	for i in 20: await get_tree().process_frame
	while scene._terrain == null or scene._scene == null or scene._scene.get_node_or_null("StoreView3D") == null:
		await get_tree().process_frame
	for i in 30: await get_tree().process_frame
	var view = scene._scene.get_node("StoreView3D")
	if mode == "snow":
		view.season_override = "winter"
		view.weather_override = "snow"
	else:
		view.season_override = "summer"
		view.weather_override = "rain"
		view.wetness = 1.0
	for i in 40: await get_tree().process_frame
	var p = scene._player
	var start: Vector2 = p.global_position
	for i in 80:
		p.global_position += Vector2(5, 2.5)
		await get_tree().process_frame
	for i in 12: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, mode])
	print("PRINTS ", view.decals._prints.size(), " PUDDLES ", view.decals._puddle_keys.size(), " SNOWMEN ", view.village._snow_keys.size(), " BODIES ", view.village._snow_bodies.size())
	get_tree().quit()
