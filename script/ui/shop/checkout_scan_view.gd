class_name CheckoutScanView
extends Control
## 스캔 막대 그리기. 규칙은 CheckoutScan 이 가진다.

var scan: CheckoutScan


func _init() -> void:
	custom_minimum_size = Vector2(400, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.11, 0.1), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.6, 0.35), false, 2.0)
	if scan == null:
		return
	var good := Rect2((scan.center - scan.good_half) * size.x, 3.0, scan.good_half * 2.0 * size.x, size.y - 6.0)
	draw_rect(good, Color(0.35, 0.55, 0.3))
	var perfect := Rect2((scan.center - scan.perfect_half) * size.x, 3.0, scan.perfect_half * 2.0 * size.x, size.y - 6.0)
	draw_rect(perfect, Color(0.95, 0.82, 0.3))
	var x: float = scan.cursor * size.x
	draw_rect(Rect2(x - 2.0, 0.0, 4.0, size.y), Color(1, 1, 1))
