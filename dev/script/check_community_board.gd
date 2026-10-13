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
	var director: CommunityBoardDirector = world.get_node("CommunityBoardDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	var interactions = world.get_node("WorldInteractions")
	check(not CommunityRequestFlow.board_available() and not director.try_interact(), "no community board before first settlement")
	check(not CommunityRequestFlow.accept("path_light") and CommunityRequestFlow.deliver("path_light").is_empty(), "locked request cannot award or accept")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	await settle()
	var board := VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path)
	check(board != null and board.visible and board.collision_layer > 0, "existing user-placed board opens after settlement")
	check(not CommunityRequestFlow.accept("path_light"), "friendship requirement enforced")
	VillageLifeFlow.greet("naru")
	player.set_physics_process(false)
	player.global_position = board.global_position + Vector2(50, 0)
	manager.hour_timer.paused = false
	check(not director.interaction_hint().is_empty(), "nearby board shows E hint")
	check(interactions.try_interact() and director.open and interactions.blocked(), "E opens board and blocks other interactions")
	check(manager.hour_timer.paused and not player.is_physics_processing(), "board pauses clock and movement")
	await settle()
	for dimensions in [Vector2i(1152,648), Vector2i(593,523), Vector2i(800,450)]:
		get_window().size = dimensions
		await settle()
		check(get_viewport().get_visible_rect().encloses(director.panel.root.get_global_rect()), "board stays inside viewport %s: %s" % [dimensions, director.panel.root.get_global_rect()])
		check(director.panel.root.get_global_rect().encloses(director.panel.close_button.get_global_rect()), "close button stays accessible")
	get_window().size = Vector2i(1152,648)
	await settle()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	await click(director.panel.cards["path_light"]["action"])
	check(director.request_offer.root.visible and not CommunityRequestFlow.accepted("path_light"), "board click asks for accept or decline")
	await click(director.request_offer.accept_button)
	check(CommunityRequestFlow.accepted("path_light"), "actual mouse click accepts request")
	var branches: int = GameState.get_item_count("dry_branch")
	GameState.remove_item("dry_branch", branches)
	director.panel.refresh()
	var money_before: int = GameState.get_money()
	check(CommunityRequestFlow.deliver("path_light").is_empty() and GameState.get_money() == money_before, "missing materials cannot pay")
	GameState.add_item("dry_branch", 5)
	director.panel.refresh()
	await settle()
	var reputation_before := ResidentRequestFlow.reputation()
	await click(director.panel.cards["path_light"]["action"])
	check(CommunityRequestFlow.done("path_light") and GameState.get_item_count("dry_branch") == 0, "actual button delivers warehouse materials")
	check(GameState.get_money() == money_before + 40 and ResidentRequestFlow.reputation() == reputation_before + 1, "small reward and reputation applied once")
	var lantern := VillageSettlement.find_site(world, "VillageGathering/MarketLantern")
	check(lantern.visible and lantern.collision_layer > 0, "completed request opens one existing lantern")
	check(CommunityRequestFlow.deliver("path_light").is_empty(), "repeat completion cannot pay twice")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await settle()
	check(not director.open and not manager.hour_timer.paused and not player.is_physics_processing(), "Escape closes and restores exact prior state")
	check(not world.get_node("UI/GameMenu").menu_open, "Escape close does not also open game menu")
	var saved := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(CommunityRequestFlow.done("path_light") and not CommunityRequestFlow.accept("path_light"), "completion survives save roundtrip")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_doyun:done", GameState.total_day)
	check(not CommunityRequestFlow.accept("flower_corner"), "second request waits for relationship")
	for i in range(3):
		VillageLifeFlow.greet("doyun")
		GameState.total_day += 1
	check(CommunityRequestFlow.accept("flower_corner"), "three greeting days unlock second request")
	saved = PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(CommunityRequestFlow.accepted("flower_corner"), "accepted request survives save roundtrip")
	GameState.total_day += 30
	check(CommunityRequestFlow.accepted("flower_corner"), "accepted request has no expiry")
	GameState.add_item("forest_herb", 3)
	check(not CommunityRequestFlow.deliver("flower_corner").is_empty(), "second request completes")
	VillageSettlement.apply_world(world)
	check(VillageSettlement.find_site(world,"VillageGathering/EastFlowerBed").visible, "second completion opens one flower corner")
	check(ResidentRequestFlow.completed_count() == 0 and CommunityRequestFlow.completed_count() == 2, "community requests do not inflate original customer unlock milestones")
	world.get_node("StoreExterior").refresh_village_layout()
	await settle()
	check(VillageSettlement.find_site(world,"VillageGathering/MarketLantern").visible, "rebuilding exterior preserves improvements")
	var editor = world.get_node("VillageMapEditor")
	editor.active = true
	check(not director.try_interact(), "editor blocks board")
	editor.active = false
	PlayerProgress.reset()
	VillageSettlement.apply_world(world)
	check(not CommunityRequestFlow.done("path_light") and not VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path).visible, "new game resets requests and board")
	print("CHECK_COMMUNITY_BOARD failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
