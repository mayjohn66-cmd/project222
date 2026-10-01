class_name CommunityBoardDirector
extends Node

var panel: CommunityBoardPanel
var player
var manager
var open := false
var previous_paused := false
var previous_physics := true
var elapsed := 0.0

func _ready() -> void:
	player = get_parent().get_node("Actors/Player")
	manager = get_parent().get_node("DayManager")
	panel = CommunityBoardPanel.new()
	add_child(panel)
	panel.action_requested.connect(_on_action)
	panel.closed.connect(_on_closed)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0.0
	var board := VillageSettlement.find_site(get_parent(), CommunityRequestFlow.SETTINGS.board_path)
	if board == null or not board.visible or not CommunityRequestFlow.board_available(): return
	if board.has_node("CommunityBoardHint"): return
	var hint := Label.new()
	hint.name = "CommunityBoardHint"
	hint.text = "마을 부탁 [E]"
	hint.position = Vector2(-90, -195)
	hint.size = Vector2(180, 32)
	hint.z_index = 50
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("fff0d0"))
	hint.add_theme_color_override("font_outline_color", Color("302415"))
	hint.add_theme_constant_override("outline_size", 4)
	board.add_child(hint)

func near_board() -> bool:
	var world := get_parent()
	if not CommunityRequestFlow.board_available() or world.get_node("WorldInteractions").blocked(): return false
	if player.in_production_room or player.in_warehouse_room or player.shelf_panel.visible or player.rumor_dialog.visible: return false
	if is_instance_valid(player.facility_dialog) and player.facility_dialog.visible: return false
	var editor = world.get_node_or_null("VillageMapEditor")
	if editor != null and editor.active: return false
	var merchant = world.get_node_or_null("SecretMerchantDirector")
	var cashier = world.get_node_or_null("ManualCheckoutController")
	if merchant != null and merchant.shopping: return false
	if cashier != null and cashier.is_busy(): return false
	var board := VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path)
	return board != null and board.visible and player.global_position.distance_to(board.global_position) <= CommunityRequestFlow.SETTINGS.interaction_distance

func interaction_hint() -> String:
	return "[E] 마을 부탁 게시판 살펴보기" if near_board() else ""

func try_interact() -> bool:
	if not near_board(): return false
	open = true
	previous_paused = manager.hour_timer.paused
	previous_physics = player.is_physics_processing()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	get_parent().set_meta("community_board_open", true)
	panel.display()
	return true

func _on_action(id: String) -> void:
	if not open: return
	if not CommunityRequestFlow.accepted(id):
		if CommunityRequestFlow.accept(id): panel.message.text = "부탁을 맡았습니다. 준비되면 이 게시판에서 전달하세요."
	else:
		var result := CommunityRequestFlow.deliver(id)
		if not result.is_empty():
			panel.message.text = "%s 평판 +%d · %d G" % [result["completion"], result["reputation"], result["money"]]
			VillageSettlement.apply_world(get_parent())
			manager.customer_spawner.refresh_spawn_interval()
	panel.refresh()

func _on_closed() -> void:
	if not open: return
	open = false
	get_parent().remove_meta("community_board_open")
	if is_instance_valid(manager): manager.hour_timer.paused = previous_paused
	if is_instance_valid(player): player.set_physics_process(previous_physics)

func _exit_tree() -> void: _on_closed()
