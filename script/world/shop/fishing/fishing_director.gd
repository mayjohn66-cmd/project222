class_name FishingDirector
extends Node
var world: Node
var player: Node2D
var manager: Node
var spots: FishingSpots
var panel: FishingPanel
var dialogue: StoryDialoguePanel
var mode := "closed"
var location := ""
var remaining := 0.0
var pending_fish := ""
var pending_entry: Dictionary = {}
var pending_phase := ""
var choices: Dictionary = {}
var moon_choice := "keep"
var owns_clock := false
var previous_paused := false
var previous_physics := true
var rng := RandomNumberGenerator.new()
var status: Label
var reel_button: Button
var visitor: Node2D
var owned_visitors: Array[Node2D] = []
var meeting: Array[Node2D] = []
func _ready() -> void:
	if not bool(FishingData.data()["settings"].get("enabled", true)):
		set_process(false)
		return
	world = get_parent()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	spots = FishingSpots.new()
	spots.name = "FishingSpots"
	world.add_child.call_deferred(spots)
	panel = FishingPanel.new()
	add_child(panel)
	panel.closed.connect(func(): pending_entry.clear(); close())
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_dialogue_finished)
	rng.randomize()
func hour() -> float:
	return float(manager.current_hour) + manager.get_display_minute() / 60.0
func weather() -> String:
	return str(WorldWeatherData.forecast(GameState.total_day, hour())["kind"])
func nearest() -> String:
	if player.in_production_room or player.in_warehouse_room or not is_instance_valid(spots): return ""
	for entry in FishingData.entries("locations"):
		var id := str(entry["id"])
		if FishingContent.location_available(id, hour(), weather()) and player.global_position.distance_to(spots.position_for(id)) < float(FishingData.data()["settings"]["interaction_distance"]): return id
	return ""
func nearest_visitor() -> Node2D:
	for actor in owned_visitors:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and player.global_position.distance_to(actor.global_position) < 70: return actor
	return null
func interaction_hint() -> String:
	if world == null or mode != "closed": return ""
	if not pending_entry.is_empty() and is_instance_valid(visitor) and player.global_position.distance_to(visitor.global_position) < 70:
		return "[E] 물가 이야기 · " + str(pending_entry.get("title", "함께 낚시하기"))
	var neighbor := nearest_visitor()
	if neighbor != null: return "[E] " + _owner_name(str(neighbor.get_meta("fishing_owner", ""))) + " · 물가 이야기"
	var id := nearest()
	return "[E] " + str(FishingData.entry(id)["name"]) + " · 낚시 / 물가 이야기" if not id.is_empty() else ""
func try_interact() -> bool:
	if world == null or mode != "closed" or world.get_node("WorldInteractions").blocked(): return false
	if not pending_entry.is_empty() and is_instance_valid(visitor) and player.global_position.distance_to(visitor.global_position) < 70:
		_open_entry()
		return true
	var neighbor := nearest_visitor()
	location = str(neighbor.get_meta("fishing_location", "fish_bank")) if neighbor != null else nearest()
	if location.is_empty(): return false
	open_menu()
	return true
func _lock(pause_clock: bool) -> void:
	owns_clock = pause_clock
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	if pause_clock: manager.hour_timer.paused = true
	world.set_meta("fishing_open", true)
func close() -> void:
	if mode == "closed": return
	panel.root.hide()
	pending_fish = ""
	mode = "closed"
	world.remove_meta("fishing_open")
	if owns_clock and is_instance_valid(manager) and not manager.summary_open and not manager.closing_shop:
		manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)
func clock_running() -> bool:
	return not get_tree().paused and not manager.hour_timer.paused and not manager.hour_timer.is_stopped() \
		and not manager.summary_open and not manager.closing_shop and not manager.management_menu.visible \
		and not manager.expedition_transition_pending
