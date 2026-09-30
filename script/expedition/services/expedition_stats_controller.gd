class_name ExpeditionStatsController
extends RefCounted


# 원정 가방의 장비로 전투 능력치를 계산하고 능력치 표시를 갱신한다.
# 능력치(combat_player_*)는 전투와 체크포인트도 쓰므로 host(expedition.gd)가 가지고 있다.
# host는 씬 노드라서 타입을 붙이지 않는다.

var host


func setup(new_host) -> void:
	host = new_host


func apply_bag_equipment_stats() -> void:
	var bonus_attack: int = 0
	var bonus_defense: int = 0

	if host.expedition_bag == null:
		host.combat_player_attack = host.BASE_PLAYER_ATTACK
		host.combat_player_defense = host.BASE_PLAYER_DEFENSE
		return

	for placement in host.expedition_bag.placements:
		var item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		if item_id.is_empty():
			continue

		if not ExpeditionEquipmentData.has_equipment(
			item_id
		):
			continue

		var equipment_type: String = (
			ExpeditionEquipmentData.get_equipment_type(
				item_id
			)
		)

		# 전투 능력치에는 무기와 방어구만 반영한다.
		if (
			equipment_type
			!= ExpeditionEquipmentData.TYPE_WEAPON
			and equipment_type
			!= ExpeditionEquipmentData.TYPE_ARMOR
		):
			continue

		var effect_id: String = (
			ExpeditionEquipmentData.get_effect_id(
				item_id
			)
		)

		var effective_value: int = int(
			EquipmentEnhancementService.get_effective_value(
				placement
			)
		)

		match effect_id:
			"attack":
				bonus_attack += effective_value

			"defense":
				bonus_defense += effective_value

			_:
				push_warning(
					"[원정 능력치] 처리되지 않은 장비 효과"
					+ " / 아이템: "
					+ item_id
					+ " / 효과: "
					+ effect_id
				)

	host.combat_player_attack = (
		host.BASE_PLAYER_ATTACK
		+ bonus_attack
	)

	host.combat_player_defense = (
		host.BASE_PLAYER_DEFENSE
		+ bonus_defense
	)

	DebugLog.write(
		"[원정 능력치]"
		+ " / 기본 공격: ",
		host.BASE_PLAYER_ATTACK,
		" / 장비 공격: ",
		bonus_attack,
		" / 최종 공격: ",
		host.combat_player_attack,
		" / 기본 방어: ",
		host.BASE_PLAYER_DEFENSE,
		" / 장비 방어: ",
		bonus_defense,
		" / 최종 방어: ",
		host.combat_player_defense
	)


func update_player_stats_ui() -> void:
	# 능력치는 숫자로 보이지 않고 HP만 그림 막대로 보인다.
	host.player_stats_label.text = ""

	var bar: HpBar = null

	if host.player_stats_label.has_meta("hp_bar"):
		bar = host.player_stats_label.get_meta("hp_bar") as HpBar

	if bar == null:
		# 막대는 라벨의 자식이라 라벨이 보일 때만 보인다.
		host.player_stats_label.custom_minimum_size = Vector2(260, 24)
		bar = HpBar.new()
		host.player_stats_label.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.player_stats_label.set_meta("hp_bar", bar)

	bar.set_hp(host.combat_player_hp, host.combat_player_max_hp)
