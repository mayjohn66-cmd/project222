@tool
extends Node2D

var cached_texture: Texture2D
var facility_id: String = "drink_machine"
var footprint := Vector2i.ONE
var rotation_index: int = 0
const ROOT = "res://art/world/cozy_v8/"

func set_footprint(x: int,y: int) -> void:
	footprint = Vector2i(x,y)
	queue_redraw()

func set_rotation_index(value: int) -> void:
	rotation_index = posmod(value,4)
	queue_redraw()

func configure(id: String) -> void:
	facility_id = id
	queue_redraw()

func _draw() -> void:
	var suffix := "_back" if rotation_index>=2 else "_front"
	if rotation_index%2==1: suffix += "_flipped"
	var root: String = "res://art/world/cozy_v10/" if facility_id=="magic_oven" else ROOT
	var path := root+facility_id+suffix+".png"
	if not ResourceLoader.exists(path): return
	cached_texture = load(path)
	var contact := FurnitureFootprint.polygon(footprint,1.0,rotation_index,Vector2(96,48))[2]
	var anchors: Dictionary = {"drink_machine_front": [34, 112], "drink_machine_front_flipped": [28, 112], "drink_machine_back": [30, 112], "drink_machine_back_flipped": [30, 112], "magic_oven_front": [96, 103], "magic_oven_front_flipped": [35, 103], "magic_oven_back": [102, 116], "magic_oven_back_flipped": [29, 116]}
	if facility_id == "magic_oven":
		# The reconstructed base spans 96x48 + 48x24 screen pixels (two tiles).
		# Normalize the generated 0.53 diagonal to the map's exact 0.5 projection.
		# No rotation-specific nudges: the front contact corner is the tile corner.
		var frame_size := Vector2(144,126)
		var anchor := Vector2(96,126) if rotation_index%2==0 else Vector2(48,126)
		draw_texture_rect(cached_texture,Rect2((contact-anchor).round(),frame_size),false)
		return
	var key := facility_id+suffix
	var point: Array = anchors[key]
	draw_texture(cached_texture,(contact-Vector2(point[0],point[1])).round())

