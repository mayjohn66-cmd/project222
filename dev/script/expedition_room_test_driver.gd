class_name ExpeditionRoomTestDriver
extends RefCounted

# 검증 전용: 실제 이동/공격/상호작용 API만 호출한다. HP/위치/드롭을 고치지 않는다.
static func play(controller: ExpeditionRoomController) -> bool:
	controller.view.set_physics_process(false)
	var room := controller.model
	var grid := _walk_grid(room)
	var steps := 0
	var dodge_direction := Vector2.ZERO
	while controller.is_active() and not room.finished and steps < 30000:
		steps += 1
		var movement := Vector2.ZERO
		var attacking := false
		if room.alive_enemies() > 0:
			var nearest: Dictionary = {}
			var distance := INF
			for enemy in room.enemies:
				if int(enemy["hp"]) <= 0: continue
				var d: float = room.player_position.distance_to(enemy["position"])
				if d < distance:
					nearest = enemy
					distance = d
			var toward: Vector2 = (nearest["position"] - room.player_position).normalized()
			room.facing = toward
			var danger := false
			for enemy in room.enemies:
				if int(enemy["hp"]) <= 0 or float(enemy["windup"]) < 0: continue
				danger = true
				if dodge_direction == Vector2.ZERO:
					dodge_direction = toward.rotated(PI * 0.5)
					if (room.player_position + dodge_direction * 2.2 - Vector2(4, 4)).length() \
							> (room.player_position - dodge_direction * 2.2 - Vector2(4, 4)).length():
						dodge_direction = -dodge_direction
				movement = dodge_direction
				break
			if not danger:
				dodge_direction = Vector2.ZERO
				if distance > room.attack_profile.reach * 0.85:
					movement = _walk_direction(room, nearest["position"], grid)
				else:
					attacking = true
		elif not room.object_kind.is_empty() and not room.object_consumed:
			var target := _available_object(controller)
			if target == Vector2.INF: target = room.exit_position
			if room.player_position.distance_to(target) > room.settings.interaction_reach * 0.75:
				movement = _walk_direction(room, target, grid)
			else:
				room.interact()
		else:
			if room.player_position.distance_to(room.exit_position) > room.settings.interaction_reach * 0.75:
				movement = _walk_direction(room, room.exit_position, grid)
			else:
				room.interact()
		room.step(1.0 / 60.0, movement, attacking)
		if steps % 120 == 0:
			await controller.view.get_tree().process_frame
	# 보스 처치 뒤 지연된 결과 전환을 기다린다.
	if room.finished and room.player_hp > 0 and controller.is_active():
		await controller.view.get_tree().create_timer(ExpeditionDamageDigits.FINISH_DELAY + 0.05).timeout
	await controller.view.get_tree().process_frame
	controller.view.set_physics_process(true)
	if controller.is_active():
		print("[방 막힘] steps=", steps, " 위치=", room.player_position, " 적=", room.alive_enemies())
	return not controller.is_active() and room.player_hp > 0

# Random object positions require walking around obstacles, just as a player does.
# The driver continues to use movement/attack/interact; it never teleports or removes walls.
static func _walk_grid(room: ExpeditionRoomModel) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0,0,33,33)
	grid.cell_size = Vector2.ONE * 0.25
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in range(33):
		for x in range(33):
			var at := Vector2(x,y) * 0.25
			var radius: float = room.settings.actor_radius + 0.03
			var solid: bool = at.x < radius or at.y < radius or at.x > 8-radius or at.y > 8-radius
			for obstacle in room.obstacles:
				if obstacle.grow(radius).has_point(at): solid = true
			grid.set_point_solid(Vector2i(x,y),solid)
	return grid

static func _free_cell(at: Vector2, grid: AStarGrid2D) -> Vector2i:
	var cell := Vector2i(roundi(at.x * 4),roundi(at.y * 4))
	var best := cell
	var distance := INF
	for y in range(cell.y-2,cell.y+3):
		for x in range(cell.x-2,cell.x+3):
			var candidate := Vector2i(x,y)
			if not grid.region.has_point(candidate) or grid.is_point_solid(candidate): continue
			var d := at.distance_squared_to(Vector2(candidate) * 0.25)
			if d < distance:
				best = candidate
				distance = d
	return best

static func _walk_direction(room: ExpeditionRoomModel, target: Vector2, grid: AStarGrid2D) -> Vector2:
	var origin := room.player_position
	var clear := true
	for obstacle in room.obstacles:
		var rect := obstacle.grow(room.settings.actor_radius + 0.03)
		var corners := [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(origin,target,corners[i],corners[(i+1)%4]) != null: clear = false
	if clear: return (target-origin).normalized()
	var path := grid.get_point_path(_free_cell(origin,grid),_free_cell(target,grid))
	if path.size() < 2: return (target-origin).normalized()
	return (path[1]-origin).normalized()

# Missing required tools are not an attempted roll. Walk to another site or skip,
# using the same actual bag/rules; never remove walls, move the actor or grant tools.
static func _available_object(controller: ExpeditionRoomController) -> Vector2:
	var room := controller.model
	if room.object_kind != "gather" or not room.interaction_guard.is_valid(): return room.object_position
	var sites := room.gathering_sites
	if sites.is_empty(): sites = [{"table":str(controller.event.get("target_id","")),"x":room.object_position.x,"y":room.object_position.y}]
	for site in sites:
		var rule := ExpeditionGatheringData.get_rule(str(site["table"]))
		if bool(rule.get("tool_required",false)) and controller.host.expedition_gathering_service._find_tool_placement(controller.host.expedition_bag,str(rule.get("tool_effect_id",""))).is_empty(): continue
		return Vector2(float(site["x"]),float(site["y"]))
	return Vector2.INF
