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
	var director: VillageSmithyDirector = world.get_node("VillageSmithyDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	var smithy := VillageSettlement.find_site(world, VillageSmithyFlow.SITE)
	check(smithy != null and not smithy.visible and smithy.collision_layer == 0, "smithy begins hidden without collision")
	check(not CommunityRequestFlow.accept("open_smithy") and VillageSmithyFlow.craft("rusty_sword_recipe").is_empty(), "locked smithy cannot accept request or craft")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for id in ["settle_naru", "settle_doyun"]:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + id + ":done", GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	for i in range(7):
		VillageLifeFlow.greet("doyun")
		GameState.total_day += 1
	check(not CommunityRequestFlow.accept("open_smithy"), "prior flower request is required even with friendship")
	for id in ["path_light", "flower_corner"]:
		PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + id + ":done", GameState.total_day)
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:doyun"] = 6
	check(not CommunityRequestFlow.accept("open_smithy"), "six greeting days do not unlock seven-day request")
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:doyun"] = 7
	check(CommunityRequestFlow.accept("open_smithy"), "seven days unlock smithy request")
	for item in ["iron_ore", "stone_shard", "mine_crystal"]:
		GameState.remove_item(item, GameState.get_item_count(item))
	GameState.add_item("iron_ore",5)
	var money_before: int = GameState.get_money()
	check(CommunityRequestFlow.deliver("open_smithy").is_empty() and GameState.get_item_count("iron_ore") == 5 and GameState.get_money() == money_before, "missing second material consumes nothing")
	GameState.add_item("stone_shard",4)
	var reputation_before := ResidentRequestFlow.reputation()
	check(not CommunityRequestFlow.deliver("open_smithy").is_empty(), "both materials complete request")
	check(GameState.get_item_count("iron_ore") == 0 and GameState.get_item_count("stone_shard") == 0 and GameState.get_money() == money_before + 60 and ResidentRequestFlow.reputation() == reputation_before + 1, "exact quest materials and rewards")
	check(CommunityRequestFlow.deliver("open_smithy").is_empty(), "completion cannot award twice")
	VillageSettlement.apply_world(world)
	await settle()
	check(VillageSmithyFlow.available() and smithy.visible and smithy.collision_layer > 0, "user-placed smithy opens with collision")
	check(str(smithy.get_meta("settlement_source", "")) == VillageSmithyFlow.SITE, "removed original uses user-placed copy")
	var saved := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(VillageSmithyFlow.available(), "save reload preserves smithy completion")
	player.set_physics_process(false)
	player.global_position = smithy.global_position + Vector2(0,90)
	var shape := CircleShape2D.new()
	shape.radius = 10
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform.origin = player.global_position
	query.collision_mask = 1
	check(world.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "smithy can be reached outside building collision")
	manager.hour_timer.paused = false
	check(not director.interaction_hint().is_empty() and world.get_node("WorldInteractions").try_interact() and director.open, "E opens smithy from accessible apron")
	check(manager.hour_timer.paused and world.get_node("WorldInteractions").blocked(), "smithy pauses clock and blocks other interaction")
	await settle()
	GameState.add_item("iron_ore",3)
	GameState.add_item("mine_crystal",1)
	check(VillageSmithyFlow.craft("rusty_sword_recipe").is_empty() and GameState.get_item_count("iron_ore") == 3, "unlearned recipe cannot consume materials")
	PlayerProgress.learn_recipe("rusty_sword_recipe")
	director.panel.refresh()
	await settle()
	var swords_before: int = GameState.get_item_count("rusty_sword")
	await click(director.panel.cards["rusty_sword_recipe"]["action"])
	check(GameState.get_item_count("rusty_sword") == swords_before + 1 and GameState.get_item_count("iron_ore") == 0 and GameState.get_item_count("mine_crystal") == 0, "actual mouse button crafts exact existing recipe into warehouse")
	check(VillageSmithyFlow.craft("rusty_sword_recipe").is_empty() and GameState.get_item_count("rusty_sword") == swords_before + 1, "insufficient materials prevent extra equipment")
	check(VillageSmithyFlow.craft("invalid").is_empty(), "unknown recipe cannot craft")
	for dimensions in [Vector2i(1152,648), Vector2i(593,523), Vector2i(800,450)]:
		get_window().size = dimensions
		await settle()
		check(get_viewport().get_visible_rect().encloses(director.panel.root.get_global_rect()) and director.panel.root.get_global_rect().encloses(director.panel.close_button.get_global_rect()), "twelve recipes scroll with accessible footer")
	get_window().size = Vector2i(1152,648)
	await settle()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await settle()
	check(not director.open and not manager.hour_timer.paused and not player.is_physics_processing() and not world.has_meta("village_smithy_open"), "Escape restores exact previous state")
	world.get_node("BuildManager").build_mode = true
	check(not director.try_interact(), "building blocks smithy interaction")
	world.get_node("BuildManager").build_mode = false
	world.get_node("StoreExterior").refresh_village_layout()
	await settle()
	VillageSettlement.apply_world(world)
	check(VillageSettlement.find_site(world, VillageSmithyFlow.SITE).visible, "exterior rebuild retains unlock")
	PlayerProgress.reset()
	VillageSettlement.apply_world(world)
	check(not VillageSmithyFlow.available() and not VillageSettlement.find_site(world, VillageSmithyFlow.SITE).visible, "new game clears smithy unlock")
	print("CHECK_VILLAGE_SMITHY failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
