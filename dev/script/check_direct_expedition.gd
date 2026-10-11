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
	expect(model.player_hp == 100 - ExpeditionDamage.calculate(8, 3), "적 공격/플레이어 방어 반영(피해 계산식)")
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
	# 무기 2개 교체: 공격 방식과 공격 보너스가 함께 바뀐다(화면에는 숫자를 보이지 않음).
	var bag := {"placements": [
		{"item_id": "rusty_sword", "enhancement_level": 0},
		{"item_id": "hand_axe", "enhancement_level": 2},
		{"item_id": "hunting_bow", "enhancement_level": 0}]}
	var loadout := ExpeditionWeaponLoadout.new()
	loadout.build(CONFIG, bag)
	expect(loadout.slots.size() == 2, "무기는 최대 2개만 고른다")
	expect(loadout.active_profile().equipment_id == "rusty_sword" and loadout.active_bonus() == 5, "처음에는 첫 무기")
	expect(loadout.other_name() == ItemData.get_item_name("hand_axe"), "교체 대상 이름")
	model = ExpeditionRoomModel.new()
	model.setup(CONFIG, loadout.active_profile(), 100, 100, 12 + loadout.active_bonus(), 3, slime, 1, false, "gather", loadout)
	model.player_position = Vector2(2.5, 3.0)
	model.enemies[0]["position"] = Vector2(2.5, 2.2)
	model.facing = Vector2.UP
	model.basic_attack()
	expect(int(model.enemies[0]["hp"]) == 40 - 15, "검 피해(공격 17 - 방어 2)")
	expect(model.swap_weapon(), "무기 교체 성공")
	expect(model.attack_profile.equipment_id == "hand_axe" and model.player_attack == 12 + 12 + 2, "교체하면 공격 방식과 공격 보너스가 함께 바뀜")
	expect(model.attack_remaining >= CONFIG.weapon_swap_delay, "교체 지연으로 쿨다운을 건너뛸 수 없음")
	model.attack_remaining = 0.0
	var hp_before: int = int(model.enemies[0]["hp"])
	model.basic_attack()
	expect(hp_before - int(model.enemies[0]["hp"]) == 26 - 2 or int(model.enemies[0]["hp"]) == 0, "도끼 피해(공격 26 - 방어 2)")
	expect(model.swap_weapon() and model.attack_profile.equipment_id == "rusty_sword", "다시 교체하면 첫 무기")
	var single := ExpeditionWeaponLoadout.new()
	single.build(CONFIG, {"placements": [{"item_id": "iron_spear", "enhancement_level": 0}]})
	expect(not single.has_choice() and not single.swap(), "무기가 하나면 교체하지 않음")
	var bare := ExpeditionWeaponLoadout.new()
	bare.build(CONFIG, {"placements": []})
	expect(bare.active_profile() == CONFIG.default_attack and bare.active_bonus() == 0 and bare.active_name() == "맨손", "무기가 없으면 맨손")
	expect(ExpeditionWeaponLoadout.get_style_text("hunting_bow").find("원거리") >= 0 and ExpeditionWeaponLoadout.get_style_text("hunting_bow").find("+") < 0, "공격 방식 설명은 숫자 없이")
	# HP는 그림 막대, 공격 피해는 별도 숫자 그림으로 표시한다.
	model = room(slime)
	model.player_position = Vector2(2.5, 3.0)
	model.enemies[0]["position"] = Vector2(2.5, 2.2)
	model.facing = Vector2.UP
	model.basic_attack()
	var hit_notes: Array = model.feedback.filter(func(n): return str(n.get("kind", "")) == "hit")
	expect(not hit_notes.is_empty() and hit_notes.all(func(n): return str(n["text"]).is_empty()), "타격 선 효과는 숫자 그림과 분리")
	var damage_notes: Array = model.feedback.filter(func(n): return str(n.get("kind", "")) == "damage")
	expect(damage_notes.size() == hit_notes.size() and int(damage_notes[0]["amount"]) > 0, "명중마다 실제 피해량 그림 기록")
	var bar := HpBar.new()
	bar.set_hp(50, 100)
	expect(is_equal_approx(bar.ratio, 0.5), "HP 막대 비율")
	bar.set_hp(0, 0)
	expect(bar.ratio == 0.0, "최대 체력 0이어도 안전")
	bar.free()
	# 피해 계산식: 공격² ÷ (공격 + 방어), 반올림, 최소 1.
	expect(ExpeditionDamage.calculate(12, 0) == 12, "방어 0이면 공격력 그대로")
	expect(ExpeditionDamage.calculate(20, 20) == 10, "방어가 공격과 같으면 절반")
	expect(ExpeditionDamage.calculate(17, 2) == 15, "검 vs 슬라임")
	expect(ExpeditionDamage.calculate(14, 6) == 10, "보스 vs 기본 방어(196 / 20)")
	expect(ExpeditionDamage.calculate(14, 60) >= 1, "방어가 아무리 높아도 최소 1")
	expect(ExpeditionDamage.calculate(0, 5) == 1 and ExpeditionDamage.calculate(-3, 5) == 1, "공격이 0 이하여도 안전")
	var previous: int = 999
	var monotonic := true
	for defense in range(0, 80):
		var damage: int = ExpeditionDamage.calculate(20, defense)
		if damage > previous: monotonic = false
		previous = damage
	expect(monotonic, "방어가 높을수록 피해는 줄어들기만 한다")
	print("[직접 조작 검사] 실패 ", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
