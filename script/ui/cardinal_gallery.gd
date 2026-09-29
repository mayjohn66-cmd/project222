extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("282821")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for direction in range(4):
		var label := Label.new()
		label.text = str(direction*90)+"°"
		label.add_theme_color_override("font_color",Color("f4ddb1"))
		label.position = Vector2(182+230*direction,30)
		add_child(label)
		for row in range(3):
			var path: String = ["res://scenes/shop/objects/shelf.tscn","res://scenes/shop/objects/register.tscn","res://scenes/shop/warehouse/warehouse_storage.tscn"][row]
			var object = load(path).instantiate()
			add_child(object)
			object.position = Vector2(190+230*direction,170+175*row)
			var visual = object.get_node("Visual")
			var size := Vector2i.ONE if row==0 else (Vector2i(2,1) if direction%2==0 else Vector2i(1,2))
			visual.set_footprint(size.x,size.y)
			visual.set_rotation_index(direction)
			var p := FurnitureFootprint.polygon(size,1.0 if row==2 else 0.5,direction,Vector2(96,48))
			var full := Line2D.new()
			full.points = FurnitureFootprint.polygon(size,1.0,0,Vector2(96,48))
			full.closed = true
			full.width = 1
			full.default_color = Color(0.65,0.65,0.65,0.5)
			object.add_child(full)
			var outline := Line2D.new()
			outline.points = p
			outline.closed = true
			outline.width = 1
			outline.default_color = Color.CYAN
			outline.z_index = 20
			object.add_child(outline)

