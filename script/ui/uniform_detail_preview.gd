extends Control
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("45463d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var paths := ["res://scenes/shop/objects/door.tscn","res://scenes/shop/warehouse/warehouse_door.tscn","res://scenes/shop/production/production_door.tscn"]
	for i in range(3):
		var object = load(paths[i]).instantiate()
		object.set_script(null)
		add_child(object)
		object.position = Vector2(360+140*i,300)
		var visual = object.get_node("Visual")
		visual.set_rotation_index(0)
		assert(visual.get_art_rect()==Rect2(Vector2(-26,-87),Vector2(52,99)))
	var script = load("res://script/ui/common/build/build_quick_slot_bar.gd")
	var factory = Control.new()
	factory.set_script(script)
	for i in range(3):
		var id: String = ["warehouse_rack","drink_machine","magic_oven"][i]
		var preview = factory._make_furniture_drag_icon(id)
		assert(preview is TextureRect and preview.texture!=null)
		assert(preview.get_child_count()==0)
		add_child(preview)
		preview.position = Vector2(330+140*i,400)
	factory.free()
	print("UNIFORM_DETAIL_OK: three identical door transforms; three icon-only drag previews")
