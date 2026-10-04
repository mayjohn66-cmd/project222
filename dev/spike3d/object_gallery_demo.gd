extends Node
## 원정 오브젝트 모양 점검(개발용): 한 방에 모든 종류를 늘어놓고 확대해서 찍는다. 인자: --out <폴더> [--region forest]
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
	model.setup(settings, settings.default_attack, 100, 100, 12, 3, {"id": "", "name": "슬라임", "max_hp": 40, "attack": 6, "defense": 1}, 1, false, "")
	model.obstacles.clear()
	model.enemies.clear()
	view.region_id = region
	view.model = model
	for i in 8: await get_tree().process_frame
	var st: ExpeditionStage3D = view.stage
	var tables := ["choice_forest_herb", "choice_wild_berry", "choice_iron_ore", "choice_stone_shard", "choice_swamp_moss", "choice_marsh_reed", "choice_ancient_fragment", "choice_rune_dust"]
	var n := 0
	for t in tables:
		var o: Node3D = st._make_object("gather_site", t, Vector2(1.2 + float(n % 4) * 1.8, 2.4 + float(n / 4) * 2.6), Color("ffffff"))
		n += 1
	var o1: Node3D = st._make_object("chest", "", Vector2(3.0, 6.6), Color.WHITE)
	var o2: Node3D = st._make_object("heal", "", Vector2(5.4, 6.6), Color.WHITE)
	model.player_position = Vector2(7.2, 7.2)
	for i in 14: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/objects_%s.png" % [out, region])
	get_tree().quit()
