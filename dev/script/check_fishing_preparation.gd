extends "res://dev/script/check_fishing_runtime.gd"
func button(prefix: String) -> Button:
	for child in director.panel.body.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false, "missing button " + prefix)
	return null
func text() -> String:
	var lines: Array[String] = []
	for child in director.panel.body.get_children():
		if child is Label: lines.append(child.text)
	return "\n".join(lines)
func click(target: Button) -> void:
	if target == null: return
	await frames() # Let a freshly rebuilt menu finish layout before scrolling.
	director.panel.scroll.ensure_control_visible(target)
	await frames()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = target.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames()
func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames()
func talk() -> void:
	check(is_instance_valid(director.visitor), "selected story has a real NPC")
	if is_instance_valid(director.visitor):
		director.player.global_position = director.visitor.global_position + Vector2(10, 0)
		await key(KEY_E)
func drain() -> void:
	for i in range(30):
		if not director.dialogue.open: break
		await key(KEY_E)
	check(not director.dialogue.open, "dialogue completed through E input")
func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--snap="): continue
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=") + "-" + label + ".png")
func request_panel() -> void:
	director.location = "fish_bank"
	director.open_menu()
	await click(button("이어가기 · 오늘 저녁"))
	await talk()
	check(director.mode == "menu", "NPC E opens accepted fish delivery")
