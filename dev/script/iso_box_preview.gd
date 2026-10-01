extends Node2D
## IsoBox 미리보기: 크기·회전별 상자와 충돌 영역(빨간 선)을 한 화면에 그린다.

func _ready() -> void:
	var specs := [
		[Vector2i(1, 1), 48.0, 0, Vector2(150, 150)],
		[Vector2i(2, 1), 48.0, 0, Vector2(380, 150)],
		[Vector2i(2, 2), 90.0, 0, Vector2(640, 150)],
		[Vector2i(3, 1), 120.0, 0, Vector2(150, 360)],
		[Vector2i(1, 2), 70.0, 0, Vector2(430, 360)],
	]
	for s in specs:
		var box := IsoBox.new()
		box.footprint_size = s[0]
		box.height = s[1]
		box.rotation_index = s[2]
		box.show_outline = true
		box.position = s[3]
		add_child(box)
	var door := Node2D.new()
	door.set_script(load("res://script/objects/shop/door_visual.gd"))
	door.position = Vector2(700, 380)
	door.show_outline = true
	add_child(door)
	var door2 := Node2D.new()
	door2.set_script(load("res://script/objects/shop/door_visual.gd"))
	door2.position = Vector2(820, 380)
	door2.rotation_index = 1
	door2.show_outline = true
	add_child(door2)
	if OS.get_environment("PREVIEW_OUT") != "":
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("PREVIEW_OUT"))
		get_tree().quit()
