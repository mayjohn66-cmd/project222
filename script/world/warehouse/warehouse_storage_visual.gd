@tool
extends Node2D


@export var tile_width: float = 96.0:
	set(value):
		tile_width = maxf(value, 1.0)
		queue_redraw()

@export var tile_height: float = 48.0:
	set(value):
		tile_height = maxf(value, 1.0)
		queue_redraw()

@export var visual_height: float = 36.0:
	set(value):
		visual_height = maxf(value, 1.0)
		queue_redraw()


var footprint_width: int = 2
var footprint_height: int = 1
var rotation_index: int = 0


func set_footprint(
	width: int,
	height: int
) -> void:
	footprint_width = maxi(width, 1)
	footprint_height = maxi(height, 1)
	queue_redraw()


func set_rotation_index(
	value: int
) -> void:
	rotation_index = posmod(value, 4)
	queue_redraw()


const VIEWS = [
	preload("res://art/world/cozy_v6/rack_front.png"),
	preload("res://art/world/cozy_v6/rack_front_flipped.png"),
	preload("res://art/world/cozy_v8/rack_back.png"),
	preload("res://art/world/cozy_v8/rack_back_flipped.png")
]

func _draw() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var contact := FurnitureFootprint.polygon(Vector2i(footprint_width,footprint_height),1.0,rotation_index,Vector2(tile_width,tile_height))[2]
	var foot_pixel := Vector2(96,128) if rotation_index%2==0 else Vector2(48,128)
	if rotation_index>=2: foot_pixel = Vector2(101, 128) if rotation_index==2 else Vector2(38, 128)
	draw_texture(VIEWS[rotation_index],(contact-foot_pixel).round())
