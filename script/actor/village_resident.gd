class_name VillageResident
extends Node2D

const VISUAL = preload("res://script/actor/character_visual.gd")
var resident_id: String
var customer_type_id: String
var customer_group_id: String
var title: Label

func _ready() -> void:
	y_sort_enabled = true
	var visual := AnimatedSprite2D.new()
	visual.set_script(VISUAL)
	visual.actor_role = "customer"
	add_child(visual)
	title = Label.new()
	title.position = Vector2(-110, -88)
	title.size = Vector2(220, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("fff0d0"))
	title.add_theme_color_override("font_outline_color", Color("302415"))
	title.add_theme_constant_override("outline_size", 4)
	add_child(title)

func refresh_title(entry: Dictionary) -> void:
	title.text = str(entry["name"]) + " [E]\n" + VillageLifeFlow.friendship_name(resident_id)
