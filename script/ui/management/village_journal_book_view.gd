class_name VillageJournalBookView
extends RefCounted
## 마을 수첩을 관리 책의 일정 탭 안에 넣는다(2026-10-08 결정: 화면에 따로 띄우던 수첩 단추·팝업 대신 책에서 확인).
## 내용은 팝업이 쓰던 것과 같다: 이웃·부탁 기록(VillageJournalFlow), 물품 준비(RequestPreparationData), 목적지 표시.
## 목적지를 고르면 월드의 VillageJournalDirector 가 책을 닫은 뒤 화살표·표시로 길을 안내한다.

const INTRO := "이웃과 함께한 날을 확인하세요. 목적지를 표시한 뒤 책을 닫고 직접 걸어가세요."


static func add_schedule(menu: Control) -> void:
	if not VillageJournalFlow.available():
		return

	var world: Node = _world(menu)

	if world == null:
		return

	var director := world.get_node_or_null("VillageJournalDirector") as VillageJournalDirector
	var list: Container = menu.schedule_list
	_card(list, [
		_label("마을 수첩", 22),
		_label("%s · 마을 평판 %d" % [ResidentStoryFlow.place_name(), ResidentRequestFlow.reputation()], 17),
		_label(INTRO, 16),
	])
	# 왼쪽에 띄우던 "채집 도구를 구하는 길" 안내도 이제 수첩에서 본다.
	var supply_step := EarlyProgressionGuide.waiting_text()
	if supply_step.is_empty(): supply_step = ResidentMerchantSupply.next_step()

	if not supply_step.is_empty():
		_card(list, [_label("채집 도구를 구하는 길", 20), _label(supply_step, 17)])

	var rows := RequestPreparationData.entries() if RequestPreparationData.ENABLED else []

	if not rows.is_empty():
		var context := _environment(world)
		var lines: Array = [_label("물품 준비", 20)]

		for entry in rows:
			lines.append(_label(str(entry["title"]), 18))
			lines.append(_label(RequestPreparationData.information(world, entry, context), 16))

		_card(list, lines)

	for entry in VillageJournalFlow.entries():
		var id := str(entry["id"])
		var target := VillageJournalFlow.destination(world, id)
		var tracked: bool = director != null and director.tracked_id == id
		var button := Button.new()
		button.text = "목적지 표시 해제" if tracked else "목적지 표시"
		button.custom_minimum_size.y = 40
		button.disabled = director == null or (target == null and not tracked)
		button.pressed.connect(func() -> void:
			if director != null:
				director.set_tracked(id)
				menu.refresh_schedule())
		var info := VillageJournalFlow.information(id)
		var current := ""

		if id.begins_with("resident:") and target != null:
			current = "\n현재: " + target.routine_status()

		_card(list, [_label(str(entry["title"]), 20), _label(info + current, 17), button])


static func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label


static func _card(list: Container, children: Array) -> void:
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)

	for child in children:
		card.add_child(child)

	list.add_child(card)


static func _world(menu: Node) -> Node:
	var node: Node = menu

	while node != null and node.get_node_or_null("DayManager") == null:
		node = node.get_parent()

	return node


static func _environment(world: Node) -> Dictionary:
	var manager := world.get_node_or_null("DayManager")
	var hour: float = float(manager.current_hour) + manager.get_display_minute() / 60.0 if manager != null else float(GameConfig.DAY_START_HOUR)
	return {"day": GameState.total_day, "hour": hour, "season": CalendarData.get_season_id(GameState.total_day),
		"weather": str(WorldWeatherData.forecast(GameState.total_day, hour)["kind"])}
