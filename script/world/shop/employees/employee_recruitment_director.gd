class_name EmployeeRecruitmentDirector
extends Node
var world: Node2D
var player: Node2D
var manager: Node
var applicant: EmployeeApplicant
var dialogue: StoryDialoguePanel
var elapsed := 0.0
var pending_id := ""
var previous_paused := false
var previous_physics := true
func _ready() -> void:
	world = get_parent()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_finish)
	var later := Button.new()
	later.text = "나중에 · Esc"
	later.anchor_left = 1.0
	later.anchor_right = 1.0
	later.anchor_top = 1.0
	later.anchor_bottom = 1.0
	later.offset_left = -200
	later.offset_right = -50
	later.offset_top = -295
	later.offset_bottom = -255
	dialogue.root.add_child(later)
	later.pressed.connect(dialogue.close)
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < EmployeeRecruitmentFlow.SETTINGS.applicant_retry_seconds: return
	elapsed = 0
	refresh_visit()
func refresh_visit() -> void:
	if world.get_node("WorldInteractions").blocked(): return
	var id := EmployeeRecruitmentFlow.next_applicant()
	if is_instance_valid(applicant):
		if applicant.employee_id == id: return
		applicant.queue_free()
		applicant = null
	if id.is_empty() or manager.current_hour < 6 or manager.current_hour >= 22: return
	var endpoints := visit_points()
	if endpoints.is_empty(): return # Retry when the road is clear, without consuming a visit.
	applicant = EmployeeApplicant.new()
	applicant.employee_id = id
	world.get_node("Actors").add_child(applicant)
	applicant.global_position = endpoints[0]
	CustomerGates.appear(applicant)
	applicant.set_destination(endpoints[1], "가게 앞에서 인사 기다리기")
func visit_points() -> PackedVector2Array:
	var doors := get_tree().get_nodes_in_group("door")
	var entrance := Vector2.INF
	for door in doors:
		if door.get_parent() == world.get_node("Objects") and not door.get_meta("is_build_preview",false):
			entrance = door.global_position
			break
	if entrance == Vector2.INF: return PackedVector2Array()
	var terrain = world.get_node("StoreExterior")
	var floor_node = world.get_node("Floor")
	var space := world.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = VillageLifeFlow.SETTINGS.resident_radius
	var points: Array[Vector2] = []
	for cell in terrain.get_connected_map_cells():
		var point: Vector2 = terrain.to_global(terrain.grid_to_local(cell))
		var distance := point.distance_to(entrance)
		if distance < EmployeeRecruitmentFlow.SETTINGS.applicant_door_distance or distance > EmployeeRecruitmentFlow.SETTINGS.applicant_search_distance: continue
		if floor_node.is_cell_inside(floor_node.local_to_grid(floor_node.to_local(point))): continue
		if not VillageRoutine.clear(space,shape,point): continue
		points.append(point)
	points.sort_custom(func(a: Vector2,b: Vector2): return a.distance_squared_to(entrance) < b.distance_squared_to(entrance))
	for target in points.slice(0,8):
		for start in points.slice(0,24):
			if start.distance_to(target) < EmployeeRecruitmentFlow.SETTINGS.applicant_walk_distance: continue
			if not VillageRoutine.route(world,start,target).is_empty(): return PackedVector2Array([start,target])
	return PackedVector2Array()
func nearby() -> bool:
	return is_instance_valid(applicant) and not applicant.is_queued_for_deletion() and not player.in_production_room and not player.in_warehouse_room and player.global_position.distance_to(applicant.global_position) <= EmployeeRecruitmentFlow.SETTINGS.applicant_interaction_distance
func interaction_hint() -> String:
	return "[E] " + str(EmployeeData.get_employee(applicant.employee_id)["display_name"]) + " · 함께 일할 이야기" if nearby() and not dialogue.open else ""
func try_interact() -> bool:
	if not nearby() or world.get_node("WorldInteractions").blocked(): return false
	pending_id = applicant.employee_id
	var lines := RequestTextData.lines("service_text", pending_id + "_intro")
	if lines.is_empty(): pending_id = ""; return false
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	world.set_meta("employee_recruitment_open", true)
	var texture := applicant.sprite.sprite_frames.get_frame_texture("idle_down",0)
	dialogue.start(str(EmployeeData.get_employee(pending_id)["display_name"]), texture, lines)
	return true
func _finish() -> void:
	if pending_id.is_empty(): return
	if dialogue.line_index >= dialogue.lines.size():
		EmployeeStoryFlow.finish(pending_id + "_intro")
		EmployeeRecruitmentFlow.meet(pending_id)
		var interactions = world.get_node("WorldInteractions")
		interactions.prompt.text = "직원 관리에 고용 조건을 적었습니다. 아침 6시, 문을 열기 전에 결정해 주세요."
		interactions.message_origin = player.global_position
		interactions.message_until = Time.get_ticks_msec() + 6000
		manager.management_menu.employee_content.refresh_view()
	pending_id = ""
	world.remove_meta("employee_recruitment_open")
	if not manager.summary_open and not manager.closing_shop: manager.hour_timer.paused = previous_paused
	player.set_physics_process(previous_physics)
func _input(event: InputEvent) -> void:
	if dialogue.open and not event.is_echo() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dialogue.close()
