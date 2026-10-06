extends Node
var checks := 0
var failures := 0
var world
var builder
var menu
var player

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)

func frames() -> void:
	for i in range(8): await get_tree().process_frame

func snap(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	await get_tree().create_timer(2.0, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + name + ".png")

func place(id: String) -> Node2D:
	if not builder.build_mode: builder.start_build_mode()
	builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(id), 0)
	builder.create_preview()
	for x in range(builder.floor.columns):
		for y in range(builder.floor.rows):
			var cell := Vector2i(x, y)
			if builder.can_place(cell):
				return builder.build_placement_service.place_furniture(id, cell)
	return null

func end_build() -> void:
	builder.confirm_build_changes()

func _ready() -> void: call_deferred("run")

func run() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames()
	OpeningJourneyFlow.initialize(world)
	builder = world.get_node("BuildManager")
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	menu = world.find_child("ManagementMenu", true, false)
	menu.space_menu.refresh()
	var construction = menu.construction_content
	var blueprint = menu.blueprint_content
	check(ShopSpaceProgression.active() and ShopSpaceProgression.phase() == "store", "fresh game starts in store only")
	check(not menu.production_button.visible and not menu.construction_button.visible and not menu.employee_button.visible, "advanced navigation hidden during core tutorial")
	check(not blueprint.production_button.visible and not blueprint.interior_button.visible and not blueprint.construction_button.visible, "future blueprint categories hidden")
	check(not world.get_node("ProductionRoom").visible and not world.get_node("WarehouseRoom").visible, "unbuilt rooms hidden")
	check(not world.get_node("ProductionRoom").enter_actor(player) and not world.get_node("WarehouseRoom").enter_actor(player), "unbuilt room entry rejected")
	check(not ShopSpaceProgression.furniture_visible("production_door") and not ShopSpaceProgression.furniture_visible("warehouse_rack"), "starting stock does not unlock future rooms")
	var door_count := GameState.get_furniture_count("warehouse_door")
	check(builder.build_placement_service.place_furniture("warehouse_door", Vector2i(0, 1)) == null and GameState.get_furniture_count("warehouse_door") == door_count, "placement service rejects early warehouse without consuming")
	var cash := GameState.money
	check(not FurnitureObjectCatalog.craft("warehouse_door") and GameState.money == cash, "early crafting cannot bypass progression")
	menu.open_menu(ManagementMenu.MenuTab.CONSTRUCTION)
	check(menu.current_tab == ManagementMenu.MenuTab.INVENTORY, "direct early menu request cannot bypass navigation")
	await snap("store")
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional", false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 1)
	check(not ShopSpaceProgression.production_offered(), "core completion alone waits for resident settlement")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", 1)
	menu.space_menu.refresh()
	check(menu.construction_button.visible and not menu.production_button.visible, "first settlement offers preparation without premature production")
	menu.select_tab(ManagementMenu.MenuTab.CONSTRUCTION)
	check(not construction.expand_button.visible and not construction.next_info_label.text.contains("5000"), "before explanation only next preparation is shown")
	var tutorial = world.get_node("TutorialDirector")
	tutorial.flow.introduce(TutorialDirector.SETTINGS.steps[-1])
	check(ShopSpaceProgression.production_introduced() and not ShopSpaceProgression.room_ready("production"), "real introduction unlocks plan without constructing room")
	menu.space_menu.refresh()
	construction.refresh_view()
	check(construction.expand_button.text == "생산실 문 배치" and not construction.expand_button.disabled, "first construction action places owned door")
	check(builder.build_placement_service.place_furniture("magic_oven", Vector2i(1, 1)) == null, "first oven cannot bypass production room by placement in store")
	check(blueprint.production_button.visible and not blueprint.interior_button.visible and not blueprint._get_visible_furniture_ids().has("warehouse_door"), "only first facilities available")
	await snap("production-plan")
	construction._on_expand_button_pressed()
	for i in range(180):
		await get_tree().process_frame
		if builder.build_mode: break
	check(builder.build_mode and builder.get_selected_build_id() == "production_door" and not ShopSpaceProgression.room_ready("production"), "actual construction button starts preview without unlocking")
	var production_count := GameState.get_furniture_count("production_door")
	var production_door := place("production_door")
	check(production_door != null and GameState.get_furniture_count("production_door") == production_count - 1 and ShopSpaceProgression.room_ready("production"), "real successful door placement constructs production room once")
	end_build()
	var middle_save := GameState.create_save_data().duplicate(true)
	check(GameState.apply_save_data(middle_save) and ShopSpaceProgression.room_ready("production") and not ShopSpaceProgression.room_ready("warehouse") and GameState.get_furniture_count("production_door") == production_count - 1, "midway save preserves first room without duplication or premature warehouse")
	player.global_position = production_door.global_position
	check(player.try_use_production_door() and player.in_production_room and ShopSpaceProgression.marked("production_entered"), "actual E route enters built production room")
	check(not ShopSpaceProgression.furniture_visible("warehouse_door") and not ShopSpaceProgression.expansion_ready(), "room construction alone does not skip first product")
	PlayerProgress.learn_recipe("camp_bread")
	var oven = place("magic_oven")
	check(oven != null, "tutorial oven placed in production room")
	end_build()
	# 실제 출력 신호를 기존 튜토리얼의 수령 처리에 연결한다.
	tutorial.enabled = true
	tutorial.set_process(false)
	oven.output_collected.connect(tutorial._on_output_collected)
	var wheat_before := GameState.get_item_count("wheat")
	check(oven.start_production("camp_bread", 1) and GameState.get_item_count("wheat") == wheat_before - 2, "real first recipe consumes actual ingredients")
	oven._process(50.0)
	check(oven.collect_production() and ShopSpaceProgression.first_product(), "actual finished output unlocks warehouse stage")
	player.global_position = world.get_node("ProductionRoom").get_entry_world_position()
	check(player.try_use_production_door() and not player.in_production_room, "return route remains available")
	menu.open_menu(ManagementMenu.MenuTab.CONSTRUCTION)
	menu.space_menu.refresh()
	construction.refresh_view()
	check(construction.warehouse_button.visible and not construction.store_button.visible and construction.expand_button.text == "창고 문 배치", "warehouse construction precedes all expansion tabs")
	check(blueprint.interior_button.visible and ShopSpaceProgression.furniture_visible("drink_machine"), "first product reveals additional equipment and decoration")
	await snap("warehouse-plan")
	construction._on_expand_button_pressed()
	for i in range(180):
		await get_tree().process_frame
		if builder.build_mode: break
	var warehouse_door := place("warehouse_door")
	check(warehouse_door != null and ShopSpaceProgression.room_ready("warehouse") and not ShopSpaceProgression.expansion_ready(), "warehouse constructed but not yet used")
	end_build()
	player.global_position = warehouse_door.global_position
	check(player.try_use_warehouse_door() and player.in_warehouse_room, "actual E route enters built warehouse")
	var rack = place("warehouse_rack")
	check(rack != null, "existing rack can be installed after warehouse construction")
	end_build()
	check(rack.deposit_from_inventory("wheat", 0) == 0 and not ShopSpaceProgression.expansion_ready(), "failed deposit unlocks nothing")
	check(rack.deposit_from_inventory("wheat", 1) == 1 and ShopSpaceProgression.expansion_ready(), "actual inventory transfer unlocks expansion")
	var level := GameState.get_store_expansion_level()
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.apply_save_data(saved) and ShopSpaceProgression.expansion_ready() and GameState.get_store_expansion_level() == level, "full save reload keeps milestones without granting expansion")
	player.global_position = world.get_node("WarehouseRoom").get_entry_world_position()
	check(player.try_use_warehouse_door() and not player.in_warehouse_room, "warehouse return remains available")
	menu.open_menu(ManagementMenu.MenuTab.CONSTRUCTION)
	construction.refresh_view()
	check(construction.store_button.visible and construction.production_room_button.visible and construction.warehouse_button.visible and construction.next_info_label.text.contains("5000"), "original expansion UI revealed only after warehouse experience")
	await snap("expansion")
	var popup := ConfirmationDialog.new()
	construction.add_child(popup)
	manager.current_hour = 12
	GameState.money = 10000
	construction._confirm_store_expansion(popup)
	check(GameState.get_store_expansion_level() == level and GameState.money == 10000, "confirmation rechecks preparation hour without charging")
	await frames()
	manager.current_hour = 6
	manager.shop_open = false
	construction._request_store_expansion()
	var actual_popup: ConfirmationDialog
	for child in construction.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion(): actual_popup = child
	check(actual_popup != null, "actual expansion confirmation available at preparation time")
	if actual_popup != null: actual_popup.confirmed.emit()
	check(GameState.get_store_expansion_level() == level + 1 and GameState.money == 5000, "original expansion applies once at original cost after progression")
	menu.close_menu()
	# 이전 저장은 이미 마련한 공간을 소급 잠그지 않는다.
	PlayerProgress.story_beat_days.erase(ShopSpaceProgression.VERSION)
	PlayerProgress.story_beat_days.erase("tutorial_step:production:intro")
	ShopSpaceProgression.adopt_tutorial_save(world)
	check(not ShopSpaceProgression.active() and ShopSpaceProgression.room_ready("warehouse") and ShopSpaceProgression.expansion_ready(), "existing built-room save preserves all functionality")
	GameState.initialize_new_game()
	check(not ShopSpaceProgression.marked("production") and not ShopSpaceProgression.marked("stored"), "new game clears old milestones")
	print("CHECK_SHOP_SPACE_PROGRESSION checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