func open_menu() -> void:
	mode = "menu"
	_lock(true)
	panel.clear(str(FishingData.entry(location)["name"]))
	panel.text("물가에 잠깐 앉아 볼까요? 낚는 동안에도 가게의 시간과 직원의 근무는 이어집니다.")
	var guide := FishingPreparationGuide.next_step(world, _environment())
	if not guide.is_empty(): panel.text(guide)
	panel.button("물가 살펴보기", observe)
	panel.button("낚싯대 드리우기 [E로 건지기]", cast, not FishingService.has_rod() or not FishingRecords.done("fishing_rod"))
	if FishingRecords.accepted("fishing_rod") and not FishingRecords.has("tool:fishing_rod_wood"):
		panel.button("타블렌과 소박한 낚싯대 엮기 · 가지 2 / 수액 1", func(): _rod("fishing_rod_wood"))
	if FishingRecords.done("fishing_first_sale") and not FishingRecords.has("tool:fishing_rod_reinforced"):
		panel.button("타블렌과 손잡이 보강 · 낚싯대 / 가지 1 / 철 1", func(): _rod("fishing_rod_reinforced"))
	panel.text("물가에서 이어지는 이야기")
	for entry in FishingContent.collection():
		if not FishingContent.available(entry, hour(), weather()): continue
		var e: Dictionary = entry.duplicate(true)
		var label := str(e.get("title", ItemData.get_item_name(str(e.get("result_item_id", "")))))
		panel.button(("이어가기 · " if FishingRecords.accepted(str(e["id"])) else "이야기 듣기 · ") + label, func(): _select(e))
	for event in FishingData.entries("store_events"):
		var id := str(event["id"])
		if not FishingContent.store_available(id) or not StoreEventData.can_share_event(id, GameState.total_day) and not _response_ready(id): continue
		var e: Dictionary = event.duplicate(true)
		e["kind"] = "store_events"
		for c in e["requires"]["all"]:
			if c["kind"] == "known_npc": e["npc_id"] = c["id"]
		panel.button("가게에서 찾는 음식 · " + str(event["title"]), func(): _select(e))
	panel.button("물가 기록 보기", show_notes)
func observe() -> void:
	FishingRecords.mark("observed:" + location)
	for e in FishingContent.collection():
		if e["kind"] == "events" and FishingRecords.accepted(str(e["id"])): FishingRecords.mark("observed:" + str(e["id"]))
	panel.text("발 디딜 돌과 흐르는 물을 살펴보았습니다. 물가의 이야기를 다시 이어가 보세요.")
func _rod(id: String) -> void:
	var e := {"id":id, "npc_id":"naru", "kind":"tools", "title":"타블렌과 낚싯대 엮기"}
	_select(e)
func _select(entry: Dictionary) -> void:
	pending_entry = entry
	choices.clear()
	moon_choice = "keep"
	close()
	var owner := str(entry.get("npc_id", entry.get("teacher", "player")))
	if owner == "player": _open_entry(); return
	visitor = _visitor(owner)
	if not is_instance_valid(visitor):
		_notice("물가로 오는 길이 막혀 있습니다. 주변 공간을 정리한 뒤 다시 이야기해 주세요.")
		pending_entry.clear()
		return
	_notice("%s와 [E]로 물가의 이야기를 이어가세요." % _speaker(entry))
func _visitor(owner: String) -> Node2D:
	for actor in world.get_node("Actors").get_children():
		if actor.get("resident_id") == owner and actor is Node2D and actor.visible and not actor.is_queued_for_deletion(): return actor
	for actor in owned_visitors:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.get_meta("fishing_owner", "") == owner:
			if actor.get_meta("fishing_location", "") != location:
				actor.set_meta("fishing_location", location)
				actor.set_destination(spots.position_for(location)+Vector2(-52,-32),"물가에서 이야기하기")
			return actor
	var destination := spots.position_for(location)
	if destination == Vector2.INF: return null
	var npc := VillageResident.new()
	npc.resident_id = "fishing_visitor:" + owner
	npc.customer_type_id = str(FishingData.data()["npc_types"].get(owner, "villager"))
	npc.customer_group_id = CustomerTypeData.get_group_id(npc.customer_type_id)
	npc.set_meta("fishing_owner", owner)
	npc.set_meta("fishing_location", location)
	world.get_node("Actors").add_child(npc)
	npc.global_position = destination + Vector2(-150, -40)
	npc.title.text = _owner_name(owner) + " · 물가 이야기 [E]"
	var offsets := {"neighbor_bread":Vector2(-52,-32),"doyun":Vector2(24,-50),"child_berries":Vector2(80,-15)}
	npc.set_destination(destination + offsets.get(owner,Vector2(-52,-32)), "물가에서 이야기하기")
	owned_visitors.append(npc)
	return npc
