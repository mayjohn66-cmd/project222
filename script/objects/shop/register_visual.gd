@tool
extends Node2D

static var VIEWS: Array = [
	ArtLoader.load_texture("res://art/world/cozy_v6/counter_front.png"),
	ArtLoader.load_texture("res://art/world/cozy_v6/counter_front_flipped.png"),
	ArtLoader.load_texture("res://art/world/cozy_v6/counter_back.png"),
	ArtLoader.load_texture("res://art/world/cozy_v6/counter_back_flipped.png")
]
static var POS_BACK: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v5/pos_back.png")
static var POS_FRONT: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v5/pos_front.png")
static var POS_BACK_FLIPPED: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v5/pos_back_flipped.png")
static var POS_FRONT_FLIPPED: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v5/pos_front_flipped.png")

var rotation_index: int = 0
func set_rotation_index(value: int) -> void:
	rotation_index = posmod(value,4)
	queue_redraw()

@export var tile_width: float = 96.0:
	set(value):
		tile_width = value
		queue_redraw()

@export var tile_height: float = 48.0:
	set(value):
		tile_height = value
		queue_redraw()

@export var footprint_x: int = 2:
	set(value):
		footprint_x = max(1, value)
		queue_redraw()

@export var footprint_y: int = 1:
	set(value):
		footprint_y = max(1, value)
		queue_redraw()

@export var furniture_height: float = 24.0:
	set(value):
		furniture_height = value
		queue_redraw()


func set_footprint(size_x: int, size_y: int):
	footprint_x = max(1, size_x)
	footprint_y = max(1, size_y)
	queue_redraw()


func grid_point(x: float, y: float) -> Vector2:
	return Vector2(
		(x - y) * tile_width * 0.5,
		(x + y) * tile_height * 0.5
	)


func get_art_rect() -> Rect2:
	var points := FurnitureFootprint.polygon(Vector2i(footprint_x,footprint_y),0.5,rotation_index,Vector2(tile_width,tile_height))
	var front_pixel := Vector2(96,84) if rotation_index % 2 == 0 else Vector2(24,84)
	return Rect2(points[2]-front_pixel,Vector2(120,84))

func _draw():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if VIEWS[rotation_index] != null:
		draw_texture_rect(VIEWS[rotation_index],get_art_rect(),false)
	# Terminal is a separate upright sprite seated on the counter surface.
	# Directions 0/1 show its rear to customers; 2/3 show the screen.
	var terminal: Texture2D = [POS_BACK,POS_BACK_FLIPPED,POS_FRONT,POS_FRONT_FLIPPED][rotation_index]
	if terminal == null:
		return
	var along: float = 1.15 if rotation_index < 2 else -0.15
	var across: float = -0.25 if rotation_index<2 else 0.25
	var p := grid_point(along,across) if rotation_index % 2 == 0 else grid_point(across,along)
	p.y -= furniture_height
	draw_texture(terminal,(p-Vector2(12,26)).round())
