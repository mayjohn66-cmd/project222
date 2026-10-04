extends Node
## 원정 던전 방 3D 점검(개발용). 인자: --out <폴더> [--regions forest,mine,swamp,hidden_ruins]
func _ready() -> void:
	var out := ""
	var regions: PackedStringArray = ["forest", "mine", "swamp", "hidden_ruins"]
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--regions" and i + 1 < args.size():
			regions = args[i + 1].split(",")
	var settings: ExpeditionRoomSettings = load("res://scenes/expedition/rooms/default_room_settings.tres")
	var view: ExpeditionRoomView = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
	add_child(view)
	var n := 0
	for region in regions:
		var model := ExpeditionRoomModel.new()
		var enemy := {"id": "", "name": "슬라임", "max_hp": 40, "attack": 6, "defense": 1}
		var kind: String = ["chest", "gather", "heal", ""][n % 4]
		model.setup(settings, settings.default_attack, 100, 100, 12, 3, enemy, 1, n == 3, kind)
		view.region_id = region
		view.model = model
		view.title_label.text = region
		for i in 8: await get_tree().process_frame
		# 플레이어를 몇 걸음 걷게 한 뒤 촬영
		for i in 30:
			model.step(0.05, Vector2(0.6, -0.8), false)
			await get_tree().process_frame
		for i in 6: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/stage_%s.png" % [out, region])
		n += 1
	get_tree().quit()
