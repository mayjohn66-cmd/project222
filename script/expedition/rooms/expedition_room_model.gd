class_name ExpeditionRoomModel
extends RefCounted

signal object_used
signal enemies_cleared
signal exited
signal defeated

var settings: ExpeditionRoomSettings
var attack_profile: ExpeditionAttackProfile
var loadout: ExpeditionWeaponLoadout = null
var base_attack: int = 12
var player_position := Vector2(3.5, 7.0)
var facing := Vector2.UP
var exit_position := Vector2(3.5, 0.5)
var player_hp: int = 100
var player_max_hp: int = 100
var player_attack: int = 12
var player_defense: int = 3
var enemies: Array[Dictionary] = []
var obstacles: Array[Rect2] = []
var projectiles: Array[Dictionary] = []
var feedback: Array[Dictionary] = []
var object_position := Vector2(5.5, 3.5)
var object_kind: String = ""
var object_consumed: bool = false
var interaction_progress: float = 0.0
var interacting: bool = false
var exit_open: bool = false
var finished: bool = false
var attack_remaining: float = 0.0
var attack_flash: float = 0.0
var hurt_remaining: float = 0.0
var elapsed: float = 0.0

func setup(config: ExpeditionRoomSettings, profile: ExpeditionAttackProfile,
		hp: int, max_hp: int, attack: int, defense: int,
		enemy: Dictionary, difficulty: int, boss: bool, kind: String,
		weapon_loadout: ExpeditionWeaponLoadout = null) -> void:
	settings = config
	attack_profile = profile
	loadout = weapon_loadout
	# attack에는 처음 든 무기의 보너스가 포함돼 있으므로 뺀 값이 맨몸 공격력이다.
	base_attack = attack - (loadout.active_bonus() if loadout != null else 0)
	player_hp = hp
	player_max_hp = max_hp
	player_attack = attack
	player_defense = defense
	object_kind = kind
	# 열린 통로를 유지하는 작은 배치 변형. 시작/출구/오브젝트와 겹치지 않는다.
	var row: int = randi_range(3, 5)
	obstacles = [Rect2(1, row, 1, 1), Rect2(6, row, 1, 1)]
	if not enemy.is_empty():
		var count: int = 1 if boss else settings.ordinary_enemy_count
		for i in range(count):
			var max_enemy_hp: int = maxi(1, roundi(float(enemy.get("max_hp", 1))
				* ExpeditionDifficultyData.get_monster_hp_mult(difficulty)))
			enemies.append({
				"position": Vector2(4.0, 2.0) if boss else Vector2(2.5 + i * 2.5, 2.0),
				"hp": max_enemy_hp, "max_hp": max_enemy_hp,
				"attack": maxi(1, roundi(float(enemy.get("attack", 1))
					* ExpeditionDifficultyData.get_monster_atk_mult(difficulty))),
				"defense": int(enemy.get("defense", 0)), "boss": boss,
				"name": str(enemy.get("name", "몬스터")),
				"cooldown": 0.0, "windup": -1.0, "target": Vector2.ZERO
			})
	exit_open = enemies.is_empty()

func step(delta: float, movement: Vector2, attacking: bool) -> void:
	if finished:
		return
	elapsed += delta
	attack_remaining = maxf(0.0, attack_remaining - delta)
	attack_flash = maxf(0.0, attack_flash - delta)
	hurt_remaining = maxf(0.0, hurt_remaining - delta)
	for note in feedback:
		note["life"] -= delta
	feedback = feedback.filter(func(note: Dictionary) -> bool: return float(note["life"]) > 0.0)
	if movement.length_squared() > 0.0:
		facing = movement.normalized()
		player_position = move_actor(player_position, facing * settings.player_speed * delta)
		interacting = false
		interaction_progress = 0.0
	if attacking:
		basic_attack()
	_step_projectiles(delta)
	for enemy in enemies:
		_step_enemy(enemy, delta)
		if finished:
			return
	if interacting:
		if player_position.distance_to(object_position) > settings.interaction_reach:
			interacting = false
			interaction_progress = 0.0
		else:
			interaction_progress += delta
			if interaction_progress >= settings.gathering_seconds:
				object_consumed = true
				interacting = false
				object_used.emit()

func move_actor(origin: Vector2, offset: Vector2) -> Vector2:
	var candidate := origin
	# 축을 나눠 벽을 따라 미끄러질 수 있게 한다.
	for axis in [0, 1]:
		var next := candidate
		next[axis] += offset[axis]
		next[axis] = clampf(next[axis], settings.actor_radius,
			ExpeditionRoomSettings.GRID_SIZE - settings.actor_radius)
		var blocked := false
		for obstacle in obstacles:
			if obstacle.grow(settings.actor_radius).has_point(next):
				blocked = true
				break
		if not blocked:
			candidate = next
	return candidate

