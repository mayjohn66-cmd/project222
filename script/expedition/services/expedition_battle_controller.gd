class_name ExpeditionBattleController
extends RefCounted


# 원정 전투의 시작, 1초 단위 진행, 결과 처리, 화면 갱신, 전리품 추첨을 담당한다.
# 전투 수치(combat_*)는 체크포인트와 장비 스탯 계산도 쓰므로 host(expedition.gd)가 가지고 있다.
# host는 씬 노드라서 타입을 붙이지 않는다.

var host


func setup(new_host) -> void:
	host = new_host


func start_battle(
	enemy_id: String = "field_slime"
):
	if host.battle_active:
		return

	var enemy: Dictionary = (
		EnemyData.get_enemy(
			enemy_id
		)
	)

	if enemy.is_empty():
		return

	host.combat_enemy_id = enemy_id

	host.combat_enemy_name = str(
		enemy.get(
			"name",
			host.combat_enemy_id
		)
	)

	var difficulty: int = host.get_run_difficulty()

	host.combat_enemy_max_hp = maxi(
		roundi(
			float(
				enemy.get(
					"max_hp",
					1
				)
			)
			* ExpeditionDifficultyData.get_monster_hp_mult(
				difficulty
			)
		),
		1
	)

	host.combat_enemy_hp = host.combat_enemy_max_hp

	host.combat_enemy_attack = maxi(
		roundi(
			float(
				enemy.get(
					"attack",
					1
				)
			)
			* ExpeditionDifficultyData.get_monster_atk_mult(
				difficulty
			)
		),
		1
	)

	host.combat_enemy_defense = int(
		enemy.get(
			"defense",
			0
		)
	)

	# 전투 파트는 새로 만들 예정이라, 지금은 승리한 것으로 보고 보상으로 넘어간다.
	if GameConfig.EXPEDITION_AUTO_WIN_BATTLES:
		host.combat_enemy_hp = 0

		DebugLog.write(
			"[전투] 자동 승리: ",
			host.combat_enemy_name
		)

		resolve_victory()
		return

	host.battle_active = true

	host.start_battle_button.disabled = true

	host.battle_status_label.text = (
		host.combat_enemy_name
		+ " 등장"
	)

	update_ui()

	host.battle_timer.start()


func process_tick():
	if not host.battle_active:
		return

	var damage_to_enemy: int = max(
		1,
		host.combat_player_attack
		- host.combat_enemy_defense
	)

	var damage_to_player: int = max(
		1,
		host.combat_enemy_attack
		- host.combat_player_defense
	)

	# 같은 1초 안에 서로 동시에 피해
	host.combat_enemy_hp -= damage_to_enemy
	host.combat_player_hp -= damage_to_player

	host.combat_enemy_hp = max(
		0,
		host.combat_enemy_hp
	)

	host.combat_player_hp = max(
		0,
		host.combat_player_hp
	)

	DebugLog.write(
		"[전투] 플레이어 → ",
		host.combat_enemy_name,
		" ",
		damage_to_enemy,
		" 피해"
	)

	DebugLog.write(
		"[전투] ",
		host.combat_enemy_name,
		" → 플레이어 ",
		damage_to_player,
		" 피해"
	)

	update_ui()

	check_result()


func check_result() -> void:
	if (
		host.combat_player_hp > 0
		and host.combat_enemy_hp > 0
	):
		return

	host.battle_active = false
	host.battle_timer.stop()

	host.start_battle_button.disabled = false

	# 동시 전투 불능도 플레이어 패배로 처리
	if host.combat_player_hp <= 0:
		var defeat_message: String = (
			"체력이 모두 소진되어 원정을 종료합니다."
		)

		if host.combat_enemy_hp <= 0:
			host.battle_status_label.text = "동시 전투 불능"
		else:
			host.battle_status_label.text = "전투 패배"

		host.battle_panel.visible = false
		host.map_panel.visible = false

		DebugLog.write("[원정] 전투 불능 → 결과 안내")

		host.show_run_messages(
			[defeat_message],
			Callable(
				host,
				"open_result_phase"
			).bind(
				host.ExpeditionEndReason.DEFEAT
			)
		)

		return

	resolve_victory()


# 적을 처치했을 때: 전리품을 굴리고 정리 화면(또는 다음 칸)으로 넘어간다.
func resolve_victory() -> void:
	host.battle_status_label.text = (
		host.combat_enemy_name + " 처치"
	)

	DebugLog.write(
		"[전투] 승리 / 남은 HP: ",
		host.combat_player_hp
	)

	generate_loot(
		host.combat_enemy_id
	)

	host.battle_panel.visible = false

	if host.temporary_loot.is_empty():
		host.complete_current_map_node()
	else:
		host.loot_panel.visible = true


func update_ui():
	host.player_hp_label.text = (
		"플레이어 HP: "
		+ str(host.combat_player_hp)
		+ " / "
		+ str(host.combat_player_max_hp)
	)

	if host.combat_enemy_name.is_empty():
		host.enemy_hp_label.text = "적 HP: -"

	else:
		host.enemy_hp_label.text = (
			host.combat_enemy_name
			+ " HP: "
			+ str(host.combat_enemy_hp)
			+ " / "
			+ str(host.combat_enemy_max_hp)
		)

	host.update_player_stats_ui()


func generate_loot(
	enemy_id: String
) -> void:
	host.temporary_loot.clear()
	host.refresh_loot_ui()

	var result: Dictionary = (
		host.expedition_loot_service.roll_enemy_loot(
			enemy_id,
			host.get_run_difficulty()
		)
	)

	if not bool(
		result.get(
			"success",
			false
		)
	):
		push_error(
			"[전투 전리품] "
			+ str(
				result.get(
					"message",
					"전리품 추첨 실패"
				)
			)
		)
		return

	var item_id: String = str(
		result.get(
			"item_id",
			""
		)
	)

	var amount: int = int(
		result.get(
			"amount",
			0
		)
	)

	host.temporary_loot.append(
		{
			"item_id": item_id,
			"amount": amount
		}
	)

	host.refresh_loot_ui()

	DebugLog.write(
		"[전투 전리품] ",
		ItemData.get_item_name(item_id),
		" ×",
		amount
	)