func _owner_name(owner: String) -> String:
	if owner == "player": return "나"
	var resident := VillageLifeFlow.resident(owner)
	if not resident.is_empty(): return str(resident["name"])
	for request in ResidentRequestFlow.SETTINGS.requests:
		if str(request["id"]) == owner: return str(request["npc"])
	return CustomerTypeData.get_display_name(str(FishingData.data()["npc_types"].get(owner,"villager")))
func _speaker(entry: Dictionary) -> String:
	return _owner_name(str(entry.get("npc_id", entry.get("teacher", "player"))))
func _open_entry() -> void:
	if pending_entry.is_empty(): return
	var id := str(pending_entry["id"])
	if pending_entry["kind"] == "tools":
		mode = "menu"
		_lock(true)
		panel.clear("타블렌과 낚싯대 엮기")
		panel.text("나뭇가지를 손질하고 줄을 엮습니다. 준비한 재료만 사용합니다.")
		if FishingPreparationGuide.ENABLED: panel.text(FishingPreparationGuide.materials(world, id, _environment()))
		panel.button("준비한 재료로 엮기", func():
			if FishingService.make_rod(id, hour(), weather()):
				panel.text(ItemData.get_item_name(id) + "를 받았습니다.")
				pending_entry.clear()
			else: panel.text("재료와 소지 공간을 확인하세요. 이미 엮은 낚싯대는 다시 만들지 않습니다."))
		return
	if pending_entry["kind"] == "store_events":
		pending_phase = "response" if _response_ready(id) else "rumor"
		_start_dialogue(str(pending_entry[pending_phase + "_scene"]))
		return
	if not FishingContent.available(pending_entry, hour(), weather()):
		pending_entry.clear()
		return
	if pending_entry["kind"] == "recipes":
		pending_phase = "learn"
		_start_dialogue(id + "_learn")
	elif not FishingRecords.accepted(id):
		pending_phase = "intro"
		_start_dialogue(id + "_intro")
	else: _delivery_panel()
func _delivery_panel() -> void:
	mode = "menu"
	_lock(true)
	var id := str(pending_entry["id"])
	panel.clear(str(pending_entry.get("title", "물가 이야기")))
	panel.text(FishingContent.instructions(id))
	for ingredient in pending_entry.get("items", []):
		if ingredient.has("group_id"):
			var group := str(ingredient["group_id"])
			panel.text("전달할 생선 선택 · %d개 (날짜가 오래된 묶음부터)" % int(ingredient["amount"]))
			choices.erase(group)
			var ids := FishingPreparationGuide.candidates(group)
			if ids.is_empty():
				panel.text(UiText.t("fishing.preparation.no_candidates"))
				continue
			var picker := OptionButton.new()
			picker.clip_text = true
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for fish in ids: picker.add_item("%s · 보유 %d" % [ItemData.get_item_name(str(fish)),GameState.get_item_count(str(fish))])
			var selected := FishingPreparationGuide.preferred(ids, int(ingredient["amount"])) if FishingPreparationGuide.ENABLED else 0
			picker.select(selected)
			choices[group] = ids[selected]
			picker.item_selected.connect(func(index: int): choices[group] = str(ids[index]))
			panel.body.add_child(picker)
			if FishingPreparationGuide.ENABLED: panel.text(UiText.t("fishing.preparation.one_kind"))
		else: panel.text("%s ×%d · 보유 %d" % [ItemData.get_item_name(str(ingredient["item_id"])),ingredient["amount"],GameState.get_item_count(str(ingredient["item_id"]))])
	if pending_entry["kind"] == "requests":
		panel.text("답례 %d G · 평판 %d · 처음 한 번" % [pending_entry["reward"]["money"],pending_entry["reward"]["reputation"]])
	if id == "fish_event_moon":
		panel.button("챙겨 두기 · 생선을 소비하지 않음", func(): _finish("keep"))
		panel.button("물가로 돌려보내기 · 달무늬 잉어 1마리", func(): _finish("release"))
	elif id == "fish_event_table":
		panel.text("나눔 · 생선구이 2개. 현금 답례가 없는 작은 식탁입니다.")
		panel.button("함께할 이웃 부르기", _gather)
		panel.button("모인 이웃과 이야기하기", func(): _finish(), not _meeting_ready())
	else: panel.button("준비한 물품 전달 / 이야기 마치기", func(): _finish())
