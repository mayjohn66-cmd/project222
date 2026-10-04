extends "res://tools/check_expedition_run.gd"
const CONTENT = preload("res://scenes/expedition/rooms/default_content_settings.tres")
const CONFIG = preload("res://scenes/expedition/rooms/default_room_settings.tres")
const DEPARTURE = preload("res://script/expedition/services/expedition_departure_service.gd")
const LOOT = preload("res://script/expedition/services/expedition_loot_service.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)

func settle() -> void:
	for i in range(4): await get_tree().process_frame

func reachable(room: ExpeditionRoomModel, target: Vector2) -> bool:
	var queue: Array[Vector2i] = [Vector2i(3,7)]
	var visited := {}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if visited.has(cell): continue
		visited[cell] = true
		if cell == Vector2i(target.floor()): return true
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if next.x < 0 or next.y < 0 or next.x >= 8 or next.y >= 8: continue
			var at := Vector2(cell) + Vector2(0.5,0.5)
			if room.move_actor(at,Vector2(direction)).is_equal_approx(Vector2(next) + Vector2(0.5,0.5)):
				queue.append(next)
	return false

func _ready() -> void: call_deferred("verify")

func verify() -> void:
	seed(62473)
	PlayerProgress.reset()
	GameState.remove_item("treasure_map",GameState.get_item_count("treasure_map"))
	var ids := ExpeditionMapData.get_region_ids()
	check(ids.size() == 6,"six destinations registered")
	var ordinary := 0
	for id in ids:
		if ExpeditionMapData.get_region_data(id)["entry_item_id"].is_empty(): ordinary += 1
	check(ordinary == 5 and not ExpeditionMapData.can_enter_region("hidden_ruins"),"five ordinary destinations and one map-gated ruin")
	var departure = DEPARTURE.new()
	var money_before: int = GameState.money
	for region in ["meadow","river_valley"]:
		check(ExpeditionMapData.can_enter_region(region),"new region available without consumable: " + region)
		var types := ExpeditionMapData.get_required_event_node_types(region)
		check(types.size() == 5 and ExpeditionMapData.has_valid_region_nodes(region),"new region has every node type and boss: " + region)
		for day in range(7):
			check(ExpeditionEventData.get_missing_event_node_types(region,types,day).is_empty() and ExpeditionEventData.get_invalid_region_event_ids(region,types,day).is_empty(),"all events valid every weekday: " + region + "/" + str(day))
		check(not departure.prepare_departure(region,1,2)["success"],"higher difficulty initially locked: " + region)
		for level in range(1,5):
			if level > 1: PlayerProgress.record_clear(region,level - 1)
			var prepared: Dictionary = departure.prepare_departure(region,1,level)
			check(prepared["success"] and prepared["map"].region_id == region and prepared["map"].difficulty == level,"real departure generates requested region/difficulty: " + region + "/" + str(level))
			for kind in types:
				for event in ExpeditionEventData.get_events_by_node_type(region,kind,1):
					var table := str(event["target_id"])
					if event["result_type"] == "battle": table = EnemyData.get_loot_table(table)
					if event["result_type"] in ["battle","loot"]:
						var rolled := ExpeditionEventData.get_random_loot(table,1.0,level)
						check(not rolled.is_empty() and ItemData.has_item(str(rolled.get("item_id",""))),"valid loot at requested level: " + str(event["event_id"]) + "/" + str(level))
		var profile := CONTENT.region_profile(region)
		check(profile["floor"] == "grass" and profile["layouts"].size() == 2,"existing floor and two distinct room layouts: " + region)
		var sites := CONTENT.gathering(region + "_gather_choice")
		check(sites.size() == 2,"two gathering choices: " + region)
		for layout in profile["layouts"]:
			var room := ExpeditionRoomModel.new()
			room.setup(CONFIG,CONFIG.default_attack,100,100,12,3,{},1,false,"gather")
			var single := profile.duplicate(true)
			single["layouts"] = [layout]
			room.configure_region(single)
			check(reachable(room,room.exit_position),"collision-aware path reaches exit: " + region)
			for index in range(2):
				var site: Dictionary = sites[index]
				var at := Vector2(float(site["x"]),float(site["y"]))
				check(reachable(room,at),"collision-aware path reaches choice: " + str(site["label"]))
				var sample := ExpeditionRoomModel.new()
				sample.setup(CONFIG,CONFIG.default_attack,100,100,12,3,{},1,false,"gather")
				sample.configure_region(single)
				sample.configure_gathering(sites)
				sample.player_position = at
				sample.interact()
				sample.step(sample.interaction_seconds() + 0.01,Vector2.ZERO,false)
				check(sample.object_consumed and sample.selected_loot_table == site["table"],"E selects actual nearby gathering table: " + str(site["label"]))
		var before: int = PlayerProgress.get_cleared_difficulty(region)
		var saved := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(saved)
		check(PlayerProgress.get_cleared_difficulty(region) == before,"new region progress survives old save structure: " + region)
	check(GameState.money == money_before and GameState.get_item_count("treasure_map") == 0,"ordinary departure consumes no money or map")
	check(PlayerProgress.get_cleared_difficulty("forest") == 0 and PlayerProgress.get_cleared_difficulty("mine") == 0,"new region clear records do not unlock old regions")
	var gather := ExpeditionGatheringService.new()
	check(not gather.resolve_gathering("gather_water",{"placements":[]},LOOT.new())["gathered"],"river water retains tool requirement")
	var water: Dictionary = gather.resolve_gathering("gather_water",{"placements":[{"item_id":"gathering_bottle","enhancement_level":0}]},LOOT.new())
	check(water["gathered"] and water["item_id"] == "raw_water","actual water tool collects native raw water")
	await verify_map()
	PlayerProgress.reset()
	# 공통 검사와 같은 실제 경로. 위치/HP/보상은 고치지 않고 이동·공격·E로 보스까지 진행한다.
	for region in ["meadow","river_valley"]:
		for level in [1,2]:
			for repeat in range(2): await _run_once(region,level)
	check(report["runs"] == 8 and report["clears"] == 8 and report["stuck"] == 0,"all eight new-dungeon runs reach results without getting stuck")
	check(report["boss_had_starter"] == 8 and report["starter_before_boss"] == 0,"starter scroll remains a first-boss reward in new regions")
	print("CHECK_ADDED_DUNGEONS checks=",checks," failures=",failures," report=",report)
	get_tree().quit(0 if failures == 0 else 1)

func verify_map() -> void:
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await settle()
	var prep = inst.prep_panel
	prep.show_departure_choice()
	prep.show()
	var map = prep.map_content
	check(map.region_buttons.size() == 6,"all six real map buttons exist")
	for resolution in [Vector2i(768,432),Vector2i(1152,648),Vector2i(1600,900)]:
		get_tree().root.size = resolution
		await settle()
		prep.select_tab(0)
		for id in map.region_buttons:
			var button: Button = map.region_buttons[id]
			var bounds := button.get_global_rect()
			var label: Label = button.get_node("RegionName")
			# canvas_items 스트레치에서는 전역 Control 좌표도 논리 뷰포트 단위다.
			var viewport_bounds: Rect2 = map.get_viewport_rect()
			check(button.visible and viewport_bounds.encloses(bounds) and viewport_bounds.encloses(label.get_global_rect()),"map marker and name fit viewport: " + str(id) + "/" + str(resolution))
			for other in map.region_buttons:
				if str(other) <= str(id): continue
				check(not bounds.intersects(map.region_buttons[other].get_global_rect()),"map hit regions do not overlap: " + str(id) + "/" + str(other))
	get_tree().root.size = Vector2i(1152,648)
	for id in ["meadow","river_valley"]:
		prep.show_departure_choice()
		map.region_buttons[id].pressed.emit()
		await settle()
		check(prep.get_selected_region_id() == id and prep.region_name_label.text == ExpeditionMapData.get_region_data(id)["name"] and prep.start_button.visible,"real map click opens departure card: " + id)
		check(map.region_buttons[id].get_node("RegionName").text == ExpeditionMapData.get_region_data(id)["name"],"reused icon has distinct visible destination name: " + id)
	inst.queue_free()
	await settle()
