class_name HpBar
extends Control


# 체력을 숫자 없이 그림으로만 보여 주는 막대(사용자 결정: 공개하는 능력치는 HP뿐이고 그림으로만).
# 하트 아이콘 + 막대이며 체력이 줄면 색이 노랑 → 빨강으로 바뀐다.

const BAR_BACK := Color("2a1a1f")
const BAR_EDGE := Color("f4eddb")
const HEART_COLOR := Color("e2565f")

var ratio: float = 1.0


func _init() -> void:
	custom_minimum_size = Vector2(260, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_hp(
	current: int,
	maximum: int
) -> void:
	var new_ratio: float = 0.0

	if maximum > 0:
		new_ratio = clampf(float(current) / float(maximum), 0.0, 1.0)

	if not is_equal_approx(new_ratio, ratio):
		ratio = new_ratio
		queue_redraw()


func _draw() -> void:
	var height: float = size.y
	var heart_size: float = height

	# 하트(사각 두 개와 삼각형으로 그린 단순한 모양)
	var hx: float = 1.0
	var hy: float = 2.0
	var u: float = heart_size / 8.0
	draw_circle(Vector2(hx + u * 2.2, hy + u * 2.4), u * 1.7, HEART_COLOR)
	draw_circle(Vector2(hx + u * 5.2, hy + u * 2.4), u * 1.7, HEART_COLOR)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(hx + u * 0.6, hy + u * 3.2),
			Vector2(hx + u * 6.8, hy + u * 3.2),
			Vector2(hx + u * 3.7, hy + u * 6.8)
		]),
		HEART_COLOR
	)

	var bar := Rect2(
		Vector2(heart_size + 6.0, 3.0),
		Vector2(maxf(size.x - heart_size - 8.0, 4.0), maxf(height - 6.0, 4.0))
	)
	draw_rect(bar, BAR_BACK)

	var fill_color: Color = Color("6fcf6f")

	if ratio < 0.35:
		fill_color = Color("e2565f")
	elif ratio < 0.65:
		fill_color = Color("e8c25a")

	if ratio > 0.0:
		var fill := Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y))
		draw_rect(fill, fill_color)
		draw_rect(
			Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.35)),
			fill_color.lightened(0.3)
		)

	draw_rect(bar, BAR_EDGE, false, 2.0)
