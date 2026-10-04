class_name ExpeditionContactRoom
extends Node

var controller: ExpeditionRoomController
var entry: Dictionary = {}
var position := Vector2.INF
var dialogue: StoryDialoguePanel
var title: Label
var sprite: AnimatedSprite2D
var figure: BlockyFigure
var open := false
var clock_was_processing := false

func _ready() -> void:
	dialogue = StoryDialoguePanel.new()
	add_child(dialogue)
	dialogue.finished.connect(_end_dialogue)
	title = Label.new()
	title.size.x = 240
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color",Color("fff0d0"))
	title.add_theme_color_override("font_outline_color",Color("302415"))
	title.add_theme_constant_override("outline_size",4)
	add_child(title)
	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	clear()

func clear() -> void:
	if dialogue.open: dialogue.close()
	_release()
	entry = {}
	position = Vector2.INF
	title.hide()
	sprite.hide()
	if is_instance_valid(figure): figure.queue_free()
	figure = null

func enter() -> void:
	clear()
	entry = ExpeditionContactFlow.encounter(controller.host.current_region_id,str(controller.event.get("result_type","none")),controller.node_type)
	if entry.is_empty(): return
	position = ExpeditionContactPlacement.choose(controller.model)
	if position == Vector2.INF:
		entry = {}
		return
	controller.model.extra_interaction_label = hint
	controller.model.extra_interact = try_interact
	title.text = CustomerTypeData.get_display_name(str(entry["type"])) + " [E]"
	var path := "res://art/characters/cozy_v1/" + CustomerTypeData.get_group_id(str(entry["type"])) + "/frames.tres"
	if not ResourceLoader.exists(path): path = "res://art/characters/cozy_v1/normal/frames.tres"
	sprite.sprite_frames = load(path)
	sprite.play("idle_down")

func _process(delta: float) -> void:
	var view := controller.view
	var shown := not entry.is_empty() and controller.is_active() and not controller.model.finished
	title.visible = shown and not open
	sprite.visible = shown and not view._stage_on()
	if is_instance_valid(figure): figure.visible = shown and view._stage_on()
	if not shown: return
	title.text = CustomerTypeData.get_display_name(str(entry["type"])) + ("\n마을에서 다시 만나요" if ExpeditionContactFlow.has(str(entry["id"]),"met") else " [E]")
	var at := view._point(position)
	title.position = at - Vector2(120,80 * view.tile_scale)
	sprite.position = at - Vector2(0,30 * view.tile_scale)
	sprite.scale = Vector2.ONE * view.tile_scale
	if view._stage_on() and not is_instance_valid(figure):
		figure = BlockyFigure.new()
		figure.build(view.stage._vp,figure,3.0,1.05)
		figure._id_root.hide()
		figure.set_sorted(false)
		figure.set_tint(Color(str(entry["color"])))
		figure.position = Vector3(position.x,0,position.y)
	if is_instance_valid(figure): figure.animate(0.0 if open else delta)

func hint() -> String:
	if entry.is_empty() or open or not controller.is_active() or controller.model.finished: return ""
	if ExpeditionContactFlow.has(str(entry["id"]),"met"): return ""
	var room := controller.model
	if room.player_position.distance_to(position) > ExpeditionContactFlow.SETTINGS.encounter_reach or room._wall_between(room.player_position,position): return ""
	return "말 걸기"

func try_interact() -> bool:
	if hint().is_empty() or controller._menu_open(): return false
	var lines := RequestTextData.lines("service_text",str(entry["id"]) + "_meet")
	if lines.is_empty(): return false
	lines.append("다음 날 이후 마을 게시판 근처에서 직접 전달\n" + ExpeditionContactFlow.requirements(str(entry["id"])))
	open = true
	var clock: Node = controller.host.get_node("ExpeditionClock")
	clock_was_processing = clock.is_processing()
	clock.set_process(false)
	dialogue.start(CustomerTypeData.get_display_name(str(entry["type"])),null,lines)
	return true

func _end_dialogue() -> void:
	if not open: return
	if dialogue.line_index >= dialogue.lines.size() and controller.is_active() and not controller.model.finished:
		if ExpeditionContactFlow.meet(str(entry["id"])): controller.view.notice = "원정에서 만난 사람의 부탁을 수첩에 남겼습니다. 다음 날 이후 마을에서 이어집니다."
	_release()

func _release() -> void:
	if not open: return
	open = false
	if is_instance_valid(controller.host):
		var clock: Node = controller.host.get_node_or_null("ExpeditionClock")
		if clock != null: clock.set_process(clock_was_processing)

func _exit_tree() -> void:
	_release()
	if is_instance_valid(figure): figure.queue_free()
