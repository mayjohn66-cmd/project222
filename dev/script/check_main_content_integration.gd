extends Node

# Regression for the merged 3D view and seasonal expedition content.
var checks := 0
var failures := 0
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(caption)
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	get_viewport().push_input(event, true)
	await settle()
func _ready() -> void: call_deferred("verify")
func verify() -> void:
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await settle()
	var store = world.get_node("StoreView3D")
	check(store._ready_done and store._canvas.visible,"main starts with 3D store")
	await press(KEY_F10)
	await press(KEY_F9)
	check(store._canvas.visible,"removed F9/F10 do not change display")
	await press(KEY_F7)
	check(store.weather_override == "rain","F7 still controls weather")
	store._update_weather(3.0)
	check(WorldWeatherData.forecast(GameState.total_day,12.0)["kind"] == "rain","expedition shares store weather override")
	await press(KEY_F7)
	store._update_weather(3.0)
	check(WorldWeatherData.forecast(GameState.total_day,12.0)["kind"] == "snow","expedition shares snow override")
	await press(KEY_F7)
	await press(KEY_F7)
	store._update_weather(3.0)
	world.queue_free()
	await settle()
	WeatherSystem.debug_kind = ""
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await settle()
	inst.prep_panel.show_departure_choice()
	inst.prep_panel.show()
	inst.prep_panel.map_content._select_region("forest")
	inst.start_expedition_run()
	await settle()
	check(ExpeditionMapData.get_region_ids().size() == 6,"all six regions integrated")
	for region in ExpeditionMapData.get_region_ids():
		inst.current_region_id = region
		var profile: Dictionary = ExpeditionRoomModel.CONTENT.region_profile(region)
		var indoor: bool = profile["floor"] == "paving"
		var spring_floor: Color
		for season in ["spring","winter"]:
			var environment := {"day":1 if season == "spring" else 85,"hour":12.0,"season":season,"weather":"snow" if season == "winter" else "rain"}
			inst.expedition_map.environment = environment.duplicate(true)
			var candidates := ExpeditionEventData.get_events_by_node_type(region,"gather",1,environment)
			check(not candidates.is_empty(),"gather event exists: " + region + "/" + season)
			if candidates.is_empty(): continue
			inst.expedition_room_controller.enter(candidates[0],"gather")
			await settle()
			var room = inst.expedition_room_controller.view
			var stage = room.stage
			check(room.use_3d and stage.active and stage._built_model == room.model,"native 3D stage built for " + region)
			check(room.region_id == region and room.title_label.text.contains(ExpeditionEnvironment.label(environment)),"region and environment shown together")
			check(room.weather_overlay.environment["indoors"] == indoor and room.weather_overlay.environment["weather"] == environment["weather"],"weather overlay respects floor/arrival environment")
			check(stage._object_nodes.size() == room.model.gathering_sites.size() or room.model.gathering_sites.is_empty(),"3D gather nodes match actual sites")
			if season == "spring": spring_floor = stage._theme["floor_tint"]
			else: check((stage._theme["floor_tint"] == spring_floor) == indoor,"season changes outdoor 3D floor only")
			if region == "river_valley": check(stage._theme_id == "swamp","valley uses waterside scenery")
			var player_position: Vector2 = room.model.player_position
			var elapsed: float = room.weather_overlay.elapsed
			inst.game_menu.menu_open = true
			room._physics_process(0.5)
			room.weather_overlay._process(0.5)
			check(room.model.player_position == player_position and room.weather_overlay.elapsed == elapsed,"menu pauses room and weather")
			inst.game_menu.menu_open = false
			inst.expedition_room_controller._close()
			await settle()
	# Seasonal resources keep their actual names in the 3D room's interaction captions.
	inst.current_region_id = "river_valley"
	inst.expedition_map.environment = {"day":85,"hour":12.0,"season":"winter","weather":"snow"}
	var winter_events := ExpeditionEventData.get_events_by_node_type("river_valley","gather",1,inst.expedition_map.environment)
	for event in winter_events:
		if event["event_id"] != "river_valley_frostling_gather": continue
		inst.expedition_room_controller.enter(event,"gather")
		await settle()
		var room = inst.expedition_room_controller.view
		check(str(room.model.gathering_sites[0]["label"]).contains("서리 얼음"),"current frost name shown in seasonal gathering")
		check(room.stage._object_nodes.size() == 1,"seasonal gathering visible in 3D")
	inst.queue_free()
	await settle()
	print("CHECK_MAIN_CONTENT_INTEGRATION checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
