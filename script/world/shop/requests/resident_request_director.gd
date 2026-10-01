class_name ResidentRequestDirector
extends TutorialDirector

# 안내 NPC의 접근 가능한 자리 선택, 대화 거리, 시간/이동 복원을 재사용한다.
func is_guiding() -> bool:
	return enabled and not ResidentRequestFlow.current().is_empty()

func refresh() -> void:
	if not is_instance_valid(panel): return
	var request := ResidentRequestFlow.current() if enabled else {}
	if request.is_empty():
		panel.display("마을 평판 · %d" % ResidentRequestFlow.reputation(), "주민 부탁 %d/%d 완료" % [ResidentRequestFlow.completed_count(), ResidentRequestFlow.SETTINGS.requests.size()] if ResidentRequestFlow.tutorial_finished() and enabled else "")
		panel.root.visible = enabled and ResidentRequestFlow.tutorial_finished() and not _blocked()
		if is_instance_valid(npc): npc.leave()
		npc = null
		return
	var accepted := ResidentRequestFlow.accepted(str(request["id"]))
	var ready := ResidentRequestFlow.can_deliver(request)
	var objective := "주민에게 말을 걸어 부탁을 받으세요. [E]"
	if accepted:
		objective = "%s %d/%d · 창고 물품 전달 [E]" % [ItemData.get_item_name(str(request["item"])), mini(GameState.get_item_count(str(request["item"])), int(request["amount"])), int(request["amount"])]
		if ready: objective = "준비 완료! 주민에게 전달 [E]"
	objective += "\n보상: 평판 +%d · %d G\n주민 부탁 %d/%d 완료" % [int(request["reputation"]), int(request["money"]), ResidentRequestFlow.completed_count(), ResidentRequestFlow.SETTINGS.requests.size()]
	panel.display("주민 부탁 · " + str(request["title"]) + "\n마을 평판 %d" % ResidentRequestFlow.reputation(), objective)
	panel.root.visible = not talking and not _blocked()
	if talking or _blocked(): return
	if is_instance_valid(npc) and str(npc.beat.get("beat_id")) != str(request["id"]):
		npc.queue_free()
		npc = null
	if not is_instance_valid(npc):
		npc = StoryNpc.new()
		npc.setup({"beat_id":request["id"], "lines":request["lines"]})
		get_parent().get_node("Actors").add_child(npc)
		npc.global_position = _guidance_position()
		npc.mark.text = str(request["npc"]) + " [E]"
		npc.mark.position.x = -65
		npc.mark.add_theme_font_size_override("font_size", 16)
	elif _npc_needs_relocation():
		npc.global_position = _guidance_position()

func try_interact() -> bool:
	if not enabled or talking or _blocked() or not is_instance_valid(npc): return false
	if player.global_position.distance_to(npc.global_position) > talk_distance: return false
	var request := ResidentRequestFlow.current()
	if request.is_empty(): return false
	var lines: Array[String] = []
	if not ResidentRequestFlow.accepted(str(request["id"])):
		ResidentRequestFlow.accept(request)
		lines.assign(request["lines"])
	elif ResidentRequestFlow.can_deliver(request):
		var result := ResidentRequestFlow.deliver(request)
		if result.is_empty(): return false
		manager.customer_spawner.refresh_spawn_interval()
		lines.assign(request["completion"])
		lines.append("평판 +%d · 사례 %d G" % [result["reputation"], result["money"]])
		for type_id in result["unlocked"]:
			lines.append("새 손님 소식: %s! 가게를 열면 소개받은 손님이 방문해요." % CustomerTypeData.get_display_name(type_id))
	else:
		lines.assign(request["lines"])
		lines.append("필요한 물건은 %s %d개야. 진열대나 원정 가방에 있다면 창고로 옮겨 준비해 줘." % [ItemData.get_item_name(str(request["item"])), int(request["amount"])])
	talking = true
	panel.root.hide()
	timer_was_paused = manager.hour_timer.paused
	manager.hour_timer.paused = true
	physics_was_enabled = player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("progressive_tutorial_dialogue", true)
	dialogue.start(str(request["npc"]), ArtLoader.load_texture("res://art/npc/npc_placeholder.png"), lines)
	return true
