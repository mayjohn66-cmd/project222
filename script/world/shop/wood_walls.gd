extends Node2D

const STREET_HEIGHT := 75.0
const INTERIOR_HEIGHT := 120.0

func _ready() -> void:
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func rebuild(floor_node: Node2D, boundary: StaticBody2D) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var exterior = floor_node.get_parent().get_node_or_null("StoreExterior")
	var corner := true
	if exterior: corner = exterior._get_current_lot_type() == StoreLotData.LOT_TYPE_CORNER
	for collision in boundary.get_children():
		if not collision is CollisionShape2D or not collision.shape is SegmentShape2D: continue
		var a: Vector2 = collision.shape.a
		var b: Vector2 = collision.shape.b
		var middle := (a+b)*0.5
		var col: float = middle.x/floor_node.tile_width+middle.y/floor_node.tile_height
		var row: float = middle.y/floor_node.tile_height-middle.x/floor_node.tile_width
		var direction := 0
		if is_equal_approx(col,float(floor_node.columns)-0.5): direction = 1
		elif is_equal_approx(row,float(floor_node.rows)-0.5): direction = 2
		elif is_equal_approx(col,-0.5): direction = 3
		var street := direction == 2 or (corner and direction == 1)
		var panel := TimberPanel.new()
		# At the same edge, the wall sorts immediately behind its mounted door.
		# Compensate the drawing coordinates so the wall footprint never moves.
		panel.position = middle+Vector2(0,-1)
		panel.start = a-panel.position
		panel.end = b-panel.position
		panel.wall_height = STREET_HEIGHT if street else INTERIOR_HEIGHT
		panel.direction = direction
		panel.set_meta("wall_direction",direction)
		add_child(panel)

class TimberPanel extends Node2D:
	var start: Vector2
	var end: Vector2
	var wall_height: float
	var direction: int
	func _draw() -> void:
		var lift := Vector2(0,-wall_height)
		var base := Color("b7814c") if direction in [0,2] else Color("956339")
		# Horizontal timber boards follow the same 2:1 tile axes as the floor.
		var count := ceili(wall_height/12.0)
		for i in range(count):
			var low := Vector2(0,-minf(float(i)*12.0,wall_height))
			var high := Vector2(0,-minf(float(i+1)*12.0,wall_height))
			var tint := base.lightened(0.035) if i%2==0 else base.darkened(0.025)
			draw_colored_polygon(PackedVector2Array([start+low,end+low,end+high,start+high]),tint)
			draw_line(start+high,end+high,Color("674527"),1)
			draw_line(start+high+Vector2(0,1),end+high+Vector2(0,1),Color("d29e61"),1)
			for grain in range(2):
				var from := start.lerp(end,0.16+grain*0.43)+low+Vector2(0,-4-grain*2)
				draw_line(from,from+(end-start)*0.22,base.darkened(0.12),1)
		# Foot rail, top cap, and narrow posts join consecutive tiles.
		draw_line(start+Vector2(0,-3),end+Vector2(0,-3),Color("68452a"),6)
		draw_line(start+lift,end+lift,Color("5b3c25"),7)
		draw_line(start+lift+Vector2(0,-2),end+lift+Vector2(0,-2),Color("e0af6d"),3)
		for point in [start,end]:
			draw_line(point,point+lift,Color("72502e"),5)
			draw_line(point+Vector2(-1,0),point+lift+Vector2(-1,0),Color("c99b5f"),2)
