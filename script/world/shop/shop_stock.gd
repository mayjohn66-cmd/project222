class_name ShopStock
extends RefCounted


# 지금 진열대에 재고가 있는 품목을 모은다. 손님이 원하는 품목을 고를 때 쓴다.
static func get_stocked_item_ids(
	tree: SceneTree
) -> Array[String]:
	var result: Array[String] = []

	for shelf in tree.get_nodes_in_group("shelf"):
		if not is_instance_valid(shelf):
			continue

		for slot in shelf.get("slots"):
			var item_id: String = str(slot.get("item_id", ""))

			if item_id.is_empty() or result.has(item_id):
				continue

			if int(slot.get("stock", 0)) > 0:
				result.append(item_id)

	return result
