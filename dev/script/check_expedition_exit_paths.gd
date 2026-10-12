extends "res://dev/script/check_expedition_sprite_art.gd"
## 지역별 자연스러운 길목과 실제 다음 방 판정이 일치하는지 확인한다.

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	view = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
	add_child(view)
	await frames()
	view.set_physics_process(false)
	view.stage.set_process(false)
	for region in ["forest","mine","swamp","hidden_ruins","meadow","river_valley"]:
		var room := model("field_slime")
		var trigger := room.exit_position
		var obstacles := room.obstacles.duplicate()
		bind(room,region)
		view.title_label.text = str(ExpeditionMapData.get_region_data(region).get("name",region))
		await frames()
		var chosen := ExpeditionRoomComposition.profile(region)
		for path in [view.stage._exit_bars,view.stage._exit_glow]:
			check(path.mesh is PlaneMesh,"flat trail instead of portal: "+region)
			check(str(path.get_meta("exit_path_kind")) == str(chosen.exit_path.kind),"regional trail material: "+region)
			check(path.get_meta("exit_trigger_position") == trigger,"same trigger position: "+region)
			check(path.position.x == trigger.x and path.position.z < trigger.y,"trail continues behind room: "+region)
			var material := path.material_override as ShaderMaterial
			for i in range(1,4):
				var texture := material.get_shader_parameter("tile_%d" % i) as Texture2D
				check(texture != null and texture.resource_path == "res://art/received/floors/%s_%d.png" % [chosen.exit_path.kind,i],"existing native tile used: "+region)
				check(material.get_shader_parameter("normal_%d" % i) != null,"normal lighting retained: "+region)
		for node in view.stage._content.get_children():
			check(str(node.get_meta("expedition_sprite_id","")) not in ["exit_open","exit_closed"],"no legacy arch in active room: "+region)
		check(room.exit_position == trigger and room.obstacles == obstacles,"view doesn't move exits or obstacles: "+region)
		check(view.stage._exit_bars.visible and not view.stage._exit_glow.visible,"unsafe trail is shown while enemies remain: "+region)
		room.player_position = trigger
		var exits := [0]
		room.exited.connect(func(): exits[0] += 1)
		room.interact()
		check(exits[0] == 0 and not room.finished,"cannot skip living enemies: "+region)
		view._physics_process(0)
		check(view.hint_label.visible and view.hint_label.text.contains("몬스터"),"nearby unsafe trail explains remaining enemies")
		view.stage._sync(room,0)
		if region in ["forest","mine"]: await capture("exit_"+region+"_unsafe")
		# Use the real shared hit/clear logic. This fixture doesn't claim continuous play.
		for enemy in room.enemies:
			while int(enemy.hp) > 0: room._hit_enemy(enemy,Vector2.UP)
		room.step(ExpeditionDamageDigits.LIFETIME + 0.1,Vector2.ZERO,false)
		view._physics_process(0)
		view.stage._sync(room,0)
		check(room.exit_open and view.stage._exit_glow.visible and not view.stage._exit_bars.visible,"real clearing unlocks trail: "+region)
		await capture("exit_"+region+"_open")
		room.interact()
		check(exits[0] == 1 and room.finished,"actual interaction exits once at visible trail: "+region)
		room.interact()
		check(exits[0] == 1,"no repeated exit: "+region)
	print("[원정 길목] 검사 ",checks," / 실패 ",failures)
	get_tree().quit(1 if failures > 0 else 0)
