extends RefCounted

var environment: Dictionary = {}


# difficulty: 원정 난이도 레벨. 수량 배율과 희귀 재료 확률 배율을 정한다.
func roll_enemy_loot(
	enemy_id: String,
	difficulty: int = 1
) -> Dictionary:
	var table_id: String = (
		EnemyData.get_loot_table(
			enemy_id
		)
	)

	if table_id.is_empty():
		return _failure(
			"적의 전리품 테이블이 없습니다: "
			+ enemy_id
		)

	return roll_loot_table(
		table_id,
		difficulty
	)


func roll_loot_table(
	table_id: String,
	difficulty: int = 1
) -> Dictionary:
	if table_id.is_empty():
		return _failure(
			"전리품 테이블 ID가 비어 있습니다."
		)

	var loot: Dictionary = (
		ExpeditionEventData.get_random_loot(
			table_id,
			ExpeditionDifficultyData.get_rare_chance_mult(
				difficulty
			),
			difficulty,
			environment
		)
	)

	if loot.is_empty():
		return _failure(
			"추첨할 전리품이 없습니다: "
			+ table_id
		)

	var item_id: String = str(
		loot.get(
			"item_id",
			""
		)
	)

	var min_amount: int = int(
		loot.get(
			"min_amount",
			0
		)
	)

	var max_amount: int = int(
		loot.get(
			"max_amount",
			0
		)
	)

	if not ItemData.has_item(item_id):
		return _failure(
			"등록되지 않은 전리품: "
			+ item_id
		)

	if not ItemData.can_store_in_expedition_bag(
		item_id
	):
		return _failure(
			"원정 가방에 담을 수 없는 전리품: "
			+ item_id
		)

	if min_amount <= 0:
		return _failure(
			"최소 수량이 올바르지 않습니다: "
			+ table_id
		)

	if max_amount < min_amount:
		return _failure(
			"최대 수량이 최소 수량보다 작습니다: "
			+ table_id
		)

	var amount: int = ceili(
		float(
			randi_range(
				min_amount,
				max_amount
			)
		)
		* ExpeditionDifficultyData.get_reward_amount_mult(
			difficulty
		)
	)

	return {
		"success": true,
		"message": "",
		"table_id": table_id,
		"item_id": item_id,
		"amount": amount
	}


# 아직 레시피를 하나도 모르는 플레이어가 처음 보스를 잡았을 때 함께 주는
# 기본 음식 제작 두루마리. 줄 게 없으면 빈 Dictionary. 한 번 주면 다시 주지 않는다.
func roll_starter_scroll() -> Dictionary:
	if not PlayerProgress.is_starter_scroll_pending():
		return {}

	var scroll_item_id: String = (
		RecipeUnlockData.get_starter_scroll_item_id()
	)

	if scroll_item_id.is_empty():
		return {}

	if not ItemData.can_store_in_expedition_bag(
		scroll_item_id
	):
		return {}

	PlayerProgress.mark_starter_scroll_granted()

	DebugLog.write(
		"[첫 보스] 기본 제작 두루마리 지급: ",
		scroll_item_id
	)

	return {
		"success": true,
		"message": "",
		"table_id": "starter_scroll",
		"item_id": scroll_item_id,
		"amount": 1
	}


func _failure(
	message: String
) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"table_id": "",
		"item_id": "",
		"amount": 0
	}
