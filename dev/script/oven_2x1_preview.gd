extends Control
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("45463d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for direction in range(4):
		var object = preload("res://scenes/shop/production/production_facility.tscn").instantiate()
		object.set_meta("build_id","magic_oven")
		add_child(object)
		object.configure_facility("magic_oven")
		object.position = Vector2(160+260*direction,250)
		var size := Vector2i(2,1) if direction%2==0 else Vector2i(1,2)
		var visual = object.get_node("Visual")
		visual.set_footprint(size.x,size.y)
		visual.set_rotation_index(direction)
		object.get_node("Collision").set_footprint(size.x,size.y)
		for x in range(size.x):
			for y in range(size.y):
				var line := Line2D.new()
				line.points = FurnitureFootprint.polygon(Vector2i.ONE,1,0,Vector2(96,48))
				line.position = Vector2((x-y)*48,(x+y)*24)
				line.closed = true
				line.width = 1
				line.default_color = Color.CYAN
				line.z_index = 20
				object.add_child(line)
	var door = preload("res://scenes/shop/production/production_door.tscn").instantiate()
	door.set_script(null)
	add_child(door)
	door.position = Vector2(490,470)
	var card = GameConfig.ITEM_CARD_SCENE.instantiate()
	add_child(card)
	card.position = Vector2(570,370)
	card.setup_furniture("production_door",1)
	assert(card.get_node("IconRect").texture.resource_path=="res://art/furniture/pixel_v1/production_door.png")
	print("OVEN_2X1_OK: four directions with two ground cells and matching production door icon")
