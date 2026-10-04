extends Node
func _ready() -> void:
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size(): out = args[i + 1]
	var settings: ExpeditionRoomSettings = load("res://scenes/expedition/rooms/default_room_settings.tres")
	var view: ExpeditionRoomView = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
	add_child(view)
	var model := ExpeditionRoomModel.new()
	model.setup(settings, settings.default_attack, 100, 100, 12, 3, {"id": "", "name": "슬라임", "max_hp": 40, "attack": 6, "defense": 1}, 1, false, "")
	view.model = model
	for i in 12: await get_tree().process_frame
	model.hurt_remaining = 0.58
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "/hurt.png")
	get_tree().quit()
