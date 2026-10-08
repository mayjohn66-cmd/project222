extends Node
var checks := 0
var failures := 0
var world
var menu
var blueprint
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(2.0,true,false,true).timeout
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + label + ".png")
func show_blueprint(id: String) -> void:
	menu.select_tab(ManagementMenu.MenuTab.BLUEPRINT)
	blueprint._on_category_pressed(str(FurnitureData.get_furniture(id)["craft_category"]))
	blueprint._select_furniture(id)
func card(id: String) -> ItemCard:
	var inv = menu.management_inventory
	inv.select_inventory_group(ItemData.INVENTORY_GROUP_FURNITURE)
	for child in inv.item_grid.get_children():
		if child is ItemCard and str(child.entry_id) == id: return child
	return null
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	OpeningJourneyFlow.initialize(world)
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	world.get_node("Actors/Player").set_physics_process(false)
	menu = manager.management_menu
	menu.space_menu.refresh()
	blueprint = menu.blueprint_content
	check(FurnitureGuide.description("unknown").is_empty() and FurnitureGuide.specs("unknown").is_empty(),"unknown ID has no fabricated furniture information")
	check(blueprint.production_button.visible == ShopSpaceProgression.UNLOCK_ALL_TABS and blueprint.interior_button.visible == ShopSpaceProgression.UNLOCK_ALL_TABS,"category visibility follows shared tab switch while furniture remains stage gated")
	check(not FurnitureGuide.description("warehouse_rack").contains("40"),"early hidden storage does not reveal capacity")
	GameState.add_furniture("shelf_2x1",1) # Older owned shelf has no current crafting recipe.
	check(FurnitureGuide.alternatives("wood_shelf_2x1").has("shelf_2x1") and not FurnitureGuide.alternatives("wood_shelf_2x1").has("modern_shelf_2x1"),"same footprint comparison prioritizes available shelf and hides unknown modern one")
	var original: Dictionary = ShelfData.get_shelf_data("reinforced_shelf_2x1")
	var guide := FurnitureGuide.description("reinforced_shelf_2x1",true)
	check(guide.contains("최대 " + str(original["max_stack_level"]) + "층") and not guide.contains("두 층"),"reinforced stacking explanation reads current three-level data rather than stale flavor")
	check(guide.contains("같은 종류의 진열대 1개") and guide.contains("해금 조건"),"maximum capacity is not presented as a free upgrade and locked crafting still explained")
	check(FurnitureGuide.description("wood_shelf_1x1").contains("한 층만") and FurnitureGuide.description("wood_shelf_1x1").contains("합계 8개"),"wood shelf explains actual single-level use")
	menu.open_menu(ManagementMenu.MenuTab.BLUEPRINT)
	show_blueprint("wood_shelf_2x1")
	check(blueprint.description_label.text.contains("합계 12개") and blueprint.description_label.text.contains("합계 21개"),"actual blueprint compares wood and existing shelf at same footprint")
	await snap("wood-comparison")
	show_blueprint("reinforced_shelf_2x1")
	check(blueprint.craft_button.disabled and blueprint.description_label.text.contains("해금 조건"),"inspectable tier does not bypass crafting condition")
	PlayerProgress.record_story_beat(FurnitureObjectCatalog.PREFIX + "wood",GameState.total_day)
	blueprint.refresh_view()
	show_blueprint("reinforced_shelf_2x1")
	check(blueprint.description_label.text.contains("합계 24개") and blueprint.description_label.text.contains("최대 3층"),"live blueprint displays current reinforced capacity")
	await snap("reinforced")

	check(blueprint.guide_summary.text.contains("24개") and blueprint.guide_summary.visible,"primary shelf capacity appears above preview without scrolling")
	var blueprint_scroll = blueprint.get_node("MainVBox/Body/DetailPanel/DetailScroll")
	blueprint_scroll.scroll_vertical = 200
	await frames()
	show_blueprint("wood_shelf_1x1")
	check(blueprint_scroll.scroll_vertical == 0,"new furniture selection returns detail to its overview")
	var inv = menu.management_inventory
	GameState.add_furniture("reinforced_shelf_2x1",1)
	menu.select_tab(ManagementMenu.MenuTab.INVENTORY)
	var selected := card("reinforced_shelf_2x1")
	check(is_instance_valid(selected),"actual furniture inventory card exists")
	selected.pressed.emit()
	var pane: InventoryDetailPane = inv.get_node("DetailPage")
	check(pane._desc.text.contains("합계 24개") and not pane._desc.text.contains("두 층"),"inventory uses the same truthful current furniture guide")
	check(pane._price.text.contains("24개") and pane._price.visible,"inventory primary capacity remains above long description")
	await frames()
	check(pane._scroll.size.y > 300 and pane._scroll.get_global_rect().end.y <= pane.get_global_rect().end.y + 1,"long inventory explanation stays inside book page")
	check(pane._desc.get_parent().get_combined_minimum_size().y > pane._scroll.size.y,"long guide actually uses scrollable content")
	pane._scroll.scroll_vertical = 99999
	await frames()
	check(pane._scroll.scroll_vertical > 0,"actual furniture inventory description can scroll to final usage hint")
	await snap("inventory-details")
	var owned_before := GameState.get_furniture_count("reinforced_shelf_2x1")
	var money_before := GameState.money
	var inventory_before := GameState.inventory.duplicate(true)
	var progress_before := PlayerProgress.to_save_data().duplicate(true)
	var preservation_before := GameState.preservation_state.duplicate(true)
	for id in FurnitureData.get_all_furniture(): FurnitureGuide.description(str(id["id"]),true)
	check(GameState.inventory == inventory_before and GameState.money == money_before and GameState.get_furniture_count("reinforced_shelf_2x1") == owned_before and PlayerProgress.to_save_data() == progress_before and GameState.preservation_state == preservation_before,"reading every guide does not spend, upgrade, unlock, install cooling or advance stories")
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat("tutorial_step:production:intro",GameState.total_day)
	PlayerProgress.learn_recipe("camp_bread")
	menu.space_menu.refresh()
	show_blueprint("magic_oven")
	check(blueprint.description_label.text.contains("현지식 빵") and not blueprint.description_label.text.contains("버섯 스튜"),"production furniture lists only learned and actually available products")
	await snap("first-oven")
	check(not FurnitureGuide.description("warehouse_rack").contains("총 보관량"),"production introduction still waits for warehouse milestone")
	ShopSpaceProgression.mark("production")
	PlayerProgress.record_story_beat("tutorial_event:produced_bread",GameState.total_day)
	ShopSpaceProgression.mark("warehouse")
	menu.space_menu.refresh()
	for id in ["warehouse_rack","wood_warehouse_rack","steel_warehouse_rack"]:
		var node = BuildObjectData.get_build_scene(id).instantiate()
		FurnitureObjectCatalog.configure_storage(node,id)
		var spec := FurnitureGuide.specs(id)
		check(spec["capacity"] == node.storage_capacity and spec["slots"] == node.storage_slot_count,"guide matches actual storage instance: " + id)
		check(FurnitureGuide.description(id).contains("일반 선반에는 냉장·냉동 기능이 없습니다"),"normal storage does not imply seasonal preservation: " + id)
		node.free()
	GameState.add_furniture("warehouse_rack",1)
	show_blueprint("wood_warehouse_rack")
	check(blueprint.description_label.text.contains("총 보관량 24개") and blueprint.description_label.text.contains("총 보관량 40개") and not blueprint.description_label.text.contains("철제 창고 선반"),"available warehouse comparison hides unknown future tier")
	await snap("warehouse")
	PlayerProgress.record_story_beat(FurnitureObjectCatalog.PREFIX + "reinforced",GameState.total_day)
	PlayerProgress.record_story_beat(FurnitureObjectCatalog.PRODUCT_STORY_PREFIX + "craft_first_shelf:done",GameState.total_day)
	for id in ["fridge_unit","freezer_unit"]:
		var text := FurnitureGuide.description(id)
		var unit := FurnitureGuide.preservation_unit(id)
		check(text.contains("총용량 " + str(unit["capacity"]) + "개") and text.contains("총용량은 함께 사용"),"cold units explain actual shared capacity: " + id)
		check(not text.contains("별도 손님·평판 보너스") and not text.contains("120 G") and not text.contains("240 G"),"cold unit has no fabricated decoration bonus or second installation fee")
	show_blueprint("freezer_unit")
	await snap("freezer")
	for id in ["plant_small","wall_poster","night_lantern","antique_cabinet","old_world_map","adventurer_banner"]:
		var text := FurnitureGuide.description(id)
		check(text.contains("[배치 효과]") and text.contains("매장에 실제 배치"),"actual decoration effect is described for " + id)
	show_blueprint("plant_small")
	check(blueprint.description_label.text.contains("손님이 찾아올 비중") and not blueprint.description_label.text.contains("매출 보장"),"available decoration contribution comes from existing effect data")
	await snap("decoration")
	show_blueprint("modern_shelf_2x1")
	check(blueprint.description_label.text.contains("합계 40개") and not blueprint.craft_button.text.is_empty(),"modern shelf explains actual density after existing story condition")
	await snap("modern")
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.load_save_data(saved)
	check(FurnitureGuide.alternatives("wood_warehouse_rack").has("steel_warehouse_rack"),"saved modern unlock is reflected without new save fields")
	PlayerProgress.story_beat_days.erase(FurnitureObjectCatalog.PRODUCT_STORY_PREFIX + "craft_first_shelf:done")
	GameState.add_furniture("steel_warehouse_rack",1)
	check(FurnitureGuide.alternatives("wood_warehouse_rack").has("steel_warehouse_rack"),"already owned future tier remains a usable comparison without unlocking new crafting")
	check(not FurnitureObjectCatalog.locked_reason("steel_warehouse_rack").is_empty(),"owned item comparison does not unlock crafting")
	menu.select_tab(ManagementMenu.MenuTab.INVENTORY)
	var steel_card := card("steel_warehouse_rack")
	check(is_instance_valid(steel_card),"owned locked-craft furniture remains visible in actual inventory")
	steel_card.pressed.emit()
	check(not pane._desc.text.contains("해금 조건") and pane._desc.text.contains("총 보관량 80개"),"inventory shows use of owned furniture independently of new crafting lock")
	GameState.add_furniture("night_lantern",1)
	var lantern_card := card("night_lantern")
	lantern_card.pressed.emit()
	check(pane._desc.text.contains("+2.0") and pane._acquire.text.contains("보유한 집기"),"owned lantern shows real effect without falsely claiming a crafting recipe")
	# Ordinary item selection still uses its icon, price and original description.
	inv.select_inventory_group(ItemData.INVENTORY_GROUP_SHELF)
	GameState.add_item("bread",1)
	inv.refresh_inventory()
	for entry in inv.item_grid.get_children():
		if entry is ItemCard and entry.item_id == "bread":
			entry.pressed.emit()
			check(pane._icon.visible and not pane._preview.visible and pane._price.text.contains("G") and not pane._desc.text.contains("[현재 규격]"),"normal item detail and price survive new scroll layout")
			break
	print("CHECK_FURNITURE_GUIDE ",checks," checks / ",failures," failures")
	get_tree().paused = false
	get_tree().quit(1 if failures else 0)
