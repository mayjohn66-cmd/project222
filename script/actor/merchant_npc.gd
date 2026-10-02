class_name MerchantNpc
extends Node2D


# 심야에 가게를 찾아오는 비밀 상인. 머리 위 보라색 물음표가 "말을 걸 수 있다"는 표시다.
# 그림은 임시(도형)이며 스프라이트로 바꿀 수 있다.

var offers: Array[Dictionary] = []
var bob_time: float = 0.0
var mark: Label = null


func setup(new_offers: Array[Dictionary]) -> void:
	offers = new_offers


func _ready() -> void:
	add_to_group("merchant_npc")
	z_index = 40

	mark = Label.new()
	mark.text = "?"
	mark.position = Vector2(-14, -100)
	mark.size = Vector2(28, 32)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_size_override("font_size", 30)
	mark.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	mark.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.25))
	mark.add_theme_constant_override("outline_size", 8)
	add_child(mark)


func _process(delta: float) -> void:
	bob_time += delta
	mark.position.y = -100 + sin(bob_time * 4.0) * 4.0


# 임시 그림: 스프라이트가 준비되면 이 함수를 지우고 Sprite2D를 쓴다.
func _draw() -> void:
	draw_circle(Vector2(0, -56), 15, Color(0.85, 0.72, 0.6))
	draw_rect(Rect2(-18, -42, 36, 48), Color(0.3, 0.2, 0.45))
	draw_rect(Rect2(-18, -42, 36, 48), Color(0.12, 0.08, 0.2), false, 2.0)
	# 두건
	draw_rect(Rect2(-16, -74, 32, 16), Color(0.24, 0.15, 0.36))


func has_offers() -> bool:
	for offer in offers:
		if int(offer.get("stock", 0)) > 0:
			return true

	return false


func leave() -> void:
	remove_from_group("merchant_npc")

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
