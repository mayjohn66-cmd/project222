class_name StoryConditions
extends RefCounted


# 스토리 장면(비트)의 조건 문자열을 판정한다. 조건은 모두 맞아야 한다.
#   day>=N                      지금까지 지난 날짜(total_day)가 N 이상
#   expedition_done             원정을 한 번 이상 다녀옴
#   money<N                     소지금이 N 미만
#   item_below:아이템:N         인벤토리의 아이템 수가 N 미만
#   furniture_missing:가구      가구 인벤토리에도 배치된 것에도 그 가구가 없음
#   product_stock_empty         팔 수 있는 상품이 인벤토리와 진열대 모두 0개
# 알 수 없는 조건은 항상 거짓이다(오타로 엉뚱한 장면이 나오지 않게).

static func are_met(
	conditions: Array,
	tree: SceneTree
) -> bool:
	for condition in conditions:
		if not _is_met(str(condition), tree):
			return false

	return true


static func _is_met(
	condition: String,
	tree: SceneTree
) -> bool:
	if condition.begins_with("day>="):
		return GameState.total_day >= int(
			condition.trim_prefix("day>=")
		)

	if condition == "expedition_done":
		return PlayerProgress.has_completed_expedition()

	if condition.begins_with("money<"):
		return GameState.money < int(
			condition.trim_prefix("money<")
		)

	if condition.begins_with("item_below:"):
		var parts: PackedStringArray = condition.split(":")

		if parts.size() < 3:
			return false

		return GameState.get_item_count(parts[1]) < int(parts[2])

	if condition.begins_with("furniture_missing:"):
		return _is_furniture_missing(
			condition.trim_prefix("furniture_missing:")
		)

	if condition == "product_stock_empty":
		return _is_product_stock_empty(tree)

	push_warning(
		"[스토리] 알 수 없는 조건: " + condition
	)

	return false


static func _is_furniture_missing(
	furniture_id: String
) -> bool:
	if GameState.get_furniture_count(furniture_id) > 0:
		return false

	for entry in GameState.get_store_layout():
		if str(entry.get("build_id", "")) == furniture_id:
			return false

	return true


static func _is_product_stock_empty(
	tree: SceneTree
) -> bool:
	for item_id in ItemData.get_sellable_items():
		if ItemData.get_item_type(item_id) != ItemData.ITEM_TYPE_STORE_PRODUCT:
			continue

		if GameState.get_item_count(item_id) > 0:
			return false

		for shelf in tree.get_nodes_in_group("shelf"):
			if (
				is_instance_valid(shelf)
				and shelf.has_method("get_item_stock")
				and int(shelf.get_item_stock(item_id)) > 0
			):
				return false

	return true
