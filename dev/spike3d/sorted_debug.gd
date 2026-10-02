extends Node
func _sky(img: Image) -> float:
	var sky: int = 0
	var tot: int = 0
	for y in range(300, 500, 3):
		for x in range(450, 750, 3):
			tot += 1
			var c: Color = img.get_pixel(x, y)
			if absf(c.r - 0.55) < 0.05 and absf(c.g - 0.72) < 0.05 and absf(c.b - 0.9) < 0.05:
				sky += 1
	return float(sky) / float(tot) * 100.0

func _ready() -> void:
	var scene = load("res://dev/spike3d/iso_sorted_spike.tscn").instantiate()
	add_child(scene)
	scene.shrink = 1
	scene._apply_shrink()
	for it in scene.items:
		it["mesh"].visible = false
	scene.actor_mesh.visible = false
	var cfg_i: int = 0
	for cfg in [["정렬 끔", true, false, 0.03], ["정렬 켬 local=0", true, true, 0.0], ["정렬 켬 local=0.03", true, true, 0.03], ["정렬 켬 local=0.03 그림자 끔", false, true, 0.03]]:
		scene.shadows = cfg[1]
		scene._apply_shrink()
		scene.sorted_mode = cfg[2]
		scene._update_sorting()
		scene.ground_material.set_shader_parameter("local_scale", cfg[3])
		for i in 6: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-project222/bebbb279-1de2-53fc-a969-a86653068aa7/scratchpad/dbg_%d.png" % cfg_i)
		cfg_i += 1
		print("%s → 중앙부 하늘색 %.1f%%" % [cfg[0], _sky(get_viewport().get_texture().get_image())])
	get_tree().quit()