func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Use the isolated foodbag_checks project; do not run against player saves.")
		get_tree().quit(2); return
	var original := GameState.create_save_data()
	reset(); core()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world); get_tree().current_scene = world
	await frames(12)
	director = world.get_node("FishingDirector")
	director.manager.current_hour = 12
	director.manager.hour_timer.start(999); director.manager.hour_timer.paused = false
	director.player.global_position = director.spots.position_for("fish_bank")
	check(world.get_node("WorldInteractions").try_interact(), "real bank interaction opens introduction")
	check(text().contains(UiText.t("fishing.preparation.intro")), "unread intro directs to observation and local NPC")
	await key(KEY_ESCAPE)
	FishingRecords.mark("fishing_intro:done")
	director.open_menu()
	check(text().contains(UiText.t("fishing.preparation.rod_intro")), "rod story precedes material crafting")
	await key(KEY_ESCAPE)
	check(FishingContent.accept("fishing_rod", 12, "clear"), "accepted rod fixture uses actual condition")
	director.open_menu()
	var before := PlayerProgress.to_save_data().duplicate(true)
	var cash := GameState.get_money()
	check(text().contains("전달 가능 0 / 필요 2") and text().contains("원정"), "empty carried materials show exact deficit and reachable source")
	check(button("낚싯대 드리우기").disabled, "no carried rod means no casting")
	check(PlayerProgress.to_save_data() == before and GameState.get_money() == cash, "guidance grants no progress or cash")
	await snap("materials")
	await click(button("타블렌과 소박한")); await talk()
	check(text().contains("전달 가능 0 / 필요 2"), "actual NPC tool panel also shows material deficit")
	await click(button("준비한 재료로"))
	check(not FishingService.has_rod() and not FishingRecords.has("tool:fishing_rod_wood"), "insufficient materials grant no rod or craft record")
	GameState.add_item("dry_branch", 2); GameState.add_item("amber_sap", 1)
	await click(button("준비한 재료로"))
	check(FishingService.has_rod() and GameState.get_item_count("dry_branch") == 0 and GameState.get_item_count("amber_sap") == 0, "actual NPC button consumes only existing materials and creates one rod")
	await key(KEY_ESCAPE); director.location = "fish_bank"; director.open_menu()
	check(text().contains(UiText.t("fishing.preparation.finish_rod")) and button("낚싯대 드리우기").disabled, "received rod still needs existing final conversation")
	await click(button("이어가기 · 가지로")); await talk(); await click(button("준비한 물품 전달")); await drain()
	check(FishingRecords.done("fishing_rod"), "real final conversation completes rod introduction")
	var storage = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	world.add_child(storage); await frames()
	check(storage.deposit_from_inventory_to_slot(0, "fishing_rod_wood", 1) == 1, "player can really store rod on warehouse shelf")
	director.location = "fish_bank"; director.open_menu()
	check(text().contains("창고 선반에 1개") and button("낚싯대 드리우기").disabled, "stored rod tells withdrawal route without enabling remote tool use")
	await snap("stored-rod"); await key(KEY_ESCAPE)
	check(storage.withdraw_slot_to_inventory(0, 1) == 1, "actual shelf withdrawal returns rod")
	director.player.global_position = director.spots.position_for("fish_bank")  # 창고에서 돌아온 뒤 부두 끝에 선 상태로 드리운다
	director.open_menu(); await click(button("낚싯대 드리우기"))
	check(director.mode == "waiting" and not director.manager.hour_timer.paused, "withdrawn rod casts and keeps world time running")
	director.remaining = 0; director._process(0.01); await key(KEY_E)
	check(director.mode == "reeling" and not FishingRecords.has("catch"), "E at bite starts reeling instead of granting a fish")
	director.reel_game.progress = 1.0; director._process(0.01)
	check(FishingRecords.has("catch") and director.mode == "closed", "landing the reel receives one actual fish after waiting fixture")
	FishingRecords.mark("fishing_first_catch:done")
	check(FishingContent.accept("fish_request_neighbor", 12, "clear"), "actual catch opens neighbor request")
	for fish in FishingData.group("fish_any_fresh"): GameState.remove_item(str(fish), GameState.get_item_count(str(fish)))
	FishingService.receive("fish_stream_minnow"); FishingService.receive("fish_stone_crucian"); FishingService.receive("fish_stone_crucian")
	await request_panel()
	var picker: OptionButton
	for child in director.panel.body.get_children():
		if child is OptionButton: picker = child
	check(picker != null and picker.item_count < FishingData.group("fish_any_fresh").size(), "delivery picker hides undiscovered seasonal and rare fish")
	check(director.choices.get("fish_any_fresh", "") == "fish_stone_crucian", "held sufficient species is initially selected instead of insufficient first entry")
	check(text().contains(UiText.t("fishing.preparation.one_kind")), "one species requirement explained without combining stacks")
	await snap("delivery")
	var close: Control = director.panel.frame.get_child(0).get_child(director.panel.frame.get_child(0).get_child_count()-1)
	check(get_viewport().get_visible_rect().encloses(close.get_global_rect()) and get_viewport().get_visible_rect().encloses(picker.get_global_rect()), "picker and fixed close button remain inside viewport")
	GameState.remove_item("fish_stone_crucian", 1)
	await click(button("준비한 물품 전달"))
	check(director.mode == "menu" and GameState.get_money() == cash, "two different species of one fish each cannot satisfy same-species delivery")
	GameState.add_item("fish_stone_crucian", 1)
	await click(button("준비한 물품 전달"))
	check(director.dialogue.open and GameState.get_item_count("fish_stone_crucian") == 2 and GameState.get_money() == cash, "starting final conversation consumes and pays nothing")
	await key(KEY_ESCAPE)
	check(not FishingRecords.done("fish_request_neighbor") and GameState.get_money() == cash, "partial conversation earns no reward")
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.apply_save_data(saved), "accepted request and caught records restore existing save")
	await request_panel()
	check(director.choices.get("fish_any_fresh", "") == "fish_stone_crucian", "reopened saved request recomputes selection from actual stock")
	await click(button("준비한 물품 전달"))
	GameState.total_day += 2
	await drain()
	check(not FishingRecords.done("fish_request_neighbor") and GameState.get_money() == cash, "fish expiring during final dialogue grants no delivery reward")
	FishingService.receive("fish_stone_crucian"); FishingService.receive("fish_stone_crucian"); FishingService.receive("fish_stream_minnow")
	await request_panel(); await click(button("준비한 물품 전달")); await drain()
	check(FishingRecords.done("fish_request_neighbor") and GameState.get_item_count("fish_stone_crucian") == 0 and GameState.get_item_count("fish_stream_minnow") == 1, "actual complete delivery consumes only chosen species")
	check(GameState.get_money() == cash + int(FishingData.entry("fish_request_neighbor")["reward"]["money"]), "existing configured reward paid once")
	check(not FishingContent.complete("fish_request_neighbor", {"fish_any_fresh":"fish_stream_minnow"}), "completed request cannot pay twice")
	check(not FishingPreparationGuide.candidates("fish_any_fresh").has("fish_moon_carp"), "rare unknown fish stays hidden after delivery")
	check(FishingPreparationGuide.candidates("fish_spring_exclusive").is_empty(), "unknown seasonal group has no invented first choice")
	FishingRecords.mark("fishing_first_sale:done")
	check(FishingContent.accept("fish_request_spring", 12, "clear"), "spring request can be accepted before discovering its seasonal fish")
	GameState.add_item("forest_herb", 1)
	director.location = "fish_bank"; director.open_menu()
	await click(button("이어가기 · 풀 향")); await talk()
	check(text().contains(UiText.t("fishing.preparation.no_candidates")) and not director.choices.has("fish_spring_exclusive"), "unknown group explains discovery without selecting an unseen species")
	var seasonal_cash := GameState.get_money()
	await click(button("준비한 물품 전달"))
	check(director.mode == "menu" and GameState.get_item_count("forest_herb") == 1 and GameState.get_money() == seasonal_cash, "no candidates cannot consume partial ingredients or pay")
	await snap("unknown-group"); await key(KEY_ESCAPE)
	GameState.add_item("fish_blossom_minnow", 1)
	director.location = "fish_bank"; director.open_menu()
	await click(button("이어가기 · 풀 향")); await talk()
	check(director.choices.get("fish_spring_exclusive", "") == "fish_blossom_minnow" and not FishingRecords.has("caught:fish_blossom_minnow"), "actually owned fish is selectable without fabricating a catch record")
	await key(KEY_ESCAPE)
	world.queue_free(); await frames()
	check(GameState.apply_save_data(original), "restore original isolated in-memory state")
	print("CHECK_FISHING_PREPARATION checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
