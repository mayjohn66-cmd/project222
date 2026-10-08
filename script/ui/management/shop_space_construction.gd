class_name ShopSpaceConstruction
extends RefCounted

static func render(host: Control) -> bool:
	host.expand_button.show()
	for button in [host.store_button, host.production_room_button, host.warehouse_button]: button.show()
	if ShopSpaceProgression.expansion_ready(): return false
	var info := ShopSpaceProgression.preparation()
	var phase := ShopSpaceProgression.phase()
	var guidance := RoomPreparationGuide.next_action(host)
	host.store_button.hide()
	host.production_room_button.visible = phase in ["store", "make_production", "produce"]
	host.warehouse_button.visible = phase in ["make_warehouse", "store_materials"]
	host.production_room_button.disabled = true
	host.warehouse_button.disabled = true
	host.area_title_label.text = str(info["title"])
	host.current_info_label.text = str(info["current"])
	host.next_info_label.text = str(info["next"])
	host.note_label.text = str(info["note"])
	var door := str(info["door"])
	host.expand_button.visible = not door.is_empty()
	host.expand_button.text = "생산실 문 배치" if door == "production_door" else "창고 문 배치"
	host.expand_button.disabled = door.is_empty() or GameState.get_furniture_count(door) < 1
	if not door.is_empty() and GameState.get_furniture_count(door) < 1:
		host.note_label.text = "보유한 문이 없습니다. 설계도에서 문을 제작한 뒤 배치하세요."
	if not guidance.is_empty():
		host.current_info_label.text = str(guidance["current"])
		host.next_info_label.text = str(guidance["next"])
		host.note_label.text = str(guidance["note"])
		host.expand_button.text = RoomPreparationGuide.button_text(guidance)
		host.expand_button.visible = not host.expand_button.text.is_empty()
		host.expand_button.disabled = false
	return true

static func begin(host: Control) -> void:
	if RoomPreparationGuide.open_action(host): return
	var info := ShopSpaceProgression.preparation()
	var menu = host.get_parent()
	while menu != null and not menu.has_method("close_menu"): menu = menu.get_parent()
	if menu != null: ShopSpaceProgression.begin_room_build(menu, str(info["door"]))
