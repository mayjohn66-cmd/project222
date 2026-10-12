class_name TutorialGoalPanel
extends CanvasLayer
var root: PanelContainer
var caption: Label
var goal: Label
func _ready() -> void:
	layer = 8
	root = PanelContainer.new()
	root.position = Vector2(16, 166)
	root.custom_minimum_size = Vector2(260, 110)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	caption = Label.new()
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 250
	box.add_child(caption)
	goal = Label.new()
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.custom_minimum_size.x = 250
	box.add_child(goal)
func display(title: String, text: String) -> void:
	root.visible = not title.is_empty()
	caption.text = title
	goal.text = text
