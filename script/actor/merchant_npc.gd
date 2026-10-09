class_name MerchantNpc
extends Node2D


# 심야에 가게를 찾아오는 비밀 상인. 머리 위 보라색 물음표가 "말을 걸 수 있다"는 표시다.
# 모습은 3D 거울(StoreView3D)이 그린다.

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


func leave() -> void:
	remove_from_group("merchant_npc")

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