func _wall_between(from: Vector2, to: Vector2) -> bool:
	for obstacle in obstacles:
		var corners: Array[Vector2] = [obstacle.position, obstacle.position + Vector2(obstacle.size.x, 0),
			obstacle.end, obstacle.position + Vector2(0, obstacle.size.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(from, to, corners[i], corners[(i + 1) % 4]) != null:
				return true
	return false

# 들고 있는 무기를 바꾼다. 공격 방식과 공격 보너스가 함께 바뀌고, 쿨다운은 이어지며 교체 지연이 붙는다.
func swap_weapon() -> bool:
	if finished or loadout == null or not loadout.swap():
		return false

	attack_profile = loadout.active_profile()
	player_attack = base_attack + loadout.active_bonus()
	attack_remaining = maxf(attack_remaining, settings.weapon_swap_delay)
	projectiles.clear()
	feedback.append({"position": player_position, "text": loadout.active_name(), "life": 0.6})
	return true


func basic_attack() -> bool:
	if finished or attack_remaining > 0.0:
		return false
	attack_remaining = attack_profile.cooldown
	attack_flash = 0.12
	interacting = false
	interaction_progress = 0.0
	if attack_profile.method == ExpeditionAttackProfile.Method.PROJECTILE:
		projectiles.append({"position": player_position, "direction": facing,
			"remaining": attack_profile.reach, "hits": 0, "hit_ids": []})
		return true
	var hits := 0
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var offset: Vector2 = enemy["position"] - player_position
		if offset.length() > attack_profile.reach:
			continue
		if absf(facing.angle_to(offset)) > deg_to_rad(attack_profile.arc_degrees * 0.5):
			continue
		if _wall_between(player_position, enemy["position"]):
			continue
		_hit_enemy(enemy, facing)
		hits += 1
		if hits >= attack_profile.max_targets:
			break
	return true

func _hit_enemy(enemy: Dictionary, direction: Vector2) -> void:
	var damage: int = mini(int(enemy["hp"]), maxi(1, player_attack - int(enemy["defense"])))
	enemy["hp"] = maxi(0, int(enemy["hp"]) - damage)
	enemy["position"] = move_actor(enemy["position"], direction * attack_profile.knockback)
	player_hp = mini(player_max_hp, player_hp + roundi(damage * attack_profile.heal_fraction))
	feedback.append({"position": enemy["position"], "text": str(damage), "life": 0.5})
	if alive_enemies() == 0 and not exit_open:
		exit_open = true
		enemies_cleared.emit()

func _step_projectiles(delta: float) -> void:
	for shot in projectiles:
		var origin: Vector2 = shot["position"]
		var distance: float = minf(float(shot["remaining"]), attack_profile.projectile_speed * delta)
		var next: Vector2 = origin + shot["direction"] * distance
		if _wall_between(origin, next) or not Rect2(0, 0, 8, 8).has_point(next):
			shot["remaining"] = 0.0
			continue
		shot["position"] = next
		shot["remaining"] -= distance
		for i in range(enemies.size()):
			var enemy: Dictionary = enemies[i]
			if int(enemy["hp"]) <= 0 or shot["hit_ids"].has(i):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(enemy["position"], origin, next)
			if closest.distance_to(enemy["position"]) <= settings.actor_radius:
				shot["hit_ids"].append(i)
				_hit_enemy(enemy, shot["direction"])
				shot["hits"] += 1
				if int(shot["hits"]) >= attack_profile.max_targets:
					shot["remaining"] = 0.0
					break
	projectiles = projectiles.filter(func(shot: Dictionary) -> bool: return float(shot["remaining"]) > 0.0)

func _step_enemy(enemy: Dictionary, delta: float) -> void:
	if int(enemy["hp"]) <= 0:
		return
	var reach: float = settings.boss_reach if bool(enemy["boss"]) else settings.enemy_reach
	if float(enemy["windup"]) >= 0.0:
		enemy["windup"] -= delta
		if float(enemy["windup"]) <= 0.0:
			enemy["windup"] = -1.0
			enemy["cooldown"] = settings.enemy_cooldown
			if player_position.distance_to(enemy["target"]) <= reach and hurt_remaining <= 0.0 \
					and not _wall_between(enemy["position"], player_position):
				var damage: int = maxi(1, int(enemy["attack"]) - player_defense)
				player_hp = maxi(0, player_hp - damage)
				hurt_remaining = settings.hurt_grace
				interacting = false
				interaction_progress = 0.0
				feedback.append({"position": player_position, "text": "-%d" % damage, "life": 0.5})
				if player_hp == 0:
					finished = true
					defeated.emit()
		return
	enemy["cooldown"] = maxf(0.0, float(enemy["cooldown"]) - delta)
	var offset: Vector2 = player_position - enemy["position"]
	if offset.length() <= reach and float(enemy["cooldown"]) <= 0.0 \
			and not _wall_between(enemy["position"], player_position):
		enemy["target"] = player_position
		enemy["windup"] = settings.enemy_windup
	else:
		var offset_step := offset.normalized() * settings.enemy_speed * delta
		enemy["position"] = move_actor(enemy["position"], offset_step)

func alive_enemies() -> int:
	var count := 0
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			count += 1
	return count

func interaction_label() -> String:
	if finished:
		return ""
	if not object_kind.is_empty() and not object_consumed \
			and player_position.distance_to(object_position) <= settings.interaction_reach:
		return "채집" if object_kind == "gather" else ("휴식" if object_kind == "heal" else "열기")
	if exit_open and player_position.distance_to(exit_position) <= settings.interaction_reach:
		return "다음 방으로"
	return ""

func interact() -> void:
	var label := interaction_label()
	if label.is_empty():
		return
	if label == "다음 방으로":
		finished = true
		exited.emit()
	elif not interacting:
		interacting = true
		interaction_progress = 0.0
