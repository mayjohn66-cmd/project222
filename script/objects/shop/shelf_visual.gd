@tool
extends Node2D

static var VIEWS: Array = [
	ArtLoader.load_texture("res://art/world/cozy_v6/shelf_front.png"),
	ArtLoader.load_texture("res://art/world/cozy_v6/shelf_front_flipped.png"),
	ArtLoader.load_texture("res://art/world/cozy_v8/shelf_back.png"),
	ArtLoader.load_texture("res://art/world/cozy_v8/shelf_back_flipped.png")
]

@export var tile_width: float = 96.0:
	set(value):
		tile_width = value
		queue_redraw()

@export var tile_height: float = 48.0:
	set(value):
		tile_height = value
		queue_redraw()

@export var footprint_x: int = 1:
	set(value):
		footprint_x = max(1, value)
		queue_redraw()

@export var footprint_y: int = 1:
	set(value):
		footprint_y = max(1, value)
		queue_redraw()

@export var furniture_height: float = 22.0:
	set(value):
		furniture_height = value
		queue_redraw()


var stack_level: int = 1


func set_footprint(size_x: int, size_y: int):
	footprint_x = max(1, size_x)
	footprint_y = max(1, size_y)

	queue_redraw()


func set_stack_level(value: int):
	stack_level = clampi(
		value,
		1,
		3
	)

	queue_redraw()


func grid_point(x: float, y: float) -> Vector2:
	return Vector2(
		(x - y) * tile_width * 0.5,
		(x + y) * tile_height * 0.5
	)


var rotation_index: int = 0

func set_rotation_index(value: int):
	rotation_index = posmod(value, 4)
	queue_redraw()

func _draw():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if VIEWS[rotation_index] == null:
		return
	var contact := FurnitureFootprint.polygon(Vector2i.ONE,0.5,rotation_index,Vector2(tile_width,tile_height))[2]
	var foot_pixel := Vector2(48,84) if rotation_index%2==0 else Vector2(24,84)
	if rotation_index>=2: foot_pixel = Vector2(51, 84) if rotation_index==2 else Vector2(19, 84)
	for diagonal in range(footprint_x+footprint_y-1):
		for x in range(footprint_x):
			var y := diagonal-x
			if y<0 or y>=footprint_y: continue
			for level in range(stack_level):
				var base := grid_point(x,y)+Vector2(0,-furniture_height*level)
				draw_texture(VIEWS[rotation_index],(base+contact-foot_pixel).round())
