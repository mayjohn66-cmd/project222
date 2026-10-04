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

# 벽 한 칸의 선분 데이터. 3D 거울(StoreView3D)이 start/end/direction/wall_height 를 읽어 벽을 만든다(2D 그리기는 제거됨).
class TimberPanel extends Node2D:
	var start: Vector2
	var end: Vector2
	var wall_height: float
	var direction: int
