extends Node
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func frames() -> void:
	for i in range(12): await get_tree().process_frame
func click(button: Button) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()
func text_of(guide) -> String:
	var lines: Array[String] = []
	for node in guide.list.get_children():
		if node is Label: lines.append(node.text)
	return "\n".join(lines)
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+label+".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	GameState.save_expedition_bag([])
	var expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(expedition)
	await frames()
	var prep = expedition.prep_panel
	var guide: ExpeditionLoadoutGuide = prep.get_node("LoadoutGuide")
	check(not guide.entry.is_visible_in_tree() and not guide.overlay.visible,"no equipment guide on preparation road")
	guide.display()
	check(not guide.overlay.visible,"hidden prep cannot open guide")
	prep.show_departure_choice()
	prep.show()
	await frames()
	check(not guide.entry.is_visible_in_tree(),"no guide before destination selection")
	prep.map_content.region_buttons["forest"].pressed.emit()
	await frames()
	var bag = prep.bag_content
	var placements_before: Array = bag.bag_model.placements.duplicate(true)
	var state_before := GameState.create_save_data()
	check(guide.entry.is_visible_in_tree(),"destination opens bag guide entry")
	await click(guide.entry)
	check(guide.overlay.visible and guide.current["valid"],"actual mouse opens empty bag guide")
	check(text_of(guide).contains("맨손") and not guide.current["can_swap"],"no packed weapons means unarmed, no swap")
	check(text_of(guide).contains("오른쪽으로 끌어") and text_of(guide).contains("[J / Space]"),"packing and actual basic attack controls explained")
	await snap("empty")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == guide.close_button,"Tab cannot focus departure behind guide")
	await key(KEY_E)
	check(expedition.current_expedition_phase == expedition.ExpeditionPhase.PREP and guide.overlay.visible,"interact never starts expedition behind guide")
	await key(KEY_F5)
	check(GameState.create_save_data() == state_before and bag.bag_model.placements == placements_before,"guide does not save, grant, consume or alter game state")
	await key(KEY_ESCAPE)
	check(not guide.overlay.visible and prep.visible and get_viewport().gui_get_focus_owner() == guide.entry,"Esc returns to bag without closing preparation")
	var ids := {}
	for id in ["rusty_sword","hunting_bow","leather_armor","gathering_bottle","sickle"]: ids[id] = GameState.create_owned_equipment_instance(id,1)
	bag.refresh_all()
	guide.display()
	check(guide.current["weapons"].is_empty() and guide.current["unpacked"].size() >= 5,"owned equipment is not equipped automatically")
	check(text_of(guide).contains("물병은 보유 중") and not text_of(guide).contains("물병 구매"),"owned bottle prompts packing, not duplicate buying")
	guide.close()
	var target_cells := {"rusty_sword":Vector2i(0,0),"hunting_bow":Vector2i(1,0),"leather_armor":Vector2i(3,0),"gathering_bottle":Vector2i(4,2),"sickle":Vector2i(5,0)}
	for id in target_cells:
		var uid := -1
		for placement in bag._get_owned_model().placements:
			if placement.get("instance_id",-1) == ids[id]: uid = int(placement["uid"])
		check(uid > 0 and bag._transfer_owned_to_bag(uid,target_cells[id]),"actual bag transfer "+id)
	bag._refresh_grid_views()
	guide.display()
	for placement in bag.bag_model.placements:
		if placement.get("instance_id",-1) == ids["gathering_bottle"]: bag.select_grid_item("bag",int(placement["uid"]))
	var prepared: Array = bag.bag_model.placements.duplicate(true)
	var settings = ExpeditionLoadoutGuideData.SETTINGS
	var runtime := ExpeditionWeaponLoadout.new()
	runtime.build(settings,bag.bag_model)
	check(guide.current["valid"] and guide.current["attack_name"] == runtime.active_name(),"first weapon matches live room loadout")
	check(guide.current["can_swap"] == runtime.has_choice() and text_of(guide).contains("[Q]"),"two weapon swap matches runtime")
	check(guide.current["attack_style"] == ExpeditionWeaponLoadout.get_style_text("rusty_sword"),"attack profile is the actual data profile")
	check(guide.current["armor"].size() == 1 and guide.current["tools"].size() == 2,"armor and tools count packed entries")
	check(text_of(guide).contains("물병 +1") and text_of(guide).contains("있어야 시도") and text_of(guide).contains("도구 없이도 시도"),"enhancement and required/optional gathering come from existing data")
	var gathering := ExpeditionGatheringService.new()
	var loot = load("res://script/expedition/services/expedition_loot_service.gd").new()
	check(gathering.resolve_gathering("gather_water",bag.bag_model,loot)["gathered"],"same packed tool actually gathers water")
	check(not text_of(guide).contains("공격력") and not text_of(guide).contains("방어력"),"no absolute combat stat display")
	for resolution in [Vector2i(1152,648),Vector2i(768,432),Vector2i(593,523)]:
		get_window().size = resolution
		await frames()
		guide.fit()
		await frames()
		check(get_viewport().get_visible_rect().encloses(guide.root.get_global_rect()),"guide fits viewport "+str(resolution))
		check(guide.root.get_global_rect().encloses(guide.close_button.get_global_rect()),"close outside scroll stays reachable "+str(resolution))
		guide.scroll.scroll_vertical = 9999
		await frames()
		check(guide.close_button.is_visible_in_tree(),"long list keeps close visible "+str(resolution))
		await snap(str(resolution.x))
	get_window().size = Vector2i(1152,648)
	await frames()
	guide.scroll.scroll_vertical = 0
	await snap("packed")
	await click(prep.start_button)
	check(guide.overlay.visible and expedition.current_expedition_phase == expedition.ExpeditionPhase.PREP,"backdrop blocks actual departure button click")
	await key(KEY_R)
	check(bag.bag_model.placements == prepared,"guide blocks background bag rotation")
	await key(KEY_TAB)
	await key(KEY_ENTER)
	check(not guide.overlay.visible,"keyboard confirm closes only focused guide")
	await frames()
	check(expedition.current_expedition_phase == expedition.ExpeditionPhase.PREP,"guide close cannot start expedition")
	guide.display()
	prep.select_tab(prep.PrepTab.MAP)
	check(not guide.overlay.visible,"returning to map hides independent layer")
	prep.map_content.region_buttons["forest"].pressed.emit()
	await frames()
	guide.display()
	prep.hide()
	check(not guide.overlay.visible,"closing prep leaves no modal layer")
	prep.show()
	await frames()
	guide.display()
	var first: Dictionary = bag.bag_model.placements[0]
	first["enhancement_level"] = 2
	guide.refresh()
	check(guide.current["weapons"][0]["level"] == 2,"open view reflects enhancement changes")
	first["enhancement_level"] = -1
	guide.refresh()
	check(not guide.current["valid"] and text_of(guide).contains("먼저 정리") and not text_of(guide).contains("처음 들 무기"),"invalid loadout gives real validation reason instead of active gear claim")
	first["enhancement_level"] = 1
	guide.refresh()
	guide.close()
	GameState.save_expedition_bag(bag.bag_model.placements)
	var saved := GameState.create_save_data()
	check(GameState.apply_save_data(saved),"existing save format survives with packed equipment")
	var restored := ExpeditionBag.new()
	restored.load_placements(GameState.get_saved_expedition_bag())
	var restored_summary := ExpeditionLoadoutGuideData.snapshot(restored,null)
	check(restored_summary["valid"] and restored_summary["attack_name"] == runtime.active_name() and restored_summary["tools"].size() == 2,"old placement save produces same guide")
	guide.display()
	var overlay = guide.overlay
	expedition.queue_free()
	await frames()
	check(not is_instance_valid(guide) and not is_instance_valid(overlay),"scene exit frees independent overlay")
	print("CHECK_EXPEDITION_LOADOUT_GUIDE checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
