extends Node
var checks := 0
var failures := 0
var world
var manager
var blueprint

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	for i in range(4): await get_tree().process_frame

func materials(id: String) -> void:
	for ingredient in FurnitureRecipeData.get_recipe(id).get("ingredients", []):
		GameState.add_item(str(ingredient["item_id"]), int(ingredient["amount"]))

func clear_objects() -> void:
	for node in manager.objects.get_children(): node.free()
	manager.build_occupancy_state.clear()

func selection(id: String, rotation: int) -> void:
	manager.build_selection_state.restore_selection(manager.furniture_catalog.find(id), rotation)

func _ready() -> void:
	ManagementMenu.PRESENTATION.animations_enabled = false  # 책 여닫기 연출 중의 위치를 재지 않게 한다
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await settle()
	world.get_node("DayManager").current_hour = 6
	world.get_node("DayManager").hour_timer.stop()
	world.get_node("Actors/Player").set_physics_process(false)
	for worker in get_tree().get_nodes_in_group("worker"): worker.queue_free()
	await settle()
	manager = world.get_node("BuildManager")
	PlayerProgress.reset()
	blueprint = load("res://scenes/shared/ui/management/management_blueprint.tscn").instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	layer.add_child(blueprint)
	check(FurnitureObjectCatalog.all_ids().size() == 12, "twelve registered functional objects")
	materials("reinforced_shelf_2x1")
	var before := GameState.get_item_count("iron_ore")
	blueprint._select_furniture("reinforced_shelf_2x1")
	check(blueprint.craft_button.disabled and blueprint.description_label.text.contains("해금 조건"), "locked object stays inspectable")
	blueprint._on_craft_pressed()
	check(GameState.get_item_count("iron_ore") == before and GameState.get_furniture_count("reinforced_shelf_2x1") == 0, "stale click cannot craft or consume locked materials")
	materials("wood_shelf_1x1")
	blueprint._select_furniture("wood_shelf_1x1")
	blueprint._on_craft_pressed()
	check(GameState.get_furniture_count("wood_shelf_1x1") == 1, "real UI crafts wooden shelf")
	check(FurnitureObjectCatalog.locked_reason("reinforced_shelf_2x1").is_empty(), "wood crafting unlocks reinforced tier")
	check(blueprint.furniture_buttons["reinforced_shelf_2x1"].text.find("미해금") == -1, "crafting updates next tier list")
	blueprint._select_furniture("reinforced_shelf_2x1")
	blueprint._on_craft_pressed()
	check(GameState.get_item_count("iron_ore") == before - 3, "reinforced craft consumes exact ingredients")
	check(not FurnitureObjectCatalog.locked_reason("modern_shelf_2x1").is_empty(), "modern objects require product reconstruction story")
	PlayerProgress.record_story_beat("crafting_path:craft_first_shelf:done", GameState.total_day)
	check(FurnitureObjectCatalog.locked_reason("modern_shelf_2x1").is_empty(), "both milestones unlock modern furniture")
	var progress := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(progress)
	check(FurnitureObjectCatalog.locked_reason("modern_register").is_empty(), "craft milestones survive saved progress")
	var known_ids := BuildObjectData.get_all_build_ids()
	check(known_ids.slice(0, 3) == ["shelf_1x1", "shelf_2x1", "shelf_3x1"], "old indexed furniture retains original ordering")
	for id in FurnitureObjectCatalog.all_ids():
		var row := FurnitureObjectCatalog.get_object(id)
		var is_storage: bool = row["family"] == "warehouse_storage"
		manager._set_build_area(false, is_storage)
		clear_objects()
		blueprint._on_category_pressed("construction" if is_storage else "store")
		materials(id)
		var count := GameState.get_furniture_count(id)
		blueprint._select_furniture(id)
		check(not blueprint.craft_button.disabled, "enabled recipe: " + id)
		blueprint._on_craft_pressed()
		check(GameState.get_furniture_count(id) == count + 1, "exact output through UI: " + id)
		check(blueprint.furniture_preview.visible and blueprint.furniture_preview.display.mesh.get_surface_count() > 0, "actual model preview: " + id)
		for rotation in range(4):
			selection(id, rotation)
			var anchor := Vector2i(0, 0) if is_storage else Vector2i(3, 3)
			check(manager.can_place(anchor), "valid footprint and reserved cells: %s/%d" % [id, rotation])
			var furniture = manager.build_placement_service.place_furniture(id, anchor)
			check(is_instance_valid(furniture), "actual placement: " + id)
			if furniture == null: continue
			check(furniture.get_meta("build_id") == id, "variant identity placed")
			var shelf := ShelfData.get_shelf_data(id)
			if not shelf.is_empty():
				check(furniture.max_stack_level == int(shelf["max_stack_level"]), "tier stack limit")
				check(furniture.slots_per_level == int(shelf["slots_per_level"]) and furniture.slot_capacity == int(shelf["slot_capacity"]), "tier display capacity")
				materials(id)
				check(FurnitureObjectCatalog.craft(id), "second shelf crafted for stacking")
				selection(id, rotation)
				while manager.can_stack_on_shelf(furniture):
					manager.stack_shelf(furniture)
					if furniture.stack_level < furniture.max_stack_level:
						materials(id)
						FurnitureObjectCatalog.craft(id)
						selection(id, rotation)
				check(furniture.stack_level == furniture.max_stack_level, "configured layer count enforced")
				var slot: Dictionary = furniture.slots[0]
				slot["item_id"] = "water"
				furniture.slots[0] = slot
				check(furniture.add_stock_to_slot(0, 100) == int(shelf["slot_capacity"]), "stock respects capacity")
				check(furniture.take_items_by_id("water", 1) == 1, "customer can pick new shelf stock")
			elif is_storage:
				check(furniture.storage_capacity == int(row["storage_capacity"]) and furniture.storage_slot_count == int(row["storage_slots"]), "storage tier configured before restore")
				GameState.add_item("dry_branch", 100)
				check(furniture.deposit_from_inventory("dry_branch", 100) == int(row["storage_capacity"]), "actual warehouse deposit respects capacity")
				check(not furniture.can_remove_storage(), "loaded warehouse protected from removal")
			# Save the real placed object and rebuild by stable ID with the same rotation.
			var layout = manager.build_layout_service.collect_layout(manager.objects, Callable(manager, "get_build_id_for_furniture"))
			clear_objects()
			manager._restore_current_area_layout(layout)
			var restored = manager.objects.get_child(0)
			check(restored.get_meta("build_id") == id and restored.get_meta("rotation_index") == rotation, "variant identity and rotation restored")
			if not shelf.is_empty():
				check(restored.stack_level == int(shelf["max_stack_level"]) and restored.get_item_stock("water") == int(shelf["slot_capacity"]) - 1, "layers and stock restored without loss")
			elif is_storage:
				check(restored.get_item_count("dry_branch") == int(row["storage_capacity"]) and restored.storage_slots.size() == int(row["storage_slots"]), "warehouse contents restored with variant capacity")
			await settle()
			var view: StoreView3D = world.get_node("StoreView3D")
			view._sync_furniture()
			check(view._items.has("furn%d" % restored.get_instance_id()), "actual store/room renderer creates visible variant")
			if row["family"] == "register":
				blueprint.visible = false
				world.get_node("CheckoutTutorial").set_process(false)
				var day = world.get_node("DayManager")
				day.shop_open = true
				var player = world.get_node("Actors/Player")
				player.global_position = manager.get_cell_world_position(restored.get_worker_cells()[0])
				var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
				world.get_node("Actors").add_child(customer)
				customer.set_physics_process(false)
				customer.global_position = manager.get_cell_world_position(restored.get_checkout_cells()[0])
				customer.carried_item_id = "water"
				customer.carried_amount = 1
				customer.target_register = restored
				restored.request_checkout(customer)
				var money: int = player.money
				var checkout = world.get_node("ManualCheckoutController")
				check(checkout.try_interact() and checkout.is_busy(), "new register accepts manual checkout")
				checkout._process(2.0)
				check(customer.purchase_completed and player.money == money + ItemData.get_item_price("water"), "new register completes actual payment exactly once")
				customer.free()
				day.shop_open = false
				blueprint.visible = true
			if not shelf.is_empty():
				var owned := GameState.get_furniture_count(id)
				while restored.stack_level > 1: manager.build_removal_service.remove_furniture(restored, id)
				check(not manager.build_removal_service.remove_furniture(restored, id), "stocked base layer cannot be removed")
				restored.take_items_by_id("water", 100)
				check(manager.build_removal_service.remove_furniture(restored, id) and GameState.get_furniture_count(id) == owned + int(shelf["max_stack_level"]), "reclaim returns same variant and exact layers")
				await settle()
			clear_objects()
			GameState.add_furniture(id, 1)
	# Exercise the complete save schema, including newly registered furniture IDs.
	manager._set_build_area(false, true)
	selection("steel_warehouse_rack", 1)
	var storage = manager.build_placement_service.place_furniture("steel_warehouse_rack", Vector2i.ZERO)
	GameState.add_item("dry_branch", 80)
	storage.deposit_from_inventory("dry_branch", 80)
	manager._set_build_area(false, false)
	selection("modern_shelf_2x1", 0)
	var placed = manager.build_placement_service.place_furniture("modern_shelf_2x1", Vector2i(2, 2))
	var stock: Dictionary = placed.slots[0]
	stock["item_id"] = "water"
	placed.slots[0] = stock
	placed.add_stock_to_slot(0, 3)
	manager.save_store_layout()
	var saved := GameState.create_save_data()
	check(GameState.is_save_data_valid(saved), "full save schema accepts all new furniture IDs")
	check(GameState.write_save_file(saved, "user://furniture_objects.dat"), "serialized save writes to isolated test userdata")
	var loaded := GameState.read_save_file("user://furniture_objects.dat")
	PlayerProgress.reset()
	check(GameState.apply_save_data(loaded), "serialized save applies without dropping unknown variants")
	check(FurnitureObjectCatalog.locked_reason("modern_shelf_2x1").is_empty(), "full save restores tier milestones")
	manager._set_build_area(false, true)
	clear_objects()
	manager._set_build_area(false, false)
	clear_objects()
	manager.restore_store_layout()
	check(manager.store_objects.get_child(0).get_item_stock("water") == 3, "full saved store stock restored")
	check(manager.warehouse_objects.get_child(0).get_item_count("dry_branch") == 80, "full saved warehouse stock restored")
	blueprint.visible = false
	var menu: ManagementMenu = world.get_node("DayManager").management_menu
	menu.open_menu(ManagementMenu.MenuTab.BLUEPRINT)
	var actual = menu.blueprint_content
	actual._select_furniture("modern_shelf_2x1")
	await settle()
	check(actual.furniture_preview.visible and actual.furniture_preview.display.mesh != null, "preview appears inside actual paused management menu")
	var button_rect: Rect2 = actual.craft_button.get_global_rect()
	check(get_viewport().get_visible_rect().encloses(button_rect) and button_rect.size.y >= 48, "craft button remains visible without scrolling details")
	var details: ScrollContainer = actual.get_node("MainVBox/Body/DetailPanel/DetailScroll")
	details.scroll_vertical = 10000
	await settle()
	check(actual.craft_button.get_global_rect() == button_rect, "long description scroll does not move craft button")
	details.scroll_vertical = 0
	# The actual crafting page can be captured for visual verification without authoring assets.
	var args := OS.get_cmdline_user_args()
	if args.has("--shot"):
		var shot_path: String = args[args.find("--shot") + 1]
		await get_tree().create_timer(0.7).timeout
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
	menu.close_menu()
	# Older furniture remains buildable even if new reconstruction milestones are absent.
	PlayerProgress.reset()
	check(FurnitureObjectCatalog.locked_reason("shelf_1x1").is_empty() and FurnitureObjectCatalog.locked_reason("register").is_empty(), "legacy furniture unaffected")
	materials("modern_register")
	before = GameState.get_item_count("mine_crystal")
	check(not FurnitureObjectCatalog.craft("modern_register") and GameState.get_item_count("mine_crystal") == before, "direct API also guards locked crafting")
	check(not FurnitureObjectCatalog.craft("not_registered"), "unknown IDs cannot craft")
	print("CHECK_FURNITURE_OBJECTS checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
