class_name RequestNotebookTab
extends RefCounted
## 기존 일정 화면 틀을 재사용하되, 부탁 기록은 독립된 책장에 놓는다.
static func install(menu: Control) -> void:
	var button := Button.new()
	button.name = "RequestButton"
	button.text = "부탁"
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(104, 48)
	menu.inventory_button.get_parent().add_child(button)
	menu.request_button = button
	button.pressed.connect(menu.select_tab.bind(ManagementTabs.MenuTab.REQUESTS))
	var content: Control = menu.schedule_content.duplicate()
	content.name = "RequestContent"
	menu.schedule_content.get_parent().add_child(content)
	menu.request_content = content
	content.hide()
	var column := content.get_node("MarginContainer/ScheduleVBox")
	column.get_node("CurrentDateLabel").hide()
	menu.request_list = column.get_node("ScheduleScroll/ScheduleList")

static func refresh(menu: Control) -> void:
	for child in menu.request_list.get_children():
		menu.request_list.remove_child(child)
		child.queue_free()
	VillageJournalBookView.add_requests(menu)