func _environment() -> Dictionary:
	return {"hour":hour(), "weather":weather(), "season":CalendarData.get_season_id(GameState.total_day)}
func _gather() -> void:
	close()
	meeting.clear()
	for owner in ["neighbor_bread", "doyun", "child_berries"]:
		var npc := _visitor(owner)
		if is_instance_valid(npc): meeting.append(npc)
	_notice("이웃이 물가로 걸어오면 이야기를 이어가세요. 생선구이는 아직 전달하지 않았습니다.")
func _meeting_ready() -> bool:
	if meeting.size() != 3: return false
	for npc in meeting:
		if not is_instance_valid(npc) or not npc.visible or npc.global_position.distance_to(spots.position_for(location)) > 130: return false
	return player.global_position.distance_to(spots.position_for(location)) < 130
func _finish(choice: String = "keep") -> void:
	var id := str(pending_entry["id"])
	if not FishingContent.action_ready(id): panel.text("아직 실제 행동을 마치지 않았습니다."); return
	if pending_entry["kind"] == "events" and id not in ["fish_event_moon", "fish_event_table"] and not FishingRecords.has("observed:" + id):
		panel.text("이야기를 들은 뒤 물가를 먼저 살펴보세요."); return
	if id == "fish_event_table" and not _meeting_ready(): panel.text("참여할 이웃이 아직 물가에 모이지 않았습니다."); return
	var selected := FishingService.selected(pending_entry.get("items", []), choices)
	if selected.is_empty() and not pending_entry.get("items", []).is_empty(): panel.text("전달할 생선을 선택하세요."); return
	for item in selected:
		if GameState.get_item_count(str(item)) < int(selected[item]): panel.text("물품이 부족하거나 날짜가 지났습니다."); return
	if id == "fish_event_moon" and GameState.get_item_count("fish_moon_carp") < 1: panel.text("보여 줄 달무늬 잉어가 없습니다."); return
	moon_choice = choice
	pending_phase = "finish"
	_start_dialogue(id + "_finish")
func _start_dialogue(scene: String) -> void:
	if mode == "menu": panel.root.hide()
	else: _lock(true)
	mode = "dialogue"
	var lines := RequestTextData.lines("service_text", scene)
	if pending_entry.get("kind", "") == "store_events" and pending_phase == "response":
		var item_name := "가게 음식"
		var suffix := str(pending_entry["id"]) + ":" + str(CalendarData.get_year(GameState.total_day))
		for item in pending_entry["products"]:
			if FishingRecords.has("receipt_item:" + suffix + ":" + str(item)):
				item_name = ItemData.get_item_name(str(item))
				break
		for i in range(lines.size()): lines[i] = lines[i].replace("{item}", item_name)
	dialogue.start(_speaker(pending_entry), null, lines)
func _dialogue_finished() -> void:
	var full := dialogue.line_index >= dialogue.lines.size()
	var id := str(pending_entry.get("id", ""))
	if full and not id.is_empty():
		match pending_phase:
			"intro": FishingContent.accept(id, hour(), weather())
			"learn":
				if FishingContent.accept(id, hour(), weather()): FishingContent.complete(id)
			"finish":
				if not FishingContent.complete(id, choices, moon_choice, _meeting_ready()): _notice("물품 상태를 다시 확인하세요. 이번에는 전달되지 않았습니다.")
			"rumor": StoreEventData.discover_event(id, GameState.total_day)
			"response": FishingRecords.mark("response:" + id + ":" + str(CalendarData.get_year(GameState.total_day)))
	if full and pending_phase in ["finish", "learn", "response"]:
		if id == "fish_event_table":
			for npc in meeting:
				if owned_visitors.has(npc): owned_visitors.erase(npc); npc.queue_free()
			meeting.clear()
		elif owned_visitors.has(visitor):
			owned_visitors.erase(visitor)
			visitor.queue_free()
		visitor = null
	close()
	pending_entry.clear()
