extends Node
var checks := 0
var failures := 0
var inst
var prep
var access: ExpeditionSupplyAccess
var shop
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frames() -> void:
	for i in range(10): await get_tree().process_frame
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + label + ".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await frames()
	prep = inst.prep_panel
	prep.show_departure_choice()
	prep.show()
	access = prep.get_node("SupplyAccess")
	shop = access.shop
	await frames()
	check(not access.entry.visible,"no shop before the arrival merchant barter")
	check(GameState.get_owned_equipment_count("gathering_bottle") == 0,"tutorial starts without water tool")
	var gathering := ExpeditionGatheringService.new()
	var loot = load("res://script/expedition/services/expedition_loot_service.gd").new()
	check(not gathering.resolve_gathering("gather_water",prep.bag_content.bag_model,loot)["gathered"],"water cannot be collected with empty expedition bag")
	PlayerProgress.record_story_beat(OpeningJourneyFlow.VERSION,GameState.total_day)
	PlayerProgress.record_story_beat("tutorial_step:checkout:done",GameState.total_day)
	PlayerProgress.record_story_beat("tutorial_step:barter:intro",GameState.total_day)
	check(OpeningJourneyFlow.trade(),"existing initial barter succeeds with convenience products")
	await frames()
	check(access.entry.visible,"shop access appears after actual barter before first expedition")
	await snap("entry")
	var price := ExpeditionShopData.get_price("gathering_bottle")
	var first_sale := ItemData.get_item_price("water")
	check(price > 0 and price <= first_sale,"one opening water sale can cover existing bottle price")
	access.entry.pressed.emit()
	await frames()
	check(shop.visible and not prep.start_button.visible and not prep.bag_content.visible,"shop is visible and blocks departure and bag interactions")
	await snap("listing")
	var bottle_button: Button
	for child in shop.shop_item_list.get_children():
		if child is Button and child.text.contains(ItemData.get_item_name("gathering_bottle")) and not child.is_queued_for_deletion(): bottle_button = child
	check(bottle_button != null,"default tool category contains actual water bottle")
	if bottle_button == null: get_tree().quit(1); return
	bottle_button.pressed.emit()
	check(shop.detail_overlay.visible and shop.buy_button.disabled,"zero money purchase is unavailable")
	shop.buy_button.pressed.emit()
	check(GameState.get_money() == 0 and GameState.get_owned_equipment_count("gathering_bottle") == 0,"insufficient funds never grant a tool or subtract money")
	GameState.add_money(first_sale)
	bottle_button.pressed.emit()
	check(not shop.buy_button.disabled and shop.item_price_label.text.contains(str(price)),"real catalog price enables purchase after first sale")
	await snap("purchase")
	shop.buy_button.pressed.emit()
	check(GameState.get_money() == first_sale - price and GameState.get_owned_equipment_count("gathering_bottle") == 1,"buy creates one owned equipment instance and pays actual price")
	check(not gathering.resolve_gathering("gather_water",prep.bag_content.bag_model,loot)["gathered"],"owning bottle alone does not bypass bag packing requirement")
	var money := GameState.get_money()
	shop.buy_button.pressed.emit()
	check(GameState.get_money() == money and GameState.get_owned_equipment_count("gathering_bottle") == 1,"repeated purchase cannot duplicate unique tool")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	access._input(escape)
	check(shop.visible and not shop.detail_overlay.visible,"first Escape closes item detail")
	access._input(escape)
	check(not shop.visible and prep.current_tab == 0,"second Escape returns to same preparation view")
	prep.map_content.region_buttons["forest"].pressed.emit()
	await frames()
	var bag = prep.bag_content
	check(prep.get_selected_region_id() == "forest" and bag.visible,"original destination selection and bag view work")
	var uid := -1
	for placement in bag._get_owned_model().placements:
		if placement["item_id"] == "gathering_bottle": uid = int(placement["uid"])
	check(uid > 0 and bag._transfer_owned_to_bag(uid,Vector2i(3,0)),"bought bottle transfers through actual owned-to-expedition bag flow")
	check(GameState.get_owned_equipment_count("gathering_bottle") == 0 and shop._is_unique_tool_owned("gathering_bottle"),"bottle in expedition bag remains uniquely owned")
	var gathered := 0
	for attempt in range(3):
		var water: Dictionary = gathering.resolve_gathering("gather_water",bag.bag_model,loot)
		check(water["gathered"] and water["item_id"] == "raw_water","packed purchased bottle collects native raw water")
		if water["gathered"]: gathered += int(water["amount"])
		if gathered >= 2: break
	check(gathered >= 2,"repeated water sites can meet first two-bottle request")
	GameState.add_item("raw_water",gathered)
	for step in OpeningJourneyFlow.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat("resident_request:neighbor_bread:done",GameState.total_day)
	var request := ResidentRequestFlow.current()
	check(request.get("id", "") == "traveler_water" and ResidentRequestFlow.accept(request),"first traveler's water request can be accepted after core tutorial")
	var hint := RequestItemSources.expedition("raw_water",ExpeditionEnvironment.capture())
	check("\n".join(hint).contains("채집용 물병") and "\n".join(hint).contains("원정 상점") and "\n".join(hint).contains("가방"),"accepted request preparation includes tool purchase and packing route")
	var stock := GameState.get_item_count("raw_water")
	var reward := ResidentRequestFlow.deliver(request)
	check(not reward.is_empty() and GameState.get_item_count("raw_water") == stock - int(request["amount"]),"water obtained with bought tool completes request with exact consumption")
	check(ResidentRequestFlow.deliver(request).is_empty(),"request reward cannot repeat")
	GameState.save_expedition_bag(bag.bag_model.placements)
	var save := GameState.create_save_data()
	check(GameState.apply_save_data(save),"in-memory save restore accepts purchased packed tool")
	check(GameState.get_saved_expedition_bag().any(func(p: Dictionary) -> bool: return p["item_id"] == "gathering_bottle"),"saved bag preserves bottle instance")
	access.entry.pressed.emit()
	await frames()
	check(shop.visible and prep.get_selected_region_id() == "forest","reopening shop preserves destination")
	for resolution in [Vector2i(1152,648),Vector2i(768,432)]:
		get_tree().root.size = resolution
		await frames()
		check(prep.get_viewport_rect().encloses(shop.get_global_rect()) and shop.get_global_rect().encloses(access.close_button.get_global_rect()),"shop and return button fit viewport " + str(resolution))
		shop._on_item_pressed("gathering_bottle")
		await frames()
		check(shop.get_global_rect().encloses(shop.buy_button.get_global_rect()) and shop.get_global_rect().encloses(shop.close_button.get_global_rect()),"detail purchase and close controls stay inside modal " + str(resolution))
		await snap("small" if resolution.x == 768 else "shop")
		shop._close_detail_popup()
	access.close_button.pressed.emit()
	check(bag.visible and prep.start_button.visible and not shop.visible,"return button restores selected destination and bag")
	check(prep.get_viewport_rect().encloses(access.entry.get_global_rect()),"entry button remains clickable inside viewport")
	inst.queue_free()
	await frames()
	print("CHECK_GATHERING_TOOL_ACCESS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
