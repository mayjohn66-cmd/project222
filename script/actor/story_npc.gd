class_name StoryNpc
extends Node2D


# 가게 안에서 대화를 기다리는 스토리 NPC.
# 머리 위 느낌표가 "대화할 수 있다"는 표시다. 그림은 임시(도형)이며 스프라이트로 바꿀 수 있다.

var beat: Dictionary = {}
var bob_time: float = 0.0
var mark: Label = null


func setup(new_beat: Dictionary) -> void:
	beat = new_beat


func _ready() -> void:
	add_to_group("story_npc")
	z_index = 40

	mark = Label.new()
	mark.text = "!"
	mark.position = Vector2(-14, -92)
	mark.size = Vector2(28, 32)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_size_override("font_size", 30)
	mark.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	mark.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.05))
	mark.add_theme_constant_override("outline_size", 8)
	add_child(mark)


func _process(delta: float) -> void:
	bob_time += delta
	mark.position.y = -92 + sin(bob_time * 4.0) * 4.0


# 임시 그림: 스프라이트가 준비되면 이 함수를 지우고 Sprite2D를 쓴다.
func _draw() -> void:
	draw_circle(Vector2(0, -52), 15, Color(0.91, 0.77, 0.63))
	draw_rect(Rect2(-16, -38, 32, 44), Color(0.35, 0.49, 0.38))
	draw_rect(Rect2(-16, -38, 32, 44), Color(0.24, 0.18, 0.12), false, 2.0)


func can_talk() -> bool:
	return not beat.is_empty()


func leave() -> void:
	remove_from_group("story_npc")

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)
