class_name ExpeditionEventController
extends RefCounted


# CSV로 정의된 원정 이벤트(전투, 전리품·채집, 회복, 없음)의 결과를 처리한다.
# 메시지 표시와 노드 완료 같은 화면 흐름은 host(expedition.gd)를 통해 호출한다.
# host는 씬 노드라서 타입을 붙이지 않는다.

var host


func setup(new_host) -> void:
	host = new_host


func resolve(
	event: Dictionary
) -> void:
	var message := str(
		event.get(
			"message",
			""
		)
	)

	var result_type := str(
		event.get(
			"result_type",
			"none"
		)
	)

	var target_id := str(
		event.get(
			"target_id",
			""
		)
	)

	var value := int(
		event.get(
			"value",
			0
		)
	)

	match result_type:
		"battle":
			host.show_run_messages(
				[
					message
				],
				Callable(
					self,
					"start_battle_event"
				).bind(
					target_id
				)
			)

		"loot":
			resolve_loot_event(
				message,
				target_id
			)

		"heal":
			resolve_heal_event(
				message,
				value
			)

		"none":
			host.show_run_messages(
				[
					message
				],
				Callable(
					host,
					"complete_current_map_node"
				)
			)

		_:
			push_warning(
				"[원정] 알 수 없는 result_type: "
				+ result_type
			)

			host.complete_current_map_node()


func start_battle_event(
	enemy_id: String
) -> void:
	if enemy_id.is_empty():
		push_warning(
			"[원정] 적 ID가 비어 있습니다."
		)

		host.complete_current_map_node()
		return

	host.start_map_battle(
		enemy_id
	)


func resolve_heal_event(
	message: String,
	heal_amount: int
) -> void:
	var before_hp: int = (
		host.combat_player_hp
	)

	var safe_heal_amount: int = max(
		heal_amount,
		0
	)

	host.combat_player_hp = min(
		host.combat_player_hp + safe_heal_amount,
		host.combat_player_max_hp
	)

	var healed: int = (
		host.combat_player_hp
		- before_hp
	)

	host.update_battle_ui()

	var result_message: String

	if healed <= 0:
		result_message = (
			"이미 체력이 가득 차 있다."
		)
	else:
		result_message = "체력을 회복했다!"

	host.show_run_messages(
		[
			message,
			result_message
		],
		Callable(
			host,
			"complete_current_map_node"
		)
	)


func resolve_loot_event(
	message: String,
	table_id: String
) -> void:
	host.temporary_loot.clear()

	var gathering_result: Dictionary = (
		host.expedition_gathering_service.resolve_gathering(
			table_id,
			host.expedition_bag,
			host.expedition_loot_service,
			host.get_run_difficulty()
		)
	)

	var gathering_handled: bool = bool(
		gathering_result.get(
			"handled",
			false
		)
	)

	# =========================
	# 도구 채집 규칙이 있는 전리품
	# =========================

	if gathering_handled:
		var gathering_success: bool = bool(
			gathering_result.get(
				"success",
				false
			)
		)

		if not gathering_success:
			var error_message: String = str(
				gathering_result.get(
					"message",
					"채집 정보를 확인할 수 없습니다."
				)
			)

			push_error(
				"[원정 채집] " + error_message
			)

			host.show_run_messages(
				[
					message,
					error_message
				],
				Callable(
					host,
					"complete_current_map_node"
				)
			)
			return

		var gathered: bool = bool(
			gathering_result.get(
				"gathered",
				false
			)
		)

		var gathering_message: String = str(
			gathering_result.get(
				"message",
				""
			)
		)

		# 도구 부족 또는 확률 판정 실패
		if not gathered:
			host.show_run_messages(
				[
					message,
					gathering_message
				],
				Callable(
					host,
					"complete_current_map_node"
				)
			)
			return

		var gathered_item_id: String = str(
			gathering_result.get(
				"item_id",
				""
			)
		)

		var gathered_amount: int = int(
			gathering_result.get(
				"amount",
				0
			)
		)

		host.temporary_loot.append(
			{
				"item_id": gathered_item_id,
				"blacksmith_ore_origin": gathered_item_id == "iron_ore",
				"amount": gathered_amount
			}
		)

		host.map_panel.visible = false
		host.battle_panel.visible = false
		host.loot_panel.visible = false

		host.show_run_messages(
			[
				message,
				gathering_message,
				"%s ×%d 획득!"
				% [
					ItemData.get_item_name(
						gathered_item_id
					),
					gathered_amount
				]
			],
			Callable(
				host,
				"_open_loot_after_message"
			)
		)
		return

	# =========================
	# 기존 일반 전리품 처리
	# =========================

	var result: Dictionary = (
		host.expedition_loot_service.roll_loot_table(
			table_id,
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
			"[원정 전리품] "
			+ str(
				result.get(
					"message",
					"전리품 추첨 실패"
				)
			)
		)

		host.show_run_messages(
			[
				message,
				"전리품 정보를 확인할 수 없습니다."
			],
			Callable(
				host,
				"complete_current_map_node"
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
			"blacksmith_ore_origin": item_id == "iron_ore",
			"amount": amount
		}
	)

	host.map_panel.visible = false
	host.battle_panel.visible = false
	host.loot_panel.visible = false

	host.show_run_messages(
		[
			message,
			"%s ×%d 발견!"
			% [
				ItemData.get_item_name(item_id),
				amount
			]
		],
		Callable(
			host,
			"_open_loot_after_message"
		)
	)
