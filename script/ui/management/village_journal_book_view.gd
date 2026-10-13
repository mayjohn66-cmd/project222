class_name VillageJournalBookView
extends RefCounted
## 부탁 포스트잇에서 기록을 확인한다. 행사 일정과는 별도의 책장이다.
## 왼쪽 기록 목록과 오른쪽 상세(RequestNotebookView). 아직 맡지 않은 부탁은 적지 않는다.
## 목적지를 고르면 월드의 VillageJournalDirector 가 책을 닫은 뒤 화살표·표시로 길을 안내한다.

static func add_requests(menu: Control) -> void:
	if not VillageJournalFlow.available():
		return

	var world: Node = _world(menu)

	if world == null:
		return

	var notebook := RequestNotebookView.new()
	notebook.menu = menu
	notebook.world = world
	menu.request_list.add_child(notebook)


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
