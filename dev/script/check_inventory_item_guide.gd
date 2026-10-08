extends Node
var checks := 0
var failures := 0
var world
var menu: ManagementMenu
var inv
var pane: InventoryDetailPane
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func card(id: String) -> ItemCard:
	inv.refresh_inventory()
	for child in inv.item_grid.get_children():
		if child is ItemCard and child.item_id == id: return child
	return null
func select(id: String) -> void:
	var found := card(id)
	check(found != null,"visible owned item: "+id)
	if found != null: found.pressed.emit()
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+label+".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.set_process(false)
	manager.customer_spawner.set_process(false)
	world.get_node("Actors/Player").set_physics_process(false)
	OpeningJourneyFlow.initialize(world)
	PlayerProgress.record_story_beat(ShopSpaceProgression.VERSION,GameState.total_day)
	GameState.inventory.clear()
	GameState.preservation_state = PreservationService.initial_state(GameState.total_day)
	menu = manager.management_menu
	menu.open_menu(ManagementMenu.MenuTab.INVENTORY)
	inv = menu.management_inventory
	pane = inv.get_node("DetailPage")
	inv.select_inventory_group(ItemData.INVENTORY_GROUP_SHELF)
	GameState.add_item("wild_berry",3)
	GameState.add_item("bread",2)
	GameState.add_item("fish_stream_minnow",2)
	GameState.add_item("spring_bud",2)
	await select("wild_berry")
	check(pane._use.visible and pane._use.text.contains("가공하지 않고도 진열해 팔 수 있는 재료"),"raw material direct sale shown in actual item details")
	check(pane._use.text.contains("소지 3개") and pane._use.text.contains("진열대에서 [E]"),"held stock has concrete next action")
	check(not pane._use.text.contains("배운 가공에 사용"),"first stage does not show future production chain")
	check(pane._price.text.contains(str(ItemData.get_item_price("wild_berry"))),"current catalog sale price remains displayed")
	check(pane._desc.text == str(ItemData.get_item("wild_berry").get("description","")),"original item description preserved")
	check(InventoryItemGuide.world(pane) == world,"item detail resolves current store world")
	await snap("raw")
	await select("bread")
	check(pane._acquire.text.contains("제작 안내를 들은 뒤") and not pane._acquire.text.contains("획득 방법 : 제작"),"transferred initial product does not claim it was crafted")
	check(pane._use.text.contains("기한이 있는 물품"),"perishable product has storage reminder")
	check(pane._desc.text == str(ItemData.get_item("bread").get("description","")),"initial product original flavor preserved")
	await select("fish_stream_minnow")
	check(pane._acquire.text.contains("낚시") and pane._use.text.contains("기한이 있는 물품"),"caught fish explains actual source and spoilage")
	check(not pane._use.text.contains("냉동할 수 없는"),"freezable fish not marked restricted")
	check(InventoryItemGuide.note(pane,"hand_axe").contains("판매하는 상품이 아닙니다"),"equipment never advised as store merchandise")
	check(InventoryItemGuide.note(pane,"absent_item").is_empty(),"unknown item cannot invent guide")
	check(not InventoryItemGuide.note(pane,"wild_berry").contains("지금 연결된 이야기"),"unheard requests and rumors remain hidden")
	var shelf = load("res://scenes/shop/objects/shelf.tscn").instantiate()
	world.get_node("Objects").add_child(shelf)
	await frames()
	shelf.slots[0]["item_id"] = "wild_berry"
	check(FoodShelfLife.restock_slot(shelf,0,1) == 1,"real shelf transfer from inventory")
	await select("wild_berry")
	check(pane._use.text.contains("진열 1개") and pane._use.text.contains("소지 2개"),"live shelf and held stock separated")
	check(pane._use.text.contains("집어 계산하면 판매"),"stock not counted as sold before checkout")
	var storage = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	world.get_node("WarehouseRoom/Objects").add_child(storage)
	await frames()
	check(storage.deposit_from_inventory("wild_berry",1) == 1,"real warehouse deposit")
	await select("wild_berry")
	check(pane._use.text.contains("창고 선반 1개") and pane._use.text.contains("소지 1개"),"warehouse stock shown separately and requires local withdrawal")
	check(not pane._use.text.contains("소지 2개"),"warehouse stock not treated as carried")
	check(ShopSpaceProgression.active() and not ShopSpaceProgression.production_introduced(),"first store phase precedes production introduction")
	PlayerProgress.record_story_beat("tutorial_step:production:intro",GameState.total_day)
	PlayerProgress.learn_recipe("berry_juice")
	check(InventoryItemGuide.learned_outputs("wild_berry").has("berry_juice"),"learned recipe ingredient relation")
	await select("wild_berry")
	check(pane._use.text.contains("배운 가공에 사용") and pane._use.text.contains("열매 주스"),"after introduction, known output appears as an option")
	GameState.add_item("berry_juice",1)
	await select("berry_juice")
	check(pane._acquire.text.contains("배운 제조법") and pane._use.text.contains("진열대"),"known crafted product has source and sale action")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX+"daily_berries"+":accepted",GameState.total_day)
	check(not InventoryItemGuide.note(pane,"wild_berry").contains("daily_berries"),"arbitrary story marker does not fabricate request")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX+"daily_berries"+":done",GameState.total_day)
	GameState.total_day = 28
	GameState.preservation_state["last_day"] = 28
	await select("spring_bud")
	check(pane._use.text.contains("다음 아침") and pane._use.text.contains(ItemData.get_item_name("wilted_greens")),"spring last-day transform shown from actual rule")
	check(not pane._use.text.contains("서리 얼음"),"bud details never show ice instruction")
	GameState.money = 1000
	check(PreservationService.install("fridge"),"existing paid fridge install")
	check(PreservationService.deposit("fridge","spring_bud",1) == 1,"actual cold deposit")
	await select("spring_bud")
	check(pane._use.text.contains("냉장 보관 1개") and pane._use.text.contains("소지 1개"),"cold stock shown separately from carried stock")
	var money := GameState.money
	var stock := GameState.inventory.duplicate(true)
	var progress := PlayerProgress.to_save_data().duplicate(true)
	var cold := GameState.preservation_state.duplicate(true)
	for item in ["wild_berry","bread","fish_stream_minnow","spring_bud","berry_juice"]:
		await select(item)
	check(GameState.money == money and GameState.inventory == stock and PlayerProgress.to_save_data() == progress and GameState.preservation_state == cold,"reading item options grants no money, items, progress or new cold stock")
	var save := GameState.create_save_data()
	check(GameState.apply_save_data(save),"in-memory full save round trip")
	check(InventoryItemGuide.learned_outputs("wild_berry").has("berry_juice") and InventoryItemGuide.note(pane,"spring_bud").contains("냉장 보관 1개"),"old save fields recreate learned use and stored guidance")
	inv.select_inventory_group(ItemData.INVENTORY_GROUP_EXPEDITION)
	GameState.add_item("hand_axe",1)
	await select("hand_axe")
	check(pane._use.text.contains("판매하는 상품이 아닙니다") and not pane._use.text.contains("진열대에서"),"real equipment tab does not promise sale")
	await snap("equipment")
	inv.select_inventory_group(ItemData.INVENTORY_GROUP_SHELF)
	await select("wild_berry")
	await snap("processing")
	for resolution in [Vector2i(1152,648),Vector2i(768,432)]:
		get_tree().root.size = resolution
		await frames()
		check(pane._scroll.get_global_rect().end.y <= pane.get_global_rect().end.y+1,"guide stays inside book page "+str(resolution))
	await snap("small")
	menu.close_menu()
	await get_tree().create_timer(2.0,true,false,true).timeout
	await frames()
	check(not menu.visible,"normal menu close")
	world.queue_free()
	await frames()
	print("CHECK_INVENTORY_ITEM_GUIDE checks=%d failures=%d" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
