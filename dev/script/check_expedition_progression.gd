extends "res://dev/script/check_expedition_loadout_guide.gd"
## Complete opening is a fixture. Actual bag transfer, inputs, collision walking,
## gather rolls, loot organization, withdrawal and settlement are exercised.
var inst
var controller: ExpeditionRoomController
var confirm_count := 0
var deposited := {}

func launch(region: String = "river_valley", pack: bool = false) -> void:
	var saved: Array[Dictionary] = []
	if pack and is_instance_valid(inst): saved.assign(inst.expedition_bag.placements.duplicate(true))
	GameState.save_expedition_bag(saved)
	if is_instance_valid(inst): inst.queue_free(); await frames()
	inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await frames()
	inst.get_node("ExpeditionClock").set_process(false)
	var prep = inst.prep_panel
	prep.show_departure_choice()
	prep.show()
	prep.map_content._select_region(region)
	await get_tree().create_timer(0.6).timeout
	await frames()
	if pack:
		var cells := {"gathering_bottle":Vector2i(4,2),"rusty_sword":Vector2i(0,0),"hunting_bow":Vector2i(1,0)}
		for id in cells:
			if prep.bag_content.bag_model.placements.any(func(entry): return entry["item_id"] == id): continue
			var uid := -1
			for entry in prep.bag_content._get_owned_model().placements:
				if entry["item_id"] == id: uid = int(entry["uid"])
			check(uid > 0 and prep.bag_content._transfer_owned_to_bag(uid,cells[id]),"real packing of " + id)
		prep.bag_content._refresh_grid_views()
	await click(prep.start_button)
	check(inst.current_expedition_phase == inst.ExpeditionPhase.RUN,"actual departure button accepts valid bag " + region)
	controller = inst.expedition_room_controller

func enter(event: Dictionary, kind: String) -> ExpeditionRoomModel:
	var current: Dictionary = inst.expedition_map.get_node(inst.current_map_node_id)
	inst.selected_map_node_id = str(current["next"][0])
	controller.enter(event,kind)
	controller.view.set_physics_process(false)
	return controller.model

func walk(target: Vector2) -> void:
	var model := controller.model
	var grid := ExpeditionRoomTestDriver._walk_grid(model)
	for i in range(2000):
		if model.player_position.distance_to(target) < model.settings.interaction_reach * 0.65: break
		model.step(1.0/60.0,ExpeditionRoomTestDriver._walk_direction(model,target,grid),false)
		if i % 120 == 0: await frames()
	check(model.player_position.distance_to(target) < model.settings.interaction_reach,"actual collision-respecting approach")
	controller.view._physics_process(0.0)
	await frames()

func room_button(text: String) -> Button:
	for button in controller.view.find_children("*","Button",true,false):
		if button.text == text: return button
	return null

# Embedded windows route mouse input from the root at their window position.
func popup_click(button: Button) -> void:
	await frames()
	var window := button.get_window()
	var viewport: Viewport = get_viewport() if window.is_embedded() else window
	var at := button.get_global_rect().get_center()
	if window.is_embedded(): at += Vector2(window.position)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event,true)
	await frames()

func settle_result() -> void:
	confirm_count += 1
	deposited = inst.expedition_result_service.deposit_items(inst.expedition_bag)

