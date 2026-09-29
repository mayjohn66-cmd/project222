class_name ProductionRecipeService
extends RefCounted


static func collect_required_ingredients(
	recipe: Dictionary,
	production_count: int
) -> Dictionary:
	var totals: Dictionary = {}

	if production_count <= 0:
		return totals

	var ingredients: Array = recipe.get(
		"ingredients",
		[]
	)

	for ingredient in ingredients:
		if not ingredient is Dictionary:
			return {}

		var item_id: String = str(
			ingredient.get("item_id", "")
		)

		var base_amount: int = int(
			ingredient.get("amount", 0)
		)

		if not ItemData.has_item(item_id):
			return {}

		if base_amount <= 0:
			return {}

		totals[item_id] = (
			int(totals.get(item_id, 0))
			+ base_amount * production_count
		)

	return totals


static func consume_ingredients(
	recipe: Dictionary,
	production_count: int
) -> bool:
	var required: Dictionary = (
		collect_required_ingredients(
			recipe,
			production_count
		)
	)

	if required.is_empty():
		return false

	# 차감 전에 모든 재료의 보유량 검사
	for raw_item_id in required:
		var item_id: String = str(raw_item_id)
		var required_amount: int = int(required[item_id])

		if GameState.get_item_count(item_id) < required_amount:
			return false

	var consumed: Dictionary = {}

	for raw_item_id in required:
		var item_id: String = str(raw_item_id)
		var required_amount: int = int(required[item_id])

		var removed_amount: int = (
			GameState.remove_item(
				item_id,
				required_amount
			)
		)

		consumed[item_id] = removed_amount

		if removed_amount == required_amount:
			continue

		# 도중에 실패하면 이번 작업에서 차감한 만큼 반환
		for raw_consumed_id in consumed:
			var consumed_id: String = str(raw_consumed_id)
			var refund_amount: int = int(
				consumed[consumed_id]
			)

			if refund_amount > 0:
				GameState.add_item(
					consumed_id,
					refund_amount
				)

		push_warning(
			"[생산] 재료 차감 실패 / 차감분 반환"
		)
		return false

	return true
