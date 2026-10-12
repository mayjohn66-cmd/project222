class_name StoryNpc
extends Node2D


# 가게 안에서 대화를 기다리는 스토리 NPC.
# 머리 위 느낌표가 "대화할 수 있다"는 표시다. 모습은 3D 거울(StoreView3D)이 그린다.

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
	mark.add_theme_font_size_override("font_size", UiTypography.size(30))
	mark.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	mark.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.05))
	mark.add_theme_constant_override("outline_size", 8)
	add_child(mark)


func _process(delta: float) -> void:
	bob_time += delta
	mark.position.y = -92 + sin(bob_time * 4.0) * 4.0


func leave() -> void:
	remove_from_group("story_npc")

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)
