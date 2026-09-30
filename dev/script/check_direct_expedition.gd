extends Node

const CONFIG = preload("res://scenes/expedition/rooms/default_room_settings.tres")
var failures: Array[String] = []

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func room(enemy: Dictionary = {}, profile: ExpeditionAttackProfile = CONFIG.default_attack) -> ExpeditionRoomModel:
	var result := ExpeditionRoomModel.new()
	result.setup(CONFIG, profile, 100, 100, 12, 3, enemy, 1, false, "gather")
	return result

func _ready() -> void:
	var model := room()
	model.step(1.0, Vector2.UP, false)
	expect(model.player_position.y < 7.0, "이동 입력이 위치를 바꿔야 함")
	expect(model.move_actor(Vector2(0.5, 0.5), Vector2(-3, -3)).x >= CONFIG.actor_radius - 0.00001, "방 밖 이동 제한")
	var wall := model.obstacles[0]
	var origin := wall.position - Vector2(0.5, -0.5)
	expect(model.move_actor(origin, Vector2(1, 0)) == origin, "장애물 충돌")
	model.interact()
	expect(not model.interacting and not model.object_consumed, "멀리 있는 자원 채집 금지")
	model.player_position = model.object_position
	model.interact()
	model.step(CONFIG.gathering_seconds * 0.5, Vector2.ZERO, false)
	expect(not model.object_consumed, "채집 완료 전에 보상 금지")
	model.step(0.1, Vector2.UP, false)
	expect(not model.interacting and model.interaction_progress == 0.0, "이동 시 채집 취소")
	model.player_position = model.object_position
	model.interact()
	model.step(CONFIG.gathering_seconds, Vector2.ZERO, false)
	expect(model.object_consumed, "근접 상호작용 완료")
	var count_before: int = model.feedback.size()
	model.interact()
	expect(not model.interacting and model.feedback.size() == count_before, "같은 오브젝트 중복 채집 금지")

	var slime: Dictionary = EnemyData.get_enemy("field_slime")
	model = room(slime)
	expect(not model.exit_open and model.alive_enemies() == 2, "전투 출구 잠금")
	model.basic_attack()
	expect(int(model.enemies[0]["hp"]) == 40, "먼 적은 공격으로 맞지 않아야 함")
	model.attack_remaining = 0.0
	model.player_position = Vector2(2.5, 3.0)
	model.facing = Vector2.UP
	model.basic_attack()
	expect(int(model.enemies[0]["hp"]) == 30, "기본 공격 피해/방어 반영")
	expect(not model.basic_attack() and int(model.enemies[0]["hp"]) == 30, "공격 쿨다운")
	model = room(slime, CONFIG.equipment_attacks.filter(func(p): return p.equipment_id == "rusty_sword")[0])
	model.player_position = Vector2(4, 3)
	model.enemies[0]["position"] = Vector2(3.5, 2.5)
	model.enemies[1]["position"] = Vector2(4.5, 2.5)
	model.facing = Vector2.UP
	model.basic_attack()
	expect(int(model.enemies[0]["hp"]) < 40 and int(model.enemies[1]["hp"]) < 40, "검의 다중 타격")
	expect(model.enemies[0]["position"] != Vector2(3.5, 2.5), "장비 넉백")
	# 예고 위치에서 이동하면 피해를 받지 않는다.
	model = room(slime)
	model.enemies.resize(1)
	model.player_position = Vector2(2.5, 2.5)
	model.step(0.01, Vector2.ZERO, false)
	expect(float(model.enemies[0]["windup"]) > 0, "적 공격 예고")
	for i in range(45): model.step(1.0 / 60.0, Vector2.RIGHT, false)
	expect(model.player_hp == 100, "걸어서 예고 공격 회피")
	model = room(slime)
	model.enemies.resize(1)
	model.player_position = Vector2(2.5, 2.5)
	model.step(0.01, Vector2.ZERO, false)
	for i in range(45): model.step(1.0 / 60.0, Vector2.ZERO, false)
	expect(model.player_hp == 95, "적 공격/플레이어 방어 반영")
	# 원거리 장비 계약도 같은 기본 공격으로 작동한다.
	var ranged := ExpeditionAttackProfile.new()
	ranged.method = ExpeditionAttackProfile.Method.PROJECTILE
	ranged.reach = 5.0
	model = room(slime, ranged)
	model.enemies.resize(1)
	model.player_position = Vector2(2.5, 5.0)
	model.facing = Vector2.UP
	model.basic_attack()
	for i in range(30): model.step(1.0 / 60.0, Vector2.ZERO, false)
	expect(int(model.enemies[0]["hp"]) == 30, "원거리 장비 기본 공격")
	model = room(slime, ranged)
	model.enemies.resize(1)
	model.obstacles = [Rect2(2, 2, 1, 1)]
	model.player_position = Vector2(1.5, 2.5)
	model.enemies[0]["position"] = Vector2(3.5, 2.5)
	model.facing = Vector2.RIGHT
	model.basic_attack()
	for i in range(20): model.step(1.0 / 60.0, Vector2.ZERO, false)
	expect(int(model.enemies[0]["hp"]) == 40, "벽 너머 원거리 타격 금지")
	print("[직접 조작 검사] 실패 ", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