func run() -> void:
	check(OS.get_user_data_dir().contains("foodbag_checks"),"isolated expedition audit project")
	if not OS.get_user_data_dir().contains("foodbag_checks"): get_tree().quit(1); return
	GameState.initialize_new_game()
	PlayerProgress.reset()
	GameState.inventory.clear()
	seed(8123)
	await launch()
	check(inst.expedition_bag.placements.is_empty(),"no equipment is silently granted for empty-bag departure")
	var model := enter({"event_id":"river_valley_gather_choice","result_type":"loot","target_id":"gather_water"},ExpeditionMap.NODE_GATHER)
	check(model.gathering_sites.size() == 2 and model.exit_open,"existing water and reed choice with optional exit")
	var water := Vector2(float(model.gathering_sites[0]["x"]),float(model.gathering_sites[0]["y"]))
	var reeds := Vector2(float(model.gathering_sites[1]["x"]),float(model.gathering_sites[1]["y"]))
	await walk(water)
	check(controller.view.hint_label.text.contains("물병"),"near water names actual missing tool")
	check(controller.view.hint_label.text.contains("채집 기회는 남아") and controller.view.hint_label.text.contains("다른 지점"),"blocked gathering explains remaining choice")
	var state := GameState.create_save_data().duplicate(true)
	seed(919)
	var expected_roll := randf()
	seed(919)
	for i in range(3): model.interact()
	check(randf() == expected_roll and not model.interacting and not model.object_consumed and controller.pending_loot.is_empty(),"rejected prerequisite consumes no roll, reward or room opportunity")
	check(GameState.create_save_data() == state,"prerequisite query changes no inventory, cash or progress")
	await click(controller.view.interact_button)
	await key(KEY_E)
	model.step(2.0,Vector2.ZERO,false)
	check(not model.interacting and not model.object_consumed,"real button and E both reject missing tool without starting timer")
	var bottle: int = GameState.create_owned_equipment_instance("gathering_bottle",0)
	controller.view._physics_process(0.0)
	check(bottle > 0 and controller.view.hint_label.text.contains("준비되지"),"owned bottle left at store does not count as packed")
	await snap("missing-tool")
	await walk(reeds)
	check(model.selected_loot_table == "choice_marsh_reed" and controller.view.interact_button.text.contains("갈대"),"walking reaches actual alternative site and updates button")
	await key(KEY_E)
	check(model.interacting and not model.object_consumed,"actual E begins available reed gathering")
	model.step(model.interaction_seconds()*0.4,Vector2.ZERO,false)
	controller.view._physics_process(0.0)
	check(controller.view.hint_label.text.contains("갈대") and controller.view.hint_label.text.contains("%"),"gather progress names actual action")
	model.step(0.1,Vector2.RIGHT,false)
	check(not model.interacting and model.interaction_progress == 0.0 and not model.object_consumed,"movement cancels gathering without consuming opportunity")
	await click(controller.view.interact_button)
	model.step(model.interaction_seconds()*0.2,Vector2.ZERO,false)
	check(model.basic_attack() and not model.interacting and not model.object_consumed,"basic attack cancels in-progress gathering")
	await key(KEY_E)
	model.step(model.interaction_seconds()+0.1,Vector2.ZERO,false)
	controller.view._physics_process(0.0)
	check(model.object_consumed and controller.pending_loot.size() == 1,"alternative site yields exactly one existing room reward")
	var reward := controller.pending_loot.duplicate(true)
	model.interact()
	model.step(2.0,Vector2.ZERO,false)
	check(controller.pending_loot == reward,"same site cannot grant duplicate reward")
	check(controller.view.hint_label.text.contains("획득") and controller.view.hint_label.text.contains("출구") and controller.view.hint_label.text.contains("[E]"),"reward feedback retains explicit next-room action")
	await snap("gathered")
	await walk(model.exit_position)
	await click(controller.view.interact_button)
	check(not controller.is_active() and inst.loot_panel.visible and inst.temporary_loot == reward,"actual exit presents pending loot before map continues")
	check(not model.interaction_guard.is_valid(),"closed room releases transient prerequisite hook")
	inst.confirm_loot_organization()
	check(inst.discard_loot_dialog.visible and not inst.temporary_loot.is_empty(),"unpacked loot requires existing discard review")
	await popup_click(inst.discard_loot_dialog.get_cancel_button())
	check(not inst.discard_loot_dialog.visible and inst.loot_panel.visible and inst.temporary_loot == reward,"actual cancel closes review and keeps reward available")
	var item: String = str(reward[0]["item_id"])
	var amount: int = int(reward[0]["amount"])
	var drag := {"source":"loot","loot_index":0,"item_id":item,"amount":amount,"rotated":false}
	check(inst.expedition_bag_controller.can_drop_grid_data("bag",drag,Vector2i.ZERO),"actual loot transfer can fit gathered material")
	inst.expedition_bag_controller.drop_grid_data("bag",drag,Vector2i.ZERO)
	check(inst.temporary_loot.is_empty() and inst.expedition_bag.placements.size() == 1,"actual loot packing removes the source exactly once")
	inst.confirm_loot_organization()
	check(inst.map_panel.visible and not inst.loot_panel.visible,"packed reward returns to branch map")
	await click(controller.map_retreat_button)
	check(inst.current_expedition_phase == inst.ExpeditionPhase.RESULT and inst.current_end_reason == inst.ExpeditionEndReason.RETREAT,"actual map withdrawal keeps packed goods in result")
	var panel = inst.result_panel
	panel.confirm.pressed.disconnect(inst.confirm_result_phase)
	panel.confirm.pressed.connect(settle_result)
	await click(panel.confirm)
	check(confirm_count == 1 and deposited.get("success",false) and GameState.get_item_count(item) == amount,"real result button settles gathered material through existing service")
	check(inst.expedition_result_service.deposit_items(inst.expedition_bag).get("deposited_amount",-1) == 0 and GameState.get_item_count(item) == amount,"second settlement cannot duplicate gathered goods")
	await snap("return")
	# A single unavailable water object may be skipped; no forced tool or roll.
	await launch("forest")
	model = enter({"result_type":"loot","target_id":"gather_water"},ExpeditionMap.NODE_GATHER)
	await walk(model.object_position)
	check(controller.view.hint_label.text.contains(" 지나쳐도") and not model.object_consumed,"single unavailable site offers safe exit")
	check(await ExpeditionRoomTestDriver.play(controller),"actual driver walks to exit when all sites need absent tool")
	check(not model.object_consumed and controller.pending_loot.is_empty(),"skipping required tool grants and consumes nothing")
	# Optional wheat failure remains one attempt, rather than free rerolls.
	model = enter({"event_id":"meadow_gather_choice","result_type":"loot","target_id":"gather_wheat"},ExpeditionMap.NODE_GATHER)
	await walk(Vector2(float(model.gathering_sites[0]["x"]),float(model.gathering_sites[0]["y"])))
	var failure_seed := 0
	for n in range(100):
		seed(n)
		if randf() > 0.4: failure_seed = n; break
	seed(failure_seed)
	model.interact()
	model.step(model.interaction_seconds()+0.1,Vector2.ZERO,false)
	controller.view._physics_process(0.0)
	check(model.object_consumed and controller.pending_loot.is_empty() and controller.view.notice.contains("실패"),"existing optional no-tool random failure still consumes one chance")
	check(controller.view.hint_label.text.contains("실패") and controller.view.hint_label.text.contains("출구"),"random failure also points to next action")
	model.interact()
	check(not model.interacting,"failed attempted roll cannot be retried")
	# Restart with actual owned-to-bag transfer, not fabricated effect flags.
	GameState.create_owned_equipment_instance("rusty_sword",0)
	GameState.create_owned_equipment_instance("hunting_bow",0)
	await launch("river_valley",true)
	model = enter({"event_id":"river_valley_gather_choice","result_type":"loot","target_id":"gather_water"},ExpeditionMap.NODE_GATHER)
	await walk(Vector2(float(model.gathering_sites[0]["x"]),float(model.gathering_sites[0]["y"])))
	check(not controller.view.hint_label.text.contains("준비되지") and model.attack_profile.equipment_id == "rusty_sword","packed bottle permits gathering and first packed weapon is active")
	await key(KEY_Q)
	check(model.attack_profile.equipment_id == "hunting_bow" and model.attack_remaining >= model.settings.weapon_swap_delay,"actual Q changes equipped basic attack with existing delay")
	await click(controller.view.interact_button)
	model.step(model.interaction_seconds()+0.1,Vector2.ZERO,false)
	controller.view._physics_process(0.0)
	check(model.object_consumed and controller.pending_loot.size() == 1 and controller.pending_loot[0]["item_id"] == "raw_water","actual bottle gathers existing water reward")
	await click(room_button("철수"))
	check(controller.retreat_pending and inst.loot_panel.visible and inst.current_expedition_phase == inst.ExpeditionPhase.RUN,"room withdrawal offers gathered pending loot before final result")
	inst.confirm_loot_organization()
	check(inst.discard_loot_dialog.visible,"pending withdrawal still protects unpacked goods")
	await popup_click(inst.discard_loot_dialog.get_ok_button())
	check(inst.current_expedition_phase == inst.ExpeditionPhase.RESULT and inst.current_end_reason == inst.ExpeditionEndReason.RETREAT and not controller.retreat_pending,"confirmed discard finishes withdrawal once")
	# Basic attack and movement buttons remain functional; combat exit stays locked.
	await launch("forest",true)
	model = enter({"result_type":"battle","target_id":"field_slime"},ExpeditionMap.NODE_BATTLE)
	check(not model.exit_open and model.alive_enemies() == 2,"actual battle keeps exit locked until enemies cleared")
	var position := model.player_position
	Input.action_press("move_right")
	controller.view._physics_process(0.2)
	Input.action_release("move_right")
	check(model.player_position != position,"actual movement input changes room position")
	var total_before := int(model.enemies[0]["hp"]) + int(model.enemies[1]["hp"])
	await click(controller.view.attack_button)
	check(int(model.enemies[0]["hp"]) + int(model.enemies[1]["hp"]) == total_before,"far basic attack cannot damage distant enemies")
	var grid := ExpeditionRoomTestDriver._walk_grid(model)
	for i in range(900):
		var target: Vector2 = model.enemies[0]["position"]
		if model.player_position.distance_to(target) <= model.attack_profile.reach*0.7: break
		model.step(1.0/60.0,ExpeditionRoomTestDriver._walk_direction(model,target,grid),false)
	model.step(model.attack_profile.cooldown,Vector2.ZERO,false)
	await click(controller.view.attack_button)
	check(int(model.enemies[0]["hp"]) + int(model.enemies[1]["hp"]) < total_before,"actual attack button hits approached enemy with equipped basic attack")
	await snap("combat")
	check(await ExpeditionRoomTestDriver.play(controller),"existing movement/basic-attack driver clears real battle without injected HP")
	check(model.alive_enemies() == 0 and model.exit_open,"actual enemy defeat opens exit")
	# Other object interactions keep their real action names and one-use result.
	for spec in [{"result_type":"loot","target_id":"forest_gather"},{"result_type":"heal","value":20}]:
		model = enter(spec,ExpeditionMap.NODE_UNKNOWN)
		await walk(model.object_position)
		await key(KEY_E)
		model.step(model.interaction_seconds()*0.4,Vector2.ZERO,false)
		controller.view._physics_process(0.0)
		check(model.interacting and controller.view.hint_label.text.contains("열기" if spec["result_type"] == "loot" else "휴식"),"chest/rest progress names actual interaction")
		model.step(model.interaction_seconds(),Vector2.ZERO,false)
		controller.view._physics_process(0.0)
		check(model.object_consumed and controller.view.hint_label.text.contains("출구"),"chest/rest completion retains exit action")
		check(await ExpeditionRoomTestDriver.play(controller),"chest/rest exits through existing movement and interaction")
	print("CHECK_EXPEDITION_PROGRESSION checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
