class_name FishingReelView
extends Control
## 당기기 화면: 가로 막대 위에 물고기 표시와 낚싯줄 구역, 아래에 게이지. 규칙은 `FishingReel`이 맡고 여기서는 그리기만 한다.

var reel: FishingReel
const BAR_COLOR := Color("d8c9a8")
const LINE_COLOR := Color("63513c")
const ZONE_OK := Color(0.42, 0.62, 0.38, 0.8)
const ZONE_MISS := Color(0.72, 0.42, 0.30, 0.8)
const FISH_COLOR := Color("322f29")
const GAUGE_COLOR := Color("b07a3a")


func _init() -> void:
	custom_minimum_size = Vector2(0, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if reel == null:
		return
	var bar := Rect2(0, 6, size.x, 36)
	draw_rect(bar, BAR_COLOR)
	var zone_size: float = float(reel.params["zone_size"])
	var zone_rect := Rect2(bar.position.x + (reel.zone - zone_size * 0.5) * bar.size.x, bar.position.y + 3, zone_size * bar.size.x, bar.size.y - 6)
	draw_rect(zone_rect, ZONE_OK if reel.inside else ZONE_MISS)
	draw_rect(bar, LINE_COLOR, false, 3.0)
	var fx: float = bar.position.x + reel.fish * bar.size.x
	var fy: float = bar.position.y + bar.size.y * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(fx - 11, fy), Vector2(fx + 5, fy - 8), Vector2(fx + 11, fy), Vector2(fx + 5, fy + 8)]), FISH_COLOR)
	draw_colored_polygon(PackedVector2Array([Vector2(fx + 9, fy), Vector2(fx + 17, fy - 7), Vector2(fx + 17, fy + 7)]), FISH_COLOR)
	var gauge := Rect2(0, 54, size.x, 14)
	draw_rect(gauge, BAR_COLOR)
	draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * clampf(reel.progress, 0.0, 1.0), gauge.size.y)), GAUGE_COLOR)
	draw_rect(gauge, LINE_COLOR, false, 2.0)
