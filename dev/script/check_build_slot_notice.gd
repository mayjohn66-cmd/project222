extends Node
## 건축 퀵슬롯: 아직 열리지 않은 가구가 든 슬롯도 자리를 지키고, 열리는 순간 한 번 알려 주며 NEW 표시가 붙는다.
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.record_story_beat(ShopSpaceProgression.VERSION, 0)   # 단계 잠금 켜짐
	GameState.add_furniture("magic_oven", 1)
	GameState.set_build_quick_slot(0, "shelf_1x1")
	GameState.set_build_quick_slot(1, "magic_oven")
	check(ShopSpaceProgression.active() and not ShopSpaceProgression.furniture_visible("magic_oven"), "처음에는 화덕이 가려져 있다")
	var bar = load("res://scenes/shared/ui/build/build_quick_slot_bar.tscn").instantiate()
	add_child(bar)
	for i in range(3): await get_tree().process_frame
	bar.set_build_mode_active(true)
	await get_tree().process_frame
	var visible_count := 0
	for b in bar.slot_buttons: if b.visible: visible_count += 1
	check(visible_count == GameState.BUILD_QUICK_SLOT_COUNT, "가려진 슬롯도 숨기지 않아 슬롯 %d개가 모두 보인다" % visible_count)
	var locked_icon: TextureRect = bar.slot_buttons[1].get_node("FurnitureIcon")
	check(locked_icon.texture == null, "가려진 슬롯은 빈 칸처럼 보인다(그림 없음)")
	check(bar.slot_buttons[1].get_node("Shortcut").text == "2", "번호는 그대로 2")
	check(PlayerProgress.story_beat_days.has(FurnitureUnlockNotice.HIDDEN_PREFIX + "magic_oven"), "가려진 가구를 본 것으로 기록")
	check(bar._new_ids.is_empty(), "아직은 새로 열린 가구가 없다")
	# 단계가 넘어가 화덕이 열린다
	PlayerProgress.record_story_beat("tutorial_step:production:intro", 0)
	check(ShopSpaceProgression.furniture_visible("magic_oven"), "단계를 넘기면 화덕이 열린다")
	bar.set_build_mode_active(false)
	bar.set_build_mode_active(true)
	await get_tree().process_frame
	check(bar._new_ids.has("magic_oven"), "열린 가구(화덕, 함께 열린 생산실 문)가 새로 열림으로 잡힌다")
	check(bar.slot_buttons[1].has_node("NewMark"), "슬롯에 NEW 표시")
	check(bar._notice_panel != null and bar._notice_panel.visible and bar._notice_label.text.contains(FurnitureData.get_furniture_name("magic_oven")), "알림 문구에 가구 이름")
	check(bar.slot_buttons[1].get_node("FurnitureIcon").texture != null, "열린 슬롯은 그림이 나온다")
	# 한 번만 알린다
	bar._new_ids.clear()
	bar.set_build_mode_active(false)
	bar.set_build_mode_active(true)
	check(bar._new_ids.is_empty(), "같은 가구는 다시 알리지 않는다")
	# 가방을 열면 NEW 가 사라진다
	bar._new_ids.append("magic_oven")
	bar.refresh_slots()
	bar.set_inventory_open(true)
	await get_tree().process_frame
	check(bar._new_ids.is_empty(), "가방을 열면 새로 열림 목록이 비워진다")
	# 처음부터 보이던 가구는 알리지 않는다
	check(not PlayerProgress.story_beat_days.has(FurnitureUnlockNotice.HIDDEN_PREFIX + "shelf_1x1"), "처음부터 보이던 선반은 기록하지 않는다")
	print("checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
