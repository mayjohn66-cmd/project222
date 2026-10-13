extends Node
## 원정 임시 보관함 카드 검사: 아이콘이 있는 물품은 아이콘과 수량 배지로, 없는 물품은 이름으로 보인다.
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _ready() -> void:
	var with_icon := ""
	var without_icon := ""
	for item_id in ItemData.get_all_item_ids() if ItemData.has_method("get_all_item_ids") else ItemData.items.keys():
		var has_icon: bool = ItemData.get_item_icon(str(item_id)) != null
		if has_icon and with_icon.is_empty(): with_icon = str(item_id)
		if not has_icon and without_icon.is_empty(): without_icon = str(item_id)
	check(not with_icon.is_empty(), "아이콘이 있는 물품이 있다")
	var card := LootItemCard.new()
	add_child(card)
	card.setup(0, with_icon, 3, null)
	check(card.icon_rect != null and card.icon_rect.texture == ItemData.get_item_icon(with_icon), "아이콘이 카드에 그려진다")
	check(card.text.is_empty(), "아이콘이 있으면 글자는 비운다")
	check(card.count_label != null and card.count_label.text == "×3", "수량 배지")
	check(card.tooltip_text.contains(ItemData.get_item_name(with_icon)) and card.tooltip_text.contains("×3"), "마우스를 올리면 이름과 수량")
	check(card.custom_minimum_size == Vector2(48, 48), "카드 크기가 가방 칸(52px 격자)과 같다")
	var drag: Variant = null
	card.controller = self
	drag = card.drag_payload()
	check(drag is Dictionary and drag["source"] == "loot" and drag["item_id"] == with_icon and int(drag["amount"]) == 3, "끌기 정보는 그대로")
	if not without_icon.is_empty():
		var plain := LootItemCard.new()
		add_child(plain)
		plain.setup(1, without_icon, 2, null)
		check(plain.icon_rect == null and plain.text == ItemData.get_item_name(without_icon), "아이콘이 없으면 이름으로 보인다")
	print("CHECK_LOOT_CARD checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
