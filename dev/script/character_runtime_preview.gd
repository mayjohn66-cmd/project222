extends Node2D
var characters: Array[Node2D] = []
const IDS := ["player","worker_001","worker_002","worker_003","normal","traveler"]
const NAMES := ["플레이어","직원 1","직원 2","직원 3","일반 손님","여행자"]
const DIRECTIONS := [Vector2.RIGHT,Vector2(1,1),Vector2.DOWN,Vector2(-1,1),Vector2.LEFT,Vector2(-1,-1),Vector2.UP,Vector2(1,-1)]

func _ready() -> void:
	call_deferred("run_preview")

func visual(actor: Node) -> AnimatedSprite2D:
	return actor.get_node("AnimatedSprite2D" if actor==characters[0] else "Visual")

func run_preview() -> void:
	$DayManager/HourTimer.stop()
	$UI.hide()
	var center: Vector2 = $Floor.to_global($Floor.grid_to_local(Vector2i(4,4)))
	characters.append($Actors/Player)
	for id in EmployeeData.get_all_employee_ids():
		assert(id in IDS)
		characters.append($Actors.get_node("Employee_"+id))
	for id in ["normal","traveler"]:
		assert(CustomerTypeData.has_customer_type(id))
		var customer = preload("res://scenes/shop/actors/customer.tscn").instantiate()
		customer.customer_type_id = id
		customer.customer_type_selected = true
		$Actors.add_child(customer)
		characters.append(customer)
	assert(characters.size()==6)
	$Actors/Player/Camera2D.enabled = false
	var camera := Camera2D.new()
	camera.position = center+Vector2(0,-20)
	camera.zoom = Vector2(1.5,1.5)
	add_child(camera)
	for i in range(characters.size()):
		var actor := characters[i]
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.show()
		actor.global_position = center+Vector2((i-2.5)*100,0)
		var sprite := visual(actor)
		sprite.refresh_profile()
		assert(sprite.profile_id==IDS[i])
		var caption := Label.new()
		caption.text = NAMES[i]
		caption.position = Vector2(-40,8)
		caption.size = Vector2(80,24)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size",13)
		caption.add_theme_color_override("font_color",Color("fff4da"))
		caption.add_theme_color_override("font_outline_color",Color("39271e"))
		caption.add_theme_constant_override("outline_size",4)
		actor.add_child(caption)
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--gallery"):
		for actor in characters:
			visual(actor).set_process(false)
			visual(actor).play("walk_down_left")
		return
	for sector in range(8):
		var expected: String = visual(characters[0]).DIRECTION_NAMES[sector]
		var seen_frames: Dictionary = {}
		for tick in range(36):
			for actor in characters: actor.global_position += DIRECTIONS[sector].normalized()*1.5
			await get_tree().process_frame
			if tick>2:
				for actor in characters:
					var sprite := visual(actor)
					assert(str(sprite.animation)=="walk_"+expected)
					assert(sprite.flip_h==(sector in [0,1,7]))
					assert(sprite.sprite_frames.get_frame_count(sprite.animation)==4)
				seen_frames[visual(characters[0]).frame]=true
		assert(seen_frames.size()>=2)
	for tick in range(15): await get_tree().process_frame
	for actor in characters:
		assert(str(visual(actor).animation)=="idle_up_right")
	# Entrance and exit tweens must animate despite velocity being zero.
	var tween := create_tween().set_parallel(true)
	for actor in characters: tween.tween_property(actor,"position",actor.position+Vector2(-40,0),0.5)
	for tick in range(8): await get_tree().process_frame
	for actor in characters: assert(str(visual(actor).animation)=="walk_left")
	await tween.finished
	for tick in range(15): await get_tree().process_frame
	for actor in characters: assert(str(visual(actor).animation)=="idle_left")
	# Teleports should reset to idle, never fabricate a long walking stride.
	for actor in characters: actor.global_position += Vector2(200,0)
	for tick in range(2): await get_tree().process_frame
	for actor in characters: assert(str(visual(actor).animation)=="idle_left")
	print("CHARACTERS_OK: six data identities, eight directions, multi-frame walks, idle, mirrored facing, entrance tweens and teleport reset")
