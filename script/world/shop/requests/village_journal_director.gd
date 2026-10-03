class_name VillageJournalDirector
extends CommunityBoardDirector

var button: Button
var guidance: Label
var marker: Label
var tracked_id := ""

func create_panel() -> CommunityBoardPanel:
	var journal := VillageJournalPanel.new()
	journal.world = get_parent()
	return journal

func modal_key() -> String: return "village_journal_open"

func _ready() -> void:
	super._ready()
	button = Button.new()
	button.name = "VillageJournalButton"
	button.text = "마을 수첩 [N]"
	button.size = Vector2(180,48)
	panel._style_button(button)
	button.pressed.connect(try_interact)
	get_parent().get_node("UI").add_child(button)
	guidance = Label.new()
	guidance.name = "VillageJournalGuidance"
	guidance.size = Vector2(600,32)
	guidance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guidance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(guidance)
	get_parent().get_node("UI").add_child(guidance)
	marker = Label.new()
	marker.name = "VillageJournalDestination"
	marker.text = "▼"
	marker.size = Vector2(48,32)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.z_index = 1000
	_style_label(marker)
	get_parent().add_child.call_deferred(marker)

func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_color",Color("fff0d0"))
	label.add_theme_color_override("font_outline_color",Color("302415"))
	label.add_theme_constant_override("outline_size",4)

func near_board() -> bool:
	return VillageJournalFlow.available() and not get_parent().get_node("VillageLifeDirector")._blocked()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		if open:
			panel.close()
			get_viewport().set_input_as_handled()
		elif try_interact(): get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if button == null: return
	if not VillageJournalFlow.available(): tracked_id = ""
	var screen := get_viewport().get_visible_rect().size
	guidance.size.x = minf(600,screen.x - 48)
	button.position = Vector2(screen.x - button.size.x - 24,screen.y - button.size.y - 24)
	button.visible = near_board() and not open
	guidance.position = Vector2((screen.x - guidance.size.x) * 0.5,screen.y - 122)
	marker.hide()
	guidance.hide()
	if tracked_id.is_empty() or not near_board() or open: return
	var target := VillageJournalFlow.destination(get_parent(),tracked_id)
	if target == null:
		tracked_id = ""
		return
	marker.global_position = target.global_position + Vector2(-24,-64)
	marker.show()
	var heading := "목적지"
	for entry in VillageJournalFlow.entries():
		if entry["id"] == tracked_id: heading = str(entry["title"])
	var delta_position: Vector2 = target.global_position - player.global_position
	var directions := ["→","↘","↓","↙","←","↖","↑","↗"]
	var direction: String = directions[posmod(roundi(delta_position.angle() / (PI / 4)),8)]
	guidance.text = "%s %s · 수첩에서 표시 해제" % [direction,heading]
	guidance.show()

func _on_action(id: String) -> void:
	if not open: return
	if tracked_id == id: tracked_id = ""
	elif VillageJournalFlow.destination(get_parent(),id) != null: tracked_id = id
	(panel as VillageJournalPanel).tracked_id = tracked_id
	panel.message.text = "목적지 표시를 해제했습니다." if tracked_id.is_empty() else "목적지를 표시했습니다. 수첩을 닫고 화살표 방향으로 걸어가세요."
	panel.refresh()

func try_interact() -> bool:
	(panel as VillageJournalPanel).tracked_id = tracked_id
	return super.try_interact()
