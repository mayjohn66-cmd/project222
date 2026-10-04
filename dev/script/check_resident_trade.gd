extends Node
var failures := 0
var world

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(6): await get_tree().process_frame

func click(button: Button) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await settle()

func _ready() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # Post-tutorial fixture; opening is tested separately.
	add_child(world)
	await settle()
	var trade: ResidentTradeDirector = world.get_node("ResidentTradeDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	check(not ResidentTradeFlow.available() and ResidentTradeFlow.exchange("grain").is_empty(), "no trade before settlement")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	check(not ResidentTradeFlow.available(), "settlement requires first greeting before trade")
	VillageLifeFlow.greet("naru")
	VillageSettlement.apply_world(world)
	await settle()
	var stall := VillageSettlement.find_site(world, ResidentTradeFlow.SETTINGS.site)
	player.set_physics_process(false)
	player.global_position = stall.global_position + Vector2(60,0)
	manager.hour_timer.paused = false
	check(not trade.interaction_hint().is_empty(), "stall shows trade hint")
	check(world.get_node("WorldInteractions").try_interact() and trade.open, "existing E interaction opens stall")
	check(manager.hour_timer.paused and world.get_node("WorldInteractions").blocked(), "trade blocks conflicting interaction and pauses clock")
	await settle()
	for dimensions in [Vector2i(1152,648),Vector2i(593,523),Vector2i(800,450)]:
		get_window().size = dimensions
		await settle()
		check(get_viewport().get_visible_rect().encloses(trade.panel.root.get_global_rect()), "trade panel fits screen")
		check(trade.panel.root.get_global_rect().encloses(trade.panel.close_button.get_global_rect()), "close remains visible")
	get_window().size = Vector2i(1152,648)
	await settle()
	GameState.remove_item("dry_branch", GameState.get_item_count("dry_branch"))
	var wheat_before: int = GameState.get_item_count("wheat")
	check(ResidentTradeFlow.exchange("grain").is_empty() and ResidentTradeFlow.used("grain") == 0, "missing materials cannot consume daily stock")
	GameState.add_item("dry_branch", 12)
	trade.panel.refresh()
	await settle()
	var money_before: int = GameState.get_money()
	var reputation_before := ResidentRequestFlow.reputation()
	await click(trade.panel.cards["grain"]["action"])
	check(ResidentTradeFlow.used("grain") == 1 and GameState.get_item_count("dry_branch") == 9 and GameState.get_item_count("wheat") == wheat_before + 2, "actual button exchanges exact quantities")
	var saved := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(ResidentTradeFlow.used("grain") == 1, "save reload preserves daily trade count")
	ResidentTradeFlow.exchange("grain")
	check(ResidentTradeFlow.remaining("grain") == 0 and ResidentTradeFlow.exchange("grain").is_empty(), "daily limit prevents extra trades")
	check(GameState.get_money() == money_before and ResidentRequestFlow.reputation() == reputation_before, "trade does not grant money or reputation")
	check(ResidentTradeFlow.used("mushroom") == 0, "daily stock is separate per offer")
	GameState.add_item("stone_shard", 6)
	check(ResidentTradeFlow.exchange("iron").is_empty(), "advanced trade requires relationship")
	for i in range(2):
		GameState.total_day += 1
		VillageLifeFlow.greet("naru")
	check(ResidentTradeFlow.remaining("grain") == 2, "next game day restocks offers")
	check(not ResidentTradeFlow.exchange("iron").is_empty(), "third greeting day unlocks iron exchange")
	trade.panel.refresh()
	await settle()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape,true)
	await settle()
	check(not trade.open and not manager.hour_timer.paused and not player.is_physics_processing(), "Escape restores exact clock and movement state")
	check(not world.has_meta("resident_trade_open") and not world.get_node("UI/GameMenu").menu_open, "close clears modal and does not open game menu")
	world.get_node("BuildManager").build_mode = true
	check(not trade.try_interact(), "building blocks trade")
	world.get_node("BuildManager").build_mode = false
	var editor = world.get_node("VillageMapEditor")
	editor.active = true
	check(not trade.try_interact(), "map editing blocks trade")
	editor.active = false
	world.get_node("StoreExterior").refresh_village_layout()
	await settle()
	check(ResidentTradeFlow.used("iron") == 1, "exterior rebuild does not restock")
	check(ResidentTradeFlow.exchange("invalid").is_empty(), "unknown offer cannot change inventory")
	PlayerProgress.reset()
	check(not ResidentTradeFlow.available() and ResidentTradeFlow.used("iron") == 0, "new game clears relationship and trade history")
	print("CHECK_RESIDENT_TRADE failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
