extends Node
## 시험용 질감을 PNG 로 내보낸다(개발용). 알베도 <kind>_<크기>.png 와 높이 맵 <kind>_<크기>_h.png.
## 법선 맵 _n.png 는 tools/art/height_to_normal.py 로 만든다(실제 제작 흐름과 같음).
func _ready() -> void:
	var size: int = 18
	var dir: String = ProjectSettings.globalize_path("res://dev/spike3d/textures/")
	DirAccess.make_dir_recursive_absolute(dir)

	for kind in ["brick", "plank"]:
		var albedo: Image = (load("res://dev/spike3d/iso_room_spike.gd").make_texture(kind, size) as ImageTexture).get_image()
		albedo.convert(Image.FORMAT_RGBA8)
		albedo.save_png("%s%s_%d.png" % [dir, kind, size])
		load("res://dev/spike3d/iso_room_spike.gd").make_height_image(kind, size).save_png("%s%s_%d_h.png" % [dir, kind, size])

	print("exported to ", dir)
	get_tree().quit()
