class_name ShopSpaceMenu
extends Node

var host
var signature := ""
var elapsed := 0.0

func _ready() -> void:
	host = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("refresh")

func refresh() -> void:
	var managers := get_tree().get_nodes_in_group("build_manager")
	if managers.is_empty(): return
	var world := managers[0].get_parent()
	ShopSpaceProgression.adopt_tutorial_save(world)
	for room in ["production", "warehouse"]:
		world.get_node("ProductionRoom" if room == "production" else "WarehouseRoom").visible = ShopSpaceProgression.room_ready(room)
	host.production_button.visible = tab_available(host.MenuTab.PRODUCTION)
	host.construction_button.visible = tab_available(host.MenuTab.CONSTRUCTION)
	host.employee_button.visible = tab_available(host.MenuTab.EMPLOYEE)
	if not tab_available(int(host.current_tab)):
		host.select_tab(host.MenuTab.INVENTORY)
	host.construction_content.refresh_view()
	host.blueprint_content.refresh_view()
	host.management_production.refresh_view()
	host.management_inventory.refresh_inventory()
	host.PRESENTATION._sync_note.call_deferred(host)
	for bar in managers:
		bar.build_quick_slot_bar.refresh_slots()
		bar.build_quick_slot_bar.refresh_furniture_inventory()

func tab_available(tab: int) -> bool:
	if ShopSpaceProgression.UNLOCK_ALL_TABS: return true
	match tab:
		host.MenuTab.PRODUCTION: return ShopSpaceProgression.production_introduced()
		host.MenuTab.CONSTRUCTION: return ShopSpaceProgression.production_offered()
		host.MenuTab.EMPLOYEE: return not ShopSpaceProgression.active() or OpeningJourneyFlow.core_finished()
	return true

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0.0
	var state := "%s:%s:%s:%s" % [ShopSpaceProgression.active(), ShopSpaceProgression.phase(), ShopSpaceProgression.production_offered(), OpeningJourneyFlow.core_finished()]
	if state == signature: return
	signature = state
	refresh()
