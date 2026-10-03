extends PanelContainer

const SCREEN_MARGIN := 24.0
const MAX_SIZE := Vector2(720, 560)

@onready var scroll: ScrollContainer = $VBoxContainer/ResultScroll
@onready var confirm: Button = $VBoxContainer/ResultConfirmButton

func _ready() -> void:
	get_viewport().size_changed.connect(_fit_screen)
	visibility_changed.connect(_on_visibility_changed)
	_fit_screen()

func _fit_screen() -> void:
	var screen := get_viewport_rect().size
	var target := Vector2(minf(MAX_SIZE.x, screen.x - SCREEN_MARGIN * 2), minf(MAX_SIZE.y, screen.y - SCREEN_MARGIN * 2))
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = target
	position = (screen - size) * 0.5

func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): return
	scroll.scroll_vertical = 0
	_fit_screen()
	confirm.call_deferred("grab_focus")
