extends Node
var checks := 0
var failures := 0
var confirmed := 0
var settlement := {}
var expedition
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames() -> void:
	for i in range(12): await get_tree().process_frame
func click(button: Button) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event,true)
	await frames()
func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		get_viewport().push_input(event,true)
	await frames()
func row(snapshot: Dictionary, item: String) -> Dictionary:
	for entry in snapshot["rows"]:
		if entry["item"] == item: return entry
	return {}
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+label+".png")
func confirm() -> void:
	confirmed += 1
	settlement = expedition.expedition_result_service.deposit_items(expedition.expedition_bag)
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	GameState.save_expedition_bag([])
	check(not ExpeditionReturnGuideData.snapshot(null)["valid"],"null bag has safe fallback")
	var bag := ExpeditionBag.new()
	var empty := ExpeditionReturnGuideData.snapshot(bag)
	check(empty["valid"] and empty["rows"].is_empty() and empty["text"].contains("남은 물품이 없습니다"),"empty return still offers normal confirmation")
	for data in [["wild_berry",Vector2i(0,0),3],["wild_berry",Vector2i(1,0),2],["winter_frost",Vector2i(2,0),1],["rusty_sword",Vector2i(3,0),1],["scroll_bake_bread",Vector2i(4,0),1],["fish_stream_minnow",Vector2i(5,0),1]]:
		check(bag.add_item(data[0],data[1],data[2]) >= 0,"real result bag placement: "+str(data[0]))
	GameState.add_item("raw_water",9)
	var initial := ExpeditionReturnGuideData.snapshot(bag)
	check(initial["valid"] and initial["rows"].size() == 5,"separate stacks aggregate by actual bag item")
	check(row(initial,"wild_berry")["amount"] == 5,"stack totals not inventory totals")
	check(row(initial,"raw_water").is_empty(),"owned but not packed item does not appear")
	check(row(initial,"wild_berry")["deposited"] and not row(initial,"rusty_sword")["deposited"],"actual item settlement policy")
	check(row(initial,"wild_berry")["text"].contains("계산을 마쳐야"),"direct sale requires actual checkout")
	check(not row(initial,"wild_berry")["text"].contains("배운 가공") and not row(initial,"wild_berry")["text"].contains("맡은 부탁"),"future crafting and unheard requests remain hidden")
	check(row(initial,"winter_frost")["text"].contains("다음 아침") and row(initial,"winter_frost")["text"].contains(ItemData.get_item_name("raw_water")),"ice actual ambient transformation")
	check(row(initial,"fish_stream_minnow")["text"].contains("기한") and not row(initial,"fish_stream_minnow")["text"].contains("남은 기한"),"perishable guidance does not invent a predeposit batch age")
	check(row(initial,"rusty_sword")["text"].contains("가방에 유지") and not row(initial,"rusty_sword")["text"].contains("진열대에서"),"equipment is retained and not merchandise")
	check(row(initial,"scroll_bake_bread")["text"].contains("아직 배우지"),"scroll possession is not learning")
	check(initial["text"].contains("챙겨 왔던 물품도") and initial["text"].contains("확인 버튼으로 재료를"),"no claim of fresh acquisition or completed deposit")
	var invalid := ExpeditionBag.new()
	invalid.placements = bag.placements.duplicate(true)
	invalid.placements.append(invalid.placements[0].duplicate(true))
	check(not ExpeditionReturnGuideData.snapshot(invalid)["valid"],"duplicate uid safe fallback")
	invalid.placements.pop_back()
	invalid.placements[0]["item_id"] = "missing_item"
	check(not ExpeditionReturnGuideData.snapshot(invalid)["valid"],"unknown item safe fallback")
	invalid.placements[0] = bag.placements[0].duplicate(true)
	invalid.placements[0]["amount"] = 0
	check(not ExpeditionReturnGuideData.snapshot(invalid)["valid"],"nonpositive amount safe fallback")
	invalid.placements[0]["amount"] = 1
	invalid.placements[0]["uid"] = -1
	check(not ExpeditionReturnGuideData.snapshot(invalid)["valid"],"negative uid safe fallback")
	PlayerProgress.record_story_beat("tutorial_step:production:intro",GameState.total_day)
	PlayerProgress.learn_recipe("berry_juice")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX+"neighbor_bread:accepted",GameState.total_day)
	var known := ExpeditionReturnGuideData.snapshot(bag)
	check(row(known,"wild_berry")["text"].contains("배운 가공") and row(known,"wild_berry")["text"].contains(ItemData.get_item_name("berry_juice")),"known recipe links ingredient without granting output")
	check(row(known,"wild_berry")["text"].contains("맡은 부탁") and row(known,"wild_berry")["text"].contains("이 물품 2개 필요"),"accepted request matches actual required amount")
	check(not row(known,"wild_berry")["text"].contains("수량 준비됨"),"predeposit never declares entire request ready")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX+"neighbor_bread:done",GameState.total_day)
	check(not row(ExpeditionReturnGuideData.snapshot(bag),"wild_berry")["text"].contains("맡은 부탁"),"completed request disappears")
	PlayerProgress.learn_recipe(RecipeUnlockData.get_recipe_id_for_scroll("scroll_bake_bread"))
	check(row(ExpeditionReturnGuideData.snapshot(bag),"scroll_bake_bread")["text"].contains("이미 배운"),"already learned scroll is not new unlock")
	for item in ItemData.items:
		if not ItemData.can_store_in_expedition_bag(item): continue
		var single := ExpeditionBag.new(12,12)
		if single.add_item(item,Vector2i.ZERO) < 0: continue
		var one := ExpeditionReturnGuideData.snapshot(single)
		check(one["valid"] and one["rows"].size() == 1 and one["rows"][0]["deposited"] == ItemData.should_deposit_after_expedition(item),"catalog deposit compatibility: "+item)
	var before := GameState.create_save_data().duplicate(true)
	var saved_bag := bag.placements.duplicate(true)
	for i in range(3): ExpeditionReturnGuideData.snapshot(bag)
	check(GameState.create_save_data() == before and bag.placements == saved_bag,"snapshot does not alter money, inventory, stories, cold storage or gear")
	check(GameState.apply_save_data(before),"existing save round trip")
	check(row(ExpeditionReturnGuideData.snapshot(bag),"wild_berry")["text"].contains("배운 가공"),"guide rebuilds from existing save fields")
	expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(expedition)
	await frames()
	expedition.expedition_bag = bag
	var panel: PanelContainer = expedition.result_panel
	var guide: ExpeditionReturnGuide = panel.get_node("ReturnGuide")
	check(not guide.entry.is_visible_in_tree() and not guide.note.visible,"no return guide in prep")
	guide.select(true)
	check(not guide.showing,"hidden result cannot open help")
	expedition.result_info_label.text = "지역의 보스를 처치했습니다!\n\n"+expedition.expedition_result_service.build_result_text(bag,"월요일")
	expedition.set_expedition_phase(expedition.ExpeditionPhase.RESULT)
	await frames()
	var original: String = expedition.result_info_label.text
	before = GameState.create_save_data().duplicate(true)
	await click(guide.entry)
	check(guide.showing and guide.note.visible and guide.note.text.contains("가방 물품 활용"),"actual result button opens help")
	check(expedition.result_info_label.text == original and expedition.result_info_label.visible,"original loot and end reason remain visible")
	check(GameState.create_save_data() == before and bag.placements == saved_bag,"opening help cannot deposit or award")
	check(panel.scroll.scroll_vertical > 0,"opening moves to usage text")
	for placement in bag.placements:
		if placement["item_id"] == "rusty_sword": expedition.selected_bag_uid = int(placement["uid"])
	await key(KEY_R)
	check(bag.placements == saved_bag,"R cannot rotate selected gear behind open usage text")
	var status: String = expedition.status_label.text
	await key(KEY_F5)
	check(expedition.status_label.text == status and GameState.create_save_data() == before,"F5 cannot save behind open help")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == panel.confirm,"Tab reaches fixed confirm from help")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == guide.entry,"Tab loops within visible result controls")
	await snap("usage")
	await key(KEY_ESCAPE)
	check(not guide.showing and not guide.note.visible and panel.scroll.scroll_vertical == 0,"Escape folds help without returning or settling")
	check(GameState.create_save_data() == before and bag.placements == saved_bag,"Escape does not settle")
	for dimensions in [Vector2i(1152,648),Vector2i(768,432),Vector2i(593,523)]:
		get_window().size = dimensions
		await frames()
		await click(guide.entry)
		check(guide.showing,"help opens after resize: "+str(dimensions))
		var viewport := get_viewport().get_visible_rect()
		check(viewport.encloses(panel.get_global_rect()),"result panel stays on screen: "+str(dimensions))
		check(panel.get_global_rect().encloses(panel.confirm.get_global_rect()),"confirm remains in result panel")
		check(not panel.scroll.get_global_rect().intersects(panel.confirm.get_global_rect()),"long help never covers confirm")
		check(not panel.scroll.get_global_rect().intersects(guide.entry.get_global_rect()),"fold button stays outside scroll")
		panel.scroll.scroll_vertical = 100000
		await frames()
		check(panel.scroll.scroll_vertical > 0,"all usage text scrolls")
		await snap(str(dimensions.x))
		await click(guide.entry)
		check(not guide.showing,"actual fold button works")
	await click(guide.entry)
	panel.hide()
	panel.show()
	await frames()
	check(not guide.showing and not guide.note.visible and panel.scroll.scroll_vertical == 0,"each result opens folded at top")
	expedition.result_info_label.text = "아이템 정산을 완료하지 못했습니다."
	await click(guide.entry)
	await click(guide.entry)
	check(expedition.result_info_label.text.contains("완료하지 못했습니다"),"help cannot overwrite settlement error")
	panel.confirm.pressed.disconnect(expedition.confirm_result_phase)
	panel.confirm.pressed.connect(confirm)
	await click(guide.entry)
	await click(panel.confirm)
	check(confirmed == 1 and settlement.get("success",false),"fixed confirm clickable with help open; real deposit succeeds")
	check(settlement.get("deposited_amount",0) == 7,"actual deposited stack total")
	check(GameState.get_item_count("wild_berry") == 5 and GameState.get_item_count("winter_frost") == 1,"materials move to actual owned inventory")
	check(bag.placements.size() == 2 and GameState.get_item_count("rusty_sword") == 0,"weapon and scroll remain in bag")
	var second: Dictionary = expedition.expedition_result_service.deposit_items(bag)
	check(second["success"] and second["deposited_amount"] == 0 and GameState.get_item_count("wild_berry") == 5,"existing settlement cannot duplicate material")
	expedition.queue_free()
	await frames()
	var standalone: PanelContainer = load("res://scenes/expedition/expedition_result.tscn").instantiate()
	add_child(standalone)
	await frames()
	check(not standalone.get_node("ReturnGuide").entry.visible,"standalone result layout has safe hidden guide")
	standalone.queue_free()
	await frames()
	print("CHECK_EXPEDITION_RETURN_GUIDE checks=%d failures=%d" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
