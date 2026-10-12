class_name ResidentRequestDirector
extends TutorialDirector

# 안내 NPC의 접근 가능한 자리 선택, 대화 거리, 시간/이동 복원을 재사용한다.
func is_guiding() -> bool:
	return enabled and (not ResidentRequestFlow.current().is_empty() or not ResidentStoryFlow.pending_introduction().is_empty())

# 튜토리얼이 끝난 뒤의 주민 부탁·인연 안내는 화면 왼쪽에 띄우지 않는다(2026-10-08 결정).
# 같은 내용은 관리 책의 일정 탭 "마을 수첩"에서 본다. 문구는 그대로 만들어 두고 보이게만 하지 않는다.
const SHOW_LEFT_PANEL := false

func refresh() -> void:
	if not is_instance_valid(panel): return
	var introduction := ResidentStoryFlow.pending_introduction() if enabled else {}
	if not introduction.is_empty():
		panel.display("새로운 인연 · " + str(introduction["npc"]), "가게를 찾은 손님과 인사하세요. [E]\n" + ResidentStoryFlow.place_name())
		panel.root.visible = SHOW_LEFT_PANEL and not talking and not _blocked()
		if not talking and not _blocked(): _prepare_npc("meet:" + str(introduction["type"]), str(introduction["npc"]), introduction["lines"])
		return
	var request := ResidentRequestFlow.current() if enabled else {}
	if request.is_empty():
		panel.display(ResidentStoryFlow.place_name() + "\n마을 평판 · %d" % ResidentRequestFlow.reputation(), "주민 부탁 %d/%d 완료" % [ResidentRequestFlow.total_completed_count(), ResidentRequestFlow.total_request_count()] if ResidentRequestFlow.tutorial_finished() and enabled else "")
		var next_step := ResidentMerchantSupply.next_step()
		if not next_step.is_empty(): panel.display("채집 도구를 구하는 길", next_step)
		panel.root.visible = SHOW_LEFT_PANEL and enabled and ResidentRequestFlow.tutorial_finished() and not _blocked()
		if is_instance_valid(npc): npc.leave()
		npc = null
		return
	var accepted := ResidentRequestFlow.accepted(str(request["id"]))
	var ready := ResidentRequestFlow.can_deliver(request)
	var objective := "주민에게 말을 걸어 부탁을 받으세요. [E]"
	if accepted:
		objective = "%s %d/%d · 소지 물품 전달 [E]" % [ItemData.get_item_name(str(request["item"])), mini(GameState.get_item_count(str(request["item"])), int(request["amount"])), int(request["amount"])]
		if ready: objective = "준비 완료! 주민에게 전달 [E]"
	if str(request.get("payment_kind", "")) == "gift":
		objective += "\n나눔 부탁 · 물품 대금은 별도로 받지 않습니다.\n답례: 평판 +%d · %d G" % [int(request["reputation"]), int(request["money"])]
	else:
		objective += "\n보상: 평판 +%d · %d G" % [int(request["reputation"]), int(request["money"])]
	var landmark := ResidentStoryFlow.landmark_for_request(str(request["id"]))
	if not landmark.is_empty(): objective += "\n함께 만들 곳: " + landmark
	panel.display("주민 부탁 · " + str(request["title"]) + "\n마을 평판 %d" % ResidentRequestFlow.reputation(), objective)
	panel.root.visible = SHOW_LEFT_PANEL and not talking and not _blocked()
	# 시험판: 영업 중에는 이 부탁을 NPC가 손님으로 입장해 건넨다(QuestVisitDirector). 서 있는 NPC는 영업 전·후에만 대신한다.
	if not talking and QuestVisitDirector.replaces_standing_npc(get_parent()):
		if is_instance_valid(npc): npc.leave()
		npc = null
		return
	if talking or _blocked(): return
	_prepare_npc(str(request["id"]), str(request["npc"]), request["lines"])

func _prepare_npc(id: String, npc_name: String, lines: Array) -> void:
	if is_instance_valid(npc) and str(npc.beat.get("beat_id")) != id:
		npc.queue_free()
		npc = null
	if not is_instance_valid(npc):
		npc = StoryNpc.new()
		npc.setup({"beat_id":id, "npc_id":NpcPortraits.npc_id_of(npc_name), "lines":lines})
		get_parent().get_node("Actors").add_child(npc)
		npc.global_position = _guidance_position()
		npc.mark.text = npc_name + " [E]"
		npc.mark.position.x = -65
		npc.mark.add_theme_font_size_override("font_size", 16)
	elif _npc_needs_relocation():
		npc.global_position = _guidance_position()

func try_interact() -> bool:
	if not enabled or talking or _blocked() or not is_instance_valid(npc): return false
	if player.global_position.distance_to(npc.global_position) > talk_distance: return false
	var introduction := ResidentStoryFlow.pending_introduction()
	if not introduction.is_empty():
		if not ResidentStoryFlow.meet(str(introduction["type"])): return false
		var greeting: Array[String] = []
		greeting.assign(introduction["lines"])
		_start_resident_dialogue(str(introduction["npc"]), greeting)
		return true
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
		var landmark := ResidentStoryFlow.landmark_for_request(str(request["id"]))
		if not landmark.is_empty(): lines.append("함께 만든 곳: " + landmark)
		for type_id in result["unlocked"]:
			lines.append("새 손님 소식: %s! 가게를 열면 소개받은 손님이 방문해요." % CustomerTypeData.get_display_name(type_id))
	else:
		lines.assign(request["lines"])
		lines.append("필요한 물건은 %s %d개야. 소지품에 챙겨 줘. 진열대나 보관 선반에 있다면 먼저 꺼내 줘." % [ItemData.get_item_name(str(request["item"])), int(request["amount"])])
	_start_resident_dialogue(str(request["npc"]), lines)
	return true

func _start_resident_dialogue(npc_name: String, lines: Array[String]) -> void:
	talking = true
	panel.root.hide()
	timer_was_paused = manager.hour_timer.paused
	manager.hour_timer.paused = true
	physics_was_enabled = player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("progressive_tutorial_dialogue", true)
	dialogue.start(npc_name, ArtLoader.load_texture("res://art/npc/npc_placeholder.png"), lines)
