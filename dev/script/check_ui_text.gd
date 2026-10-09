extends Node
## UiText 가 CSV 를 읽고 관리 책 탭 설명이 화면에 반영되는지 확인한다.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	UiText.reload()
	check(UiText.has_key("management.tab.inventory.desc"), "key exists")
	check(UiText.t("management.tab.history.desc") == "편의점 현황과 지난 영업 결과를 확인합니다.", "text read")
	check(UiText.t("no.such.key", "대체") == "대체", "fallback for missing key")
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in range(30): await get_tree().process_frame
	var menu: ManagementMenu = world.get_node("UI/ManagementMenu")
	menu.open_menu(ManagementTabs.MenuTab.PRODUCTION)
	for i in range(10): await get_tree().process_frame
	check(menu.info_label.text == UiText.t("management.tab.production.desc"), "production tab shows csv text")
	menu.select_tab(ManagementTabs.MenuTab.EMPLOYEE)
	for i in range(10): await get_tree().process_frame
	check(menu.info_label.text == UiText.t("management.tab.employee.desc"), "employee tab shows csv text")
	print("CHECK_UI_TEXT checks=%d failures=%d" % [checks, failures])
	get_tree().quit()
