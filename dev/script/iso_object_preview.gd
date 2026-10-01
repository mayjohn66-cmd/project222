extends Node2D
## IsoObject 미리보기: ㄱ자 가로등(도형), 같은 도형에 곡선 그림만 씌운 것, 집(몸통 + 굴뚝 + 처마).

func _box(offset: Vector2, size: Vector2, height: float, elevation: float = 0.0, blocking: bool = true, color: Color = Color(0.8, 0.66, 0.46)) -> IsoBox:
	var b := IsoBox.new()
	b.cell_offset = offset
	b.footprint_size = size
	b.height = height
	b.elevation = elevation
	b.blocking = blocking
	b.top_color = color
	b.left_color = color.darkened(0.2)
	b.right_color = color.darkened(0.35)
	return b


func _lamp(pos: Vector2, art: Texture2D) -> IsoObject:
	var o := IsoObject.new()
	o.position = pos
	o.object_size = Vector2(1, 1)
	o.add_child(_box(Vector2(0.35, 0.35), Vector2(0.3, 0.3), 100.0))
	# 공중의 팔: 막지 않는다(노란 선).
	o.add_child(_box(Vector2(0.35, 0.35), Vector2(0.65, 0.3), 10.0, 100.0, false))
	o.show_outline = true
	if art != null:
		o.art = art
		o.art_anchor = Vector2(40, 130)
	return o


# 곡선 모양 그림(코드로 만든 임시 그림): 기둥 + 둥글게 휜 팔.
func _curved_art() -> Texture2D:
	var img := Image.create(120, 140, false, Image.FORMAT_RGBA8)
	var c := Color(0.35, 0.25, 0.15)
	for y in range(20, 131):
		for x in range(37, 44):
			img.set_pixel(x, y, c)
	for i in range(0, 60):
		var a := PI * 0.5 * float(i) / 60.0
		var x := 40 + int(50.0 * sin(a))
		var y := 40 - int(26.0 * (1.0 - cos(a)))
		for dx in 4:
			for dy in 4:
				img.set_pixel(clampi(x + dx, 0, 119), clampi(y + dy, 0, 139), c)
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	add_child(_lamp(Vector2(140, 200), null))
	add_child(_lamp(Vector2(340, 200), _curved_art()))
	var house := IsoObject.new()
	house.position = Vector2(620, 160)
	house.object_size = Vector2(2, 2)
	house.show_outline = true
	house.add_child(_box(Vector2(0, 0), Vector2(2, 2), 80.0, 0.0, true, Color(0.85, 0.75, 0.6)))
	house.add_child(_box(Vector2(0.2, 0.2), Vector2(0.4, 0.4), 40.0, 80.0, true, Color(0.55, 0.5, 0.5)))
	house.add_child(_box(Vector2(0, 0), Vector2(2, 2), 12.0, 80.0, false, Color(0.7, 0.35, 0.3)))
	add_child(house)
	var house2 := IsoObject.new()
	house2.position = Vector2(620, 380)
	house2.object_size = Vector2(2, 1)
	house2.rotation_index = 1
	house2.show_outline = true
	house2.add_child(_box(Vector2(0, 0), Vector2(1, 1), 60.0, 0.0, true, Color(0.6, 0.75, 0.85)))
	house2.add_child(_box(Vector2(1, 0), Vector2(1, 1), 36.0, 0.0, true, Color(0.9, 0.7, 0.5)))
	add_child(house2)
	if OS.get_environment("PREVIEW_OUT") != "":
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("PREVIEW_OUT"))
		get_tree().quit()