func _response_ready(id: String) -> bool:
	var suffix := id + ":" + str(CalendarData.get_year(GameState.total_day))
	return FishingRecords.has("receipt:" + suffix) and not FishingRecords.has("response:" + suffix)
func cast() -> void:
	# Return the menu's clock lease before checking the live world clock.
	close()
	if not FishingService.has_rod() or not FishingRecords.done("fishing_rod") or not clock_running():
		_notice("정비와 정산을 마치고 시간이 흐를 때 낚싯대를 드리울 수 있습니다.")
		return
	mode = "waiting"
	_lock(false)
	remaining = rng.randf_range(float(FishingData.data()["settings"]["bite_min_seconds"]), float(FishingData.data()["settings"]["bite_max_seconds"]))
	panel.clear(str(FishingData.entry(location)["name"]))
	panel.shade.color.a = 0.0
	player.last_direction = Vector2.DOWN
	panel.frame.anchor_left = 0.65
	panel.frame.anchor_right = 0.98
	panel.frame.anchor_top = 0.34
	panel.frame.anchor_bottom = 0.89
	status = panel.text("찌를 바라보며 기다립니다…\n가게와 물가의 시간이 함께 흐릅니다.")
	reel_button = panel.button("찌가 움직이면 [E]로 건지기", reel, true)
func _process(delta: float) -> void:
	if mode not in ["waiting", "bite", "full"]: return
	if not clock_running():
		close()
		_notice("시간이 멈춰 낚싯대를 거두었습니다. 물품은 지급되지 않았습니다.")
		return
	if mode == "waiting":
		remaining -= delta
		if remaining <= 0:
			pending_fish = FishingService.roll(location, hour(), weather(), rng)
			if pending_fish.is_empty(): close(); return
			mode = "bite"
			status.text = "찌가 움직입니다! [E]로 천천히 건져 보세요."
			reel_button.disabled = false
			reel_button.text = "건지기 [E]"
func reel() -> void:
	if mode not in ["bite", "full"] or pending_fish.is_empty() or not clock_running(): return
	if not FishingService.receive(pending_fish):
		if mode != "full": panel.button("물가로 놓아주기 · 지급 없음", close)
		mode = "full"
		status.text = "소지 공간이 부족합니다. 놓아주거나 낚싯대를 거두고 재고를 정리할 수 있습니다."
		return
	var caught := pending_fish
	pending_fish = ""
	close()
	_notice("%s 1마리를 건졌습니다. 진열하거나 보존해 두세요." % ItemData.get_item_name(caught))
func show_notes() -> void:
	panel.clear("물가 기록")
	panel.text("만난 물고기 %d / 12 · 계절 물고기 %d종" % [FishingRecords.discovered(),FishingRecords.discovered(true)])
	for fish in FishingData.entries("fish"):
		if FishingRecords.has("caught:" + str(fish["id"])):
			panel.text(str(fish["name"]) + "\n" + str(fish["description"]) + "\n" + FoodShelfLife.describe(str(fish["id"])))
	for entry in FishingContent.collection():
		var id := str(entry["id"])
		if FishingRecords.accepted(id) or FishingRecords.done(id): panel.text(str(entry.get("title", ItemData.get_item_name(str(entry.get("result_item_id", ""))))) + " · " + ("함께 마침" if FishingRecords.done(id) else "진행 중") + "\n" + FishingContent.instructions(id))
	if FishingRecords.has("moon:release"): panel.text("달무늬 잉어를 물가로 돌려보냈습니다.")
	elif FishingRecords.has("moon:keep"): panel.text("달무늬 잉어를 보여 주고 챙겨 두었습니다.")
func _input(event: InputEvent) -> void:
	if mode == "closed" or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if mode == "dialogue": dialogue.close()
		else: pending_entry.clear(); close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and mode in ["waiting", "bite", "full"]:
		if mode != "waiting": reel()
		get_viewport().set_input_as_handled()
func _notice(value: String) -> void:
	var interactions = world.get_node_or_null("WorldInteractions")
	if interactions != null: interactions.show_message(value)
func _exit_tree() -> void:
	if is_instance_valid(panel): close()
	for npc in owned_visitors:
		if is_instance_valid(npc): npc.queue_free()
