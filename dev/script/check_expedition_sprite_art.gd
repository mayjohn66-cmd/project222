extends Node
## 실제 방 표시와 데이터의 정지 그림 연결을 검증한다. 별도 저장 폴더에서 실행한다.
const SETTINGS := preload("res://scenes/expedition/rooms/default_room_settings.tres")
var checks := 0
var failures := 0
var view: ExpeditionRoomView

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	run.call_deferred()

func frames(count: int = 3) -> void:
	for i in count: await get_tree().process_frame

func model(id: String = "", kind: String = "", boss: bool = false) -> ExpeditionRoomModel:
	var room := ExpeditionRoomModel.new()
	var enemy := EnemyData.get_enemy(id).duplicate(true) if not id.is_empty() else {}
	if not enemy.is_empty(): enemy["id"] = id
	room.setup(SETTINGS, ExpeditionAttackProfile.new(), 80, 100, 12, 3, enemy, 1, boss, kind)
	return room

func bind(room: ExpeditionRoomModel, region: String) -> void:
	view.model = room
	view.region_id = region
	view.stage.rebuild(room, region)
	view.stage._layout()
	view.stage._sync(room, 0.016)

func verify_sprite(node: MeshInstance3D, row: Dictionary) -> void:
	check(node != null and node.get_meta("expedition_sprite_id", "") == str(row.id), "identity: " + str(row.id))
	if node == null: return
	var tex := (node.material_override as ShaderMaterial).get_shader_parameter("frame_texture") as Texture2D
	check(tex.resource_path == str(row.path), "runtime source: " + str(row.id))
	check(FileAccess.get_sha256(str(row.path)) == str(row.sha256), "source hash: " + str(row.id))
	var rect := tex.get_image().get_used_rect()
	var size: Vector2 = (node.mesh as QuadMesh).size
	check(is_equal_approx(size.x / size.y, float(rect.size.x) / rect.size.y), "uniform source aspect: " + str(row.id))
	check(node.scale == Vector3.ONE, "no axis compression: " + str(row.id))
	check((node.material_override as ShaderMaterial).get_shader_parameter("normal_texture") != null, "lit normal map: " + str(row.id))

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + name + ".png")

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	view = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
	add_child(view)
	await frames()
	view.set_physics_process(false)
	view.stage.set_process(false)
	check(view.stage._player is ExpeditionPixelPlayer, "expedition reuses selected-gender 2D player")
	view.stage._player.play_hurt(0.4)
	view.stage._player.animate(0.2)
	check(view.stage._player.hurt_amount() > 0.0, "pixel player hit feedback runs")
	view.stage._player.animate(0.3)
	check(view.stage._player.hurt_amount() == 0.0, "pixel player hit feedback expires")
	check(ExpeditionSpriteArt.assets().size() == 47, "45 prepared drawings and 2 reused gathering pictures indexed")
	for row in ExpeditionSpriteArt.assets().values():
		if str(row.group) == "monsters":
			var room := model(str(row.id), "", bool(row.boss))
			check(not room.enemies.is_empty(), "existing enemy data: " + str(row.id))
			bind(room, "forest")
			for entry in view.stage._enemy_nodes:
				check(str(entry.enemy.id) == str(row.id), "model preserves enemy ID")
				verify_sprite(entry.node, row)
				entry.enemy.windup = 0.1
			view.stage._sync(room, 0.016)
			for entry in view.stage._enemy_nodes:
				check(entry.node.scale == Vector3.ONE and entry.node.rotation == Vector3.ZERO, "attack preparation preserves pixels")
				entry.enemy.windup = -1.0
			view.stage._sync(room, 0.016)
			for entry in view.stage._enemy_nodes:
				check(entry.node.scale == Vector3.ONE, "lunge preserves pixels")
				entry.enemy.hp = 0
			room.exit_open = true
			view.stage._sync(room, 0.016)
			for entry in view.stage._enemy_nodes: check(not entry.node.visible, "defeated monster hidden")
			check(view.stage._exit_glow.visible and not view.stage._exit_bars.visible, "cleared room opens exit image")
		elif str(row.group) == "objects":
			var kind := "chest" if row.id == "treasure_chest" else ("heal" if row.id == "healing_spring" else "gather")
			var room := model("", kind)
			room.object_loot_table = str(row.get("table", ""))
			bind(room, "mine" if row.id == "mineral_outcrop" else "forest")
			verify_sprite(view.stage._object_nodes[0], row)
			# Use the existing E interaction rather than changing its consumed flag.
			room.player_position = room.object_position
			room.interact()
			room.step(room.interaction_seconds() + 0.1, Vector2.ZERO, false)
			view.stage._sync(room, 0.016)
			check(room.object_consumed and not view.stage._object_nodes[0].visible, "interaction hides used object: " + str(row.id))
		await frames(1)
	check(ExpeditionSpriteArt.object_id("gather", "") == "", "unknown gather does not claim mineral reward")
	check(ExpeditionSpriteArt.object_id("gather", "mine_gather") == "mineral_outcrop", "mixed mine event has correct drawing")
	check(ExpeditionSpriteArt.object_id("chest", "mine_gather") == "treasure_chest", "kind wins over loot table")
	# Exercise every active gathering event, including mixed tables and both choices.
	var event_file := FileAccess.open("res://data/expedition/expedition_events.csv",FileAccess.READ)
	var headers := event_file.get_csv_line()
	while not event_file.eof_reached():
		var fields := event_file.get_csv_line()
		if fields.size() != headers.size(): continue
		var event_row := {}
		for i in headers.size(): event_row[headers[i]] = fields[i]
		if event_row.node_type != "gather" or event_row.result_type != "loot": continue
		var gathering_room := model("","gather")
		gathering_room.object_loot_table = str(event_row.target_id)
		gathering_room.configure_gathering(gathering_room.CONTENT.gathering(str(event_row.event_id)))
		bind(gathering_room,str(event_row.region_id))
		for i in view.stage._object_nodes.size():
			var table := str(gathering_room.object_loot_table) if gathering_room.gathering_sites.is_empty() else str(gathering_room.gathering_sites[i].table)
			var selected_id := ExpeditionSpriteArt.object_id("gather",table)
			check(not selected_id.is_empty(),"every actual gathering table has a picture: "+table)
			var selected := view.stage._object_nodes[i] as MeshInstance3D
			check(selected != null,"no fallback model in gathering event: "+str(event_row.event_id))
			if selected != null and not selected_id.is_empty(): verify_sprite(selected,ExpeditionSpriteArt.assets()[selected_id])
		await frames(1)
	event_file.close()
	for table in ["choice_wild_berry","choice_stone_shard","forest_gather","swamp_gather","ruins_gather","meadow_gather","river_gather","gather_iron"]:
		var gathering_room := model("","gather")
		gathering_room.object_loot_table = table
		var capture_regions := {"choice_wild_berry":"forest","choice_stone_shard":"mine",
			"forest_gather":"forest","swamp_gather":"swamp","ruins_gather":"hidden_ruins",
			"meadow_gather":"meadow","river_gather":"river_valley","gather_iron":"mine"}
		bind(gathering_room,str(capture_regions[table]))
		await capture("gather_"+table)
	# Both table-selected gathering sites must keep their corresponding image and position.
	var sites := model("", "gather")
	sites.configure_gathering([{"table":"gather_water","x":2.5,"y":3.5,"color":"85bad4"}, {"table":"choice_forest_herb","x":5.5,"y":3.5,"color":"85bad4"}])
	bind(sites, "forest")
	check(view.stage._object_nodes.size() == 2, "both gathering choices shown")
	for i in view.stage._object_nodes.size():
		check(view.stage._object_nodes[i].position == Vector3(float(sites.gathering_sites[i].x),0,float(sites.gathering_sites[i].y)), "original site coordinates retained")
	# Gate, ruins column, and static torches are placed by the live scenery builder.
	var ruins := model("ancient_guardian", "", true)
	bind(ruins, "hidden_ruins")
	await frames(1) # rebuild queues previous room nodes for deletion.
	verify_sprite(view.stage._exit_bars, ExpeditionSpriteArt.assets().exit_closed)
	verify_sprite(view.stage._exit_glow, ExpeditionSpriteArt.assets().exit_open)
	check(not view.stage._exit_glow.visible and view.stage._exit_bars.visible, "occupied room closes exit image")
	var columns := 0
	var torches := 0
	for node in view.stage._content.get_children():
		var id := str(node.get_meta("expedition_sprite_id", ""))
		if id == "broken_column": columns += 1
		if id == "wall_torch": torches += 1
		if id in ["broken_column", "wall_torch"]: verify_sprite(node, ExpeditionSpriteArt.assets()[id])
	check(columns == ruins.obstacles.size(), "all ruin collision columns use prepared drawing")
	check(torches == 2 and view.stage._torches.size() >= 2, "two visible static torches have live lights: %d sprites / %d lights" % [torches,view.stage._torches.size()])
	await capture("expedition_ruins_boss")
	for pair in [["field_slime","forest"],["mine_golem","mine"],["river_crab","river_valley"],["meadow_guardian","meadow"]]:
		bind(model(pair[0], "", pair[0].ends_with("guardian") or pair[0]=="mine_golem"), pair[1])
		await capture("expedition_" + pair[1])
	var winter := model("", "gather")
	winter.object_loot_table = "climate_winter_frost"
	view.weather_overlay.environment = {"season":"winter", "weather":"snow"}
	bind(winter, "forest")
	await capture("expedition_winter_gather")
	var icons = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/fishing_item_assets.json"))
	check(icons.assets.size() == 20, "20 fishing icons indexed")
	for row in icons.assets:
		var icon := ItemData.get_item_icon(str(row.id)) as Texture2D
		check(icon != null and icon.resource_path == str(row.path), "actual item catalog loads icon: " + str(row.id))
		check(FileAccess.get_sha256(str(row.path)) == str(row.sha256), "installed icon hash: " + str(row.id))
		check(FileAccess.get_sha256("res://" + str(row.source)) == str(row.source_sha256), "received original preserved")
	# Exercise the actual encounter renderer for every configured role without changing unlocks.
	var controller := ExpeditionRoomController.new()
	controller.view = view
	controller.model = view.model
	var contact := ExpeditionContactRoom.new()
	contact.controller = controller
	controller.contact = contact
	view.add_child(contact)
	for entry in ExpeditionContactFlow.SETTINGS.events:
		contact.entry = entry.duplicate(true)
		contact.position = Vector2(2.5, 4.5)
		contact._process(0.016)
		check(contact.figure is PixelActorFigure, "actual expedition contact uses prepared role sprite: " + str(entry.id))
		if contact.figure is PixelActorFigure:
			check(contact.figure.sprite_key == CustomerTypeData.get_group_id(str(entry.type)), "encounter keeps role identity")
			check(contact.figure._material.get_shader_parameter("normal_texture") != null, "encounter normal map is lit")
		contact.clear()
		await frames(1)
	contact.queue_free()
	print("[원정 도트 연결] 검사 ", checks, " / 실패 ", failures)
	get_tree().quit(1 if failures > 0 else 0)
