extends Node
## 마을 물체 목록(이름, 그림 파일, 발자국 칸 크기)을 출력한다(개발용).
func _ready() -> void:
	var scene = load("res://scenes/shop/main.tscn").instantiate()
	add_child(scene)
	var mirror := StoreView3D.new()
	scene.add_child(mirror)
	for i in range(80):
		await get_tree().process_frame
	var village = mirror.village
	for cname in VillageMirror.CONTAINERS:
		var c = scene.get_node_or_null(cname)
		if c == null:
			continue
		for body in c.get_children():
			if not body is StaticBody2D:
				continue
			var rect: Rect2 = village._footprint_cell_rect(body)
			var info: Dictionary = village._sprite_info(body)
			print("OBJ|", cname, "|", body.name, "|", str(info["path"]), "|size=", snappedf(rect.size.x, 0.01), "x", snappedf(rect.size.y, 0.01), "|sprite_h=", snappedf(info["height_px"], 1.0), "|vis=", body.visible)
	get_tree().quit()
