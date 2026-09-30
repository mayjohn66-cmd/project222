class_name ExpeditionRoomTestDriver
extends RefCounted

# 검증 전용: 실제 이동/공격/상호작용 API만 호출한다. HP/위치/드롭을 고치지 않는다.
static func play(controller: ExpeditionRoomController) -> bool:
	controller.view.set_physics_process(false)
	var room := controller.model
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
					movement = toward
				else:
					attacking = true
		elif not room.object_kind.is_empty() and not room.object_consumed:
			if room.player_position.distance_to(room.object_position) > room.settings.interaction_reach * 0.75:
				movement = (room.object_position - room.player_position).normalized()
			else:
				room.interact()
		else:
			if room.player_position.distance_to(room.exit_position) > room.settings.interaction_reach * 0.75:
				movement = (room.exit_position - room.player_position).normalized()
			else:
				room.interact()
		room.step(1.0 / 60.0, movement, attacking)
		if steps % 120 == 0:
			await controller.view.get_tree().process_frame
	# 보스 처치 뒤 지연된 결과 전환을 기다린다.
	await controller.view.get_tree().process_frame
	controller.view.set_physics_process(true)
	if controller.is_active():
		print("[방 막힘] steps=", steps, " 위치=", room.player_position, " 적=", room.alive_enemies())
	return not controller.is_active() and room.player_hp > 0
