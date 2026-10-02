extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("45463d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for direction in range(4):
		for row in range(3):
			var id: String = ["drink_machine","magic_oven","production_door"][row]
			var path := "res://scenes/shop/production/production_door.tscn" if row==2 else "res://scenes/shop/production/production_facility.tscn"
			var object = load(path).instantiate()
			if row==2: object.set_script(null)
			object.set_meta("build_id",id)
			add_child(object)
			object.position = Vector2(170+260*direction,160+185*row)
			var visual = object.get_node("Visual")
			var size := Vector2i.ONE if row!=1 else (Vector2i(2,1) if direction%2==0 else Vector2i(1,2))
			visual.set_footprint(size.x,size.y)
			visual.set_rotation_index(direction)
			if row!=2:
				object.configure_facility(id)
				object.get_node("Collision").set_footprint(size.x,size.y)
				assert(object.get_node("Collision").polygon.size()==4)
			var line := Line2D.new()
			line.points = FurnitureFootprint.polygon(size,1.0,direction,Vector2(96,48))
			line.closed = true
			line.width = 1
			line.default_color = Color.CYAN
			line.z_index = 20
			object.add_child(line)
	print("PRODUCTION_ART_OK: all four directions configured and collision polygons created")
