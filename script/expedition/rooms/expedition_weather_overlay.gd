class_name ExpeditionWeatherOverlay
extends Control
var environment: Dictionary = {}
var elapsed := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var room := get_parent() as ExpeditionRoomView
	if room == null or not room.is_visible_in_tree() or environment.get("weather", "clear") == "clear": return
	if room.blocked.is_valid() and room.blocked.call(): return
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var room := get_parent() as ExpeditionRoomView
	if room == null: return
	var kind := str(environment.get("weather", "clear"))
	if kind == "clear" or bool(environment.get("indoors", false)): return
	var area := room.board.grow(-6)
	if area.size.x <= 0 or area.size.y <= 0: return
	for i in range(24):
		var speed := 95.0 if kind == "snow" else 290.0
		var at := area.position + Vector2(fposmod(i * 73.0 + elapsed * 12.0, area.size.x), fposmod(i * 41.0 + elapsed * speed, area.size.y))
		if kind == "snow": draw_circle(at, 1.5, Color(0.92, 0.97, 1.0, 0.6))
		else: draw_line(at, at + Vector2(-3, 7), Color(0.7, 0.83, 0.92, 0.38), 1.0)
