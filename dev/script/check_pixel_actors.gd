extends Node
## 실제 매장 렌더러에서 역할 선택, 여백 보정, 걷기/정지/숨김/앉기/제거를 검증한다.
class TestActor extends Node2D:
	var employee_id := ""
	var customer_type_id := ""

var checks := 0
var failures := 0
var world: Node2D
var view: StoreView3D


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()


func frames(count: int = 4) -> void:
	for i in count:
		await get_tree().process_frame


func run() -> void:
	for key in ActorSpriteFrames.KEYS:
		var set_data := ActorSpriteFrames.load_set(key)
		check(not set_data.is_empty(), "complete set: " + key)
		if set_data.is_empty():
			continue
		check(set_data == ActorSpriteFrames.load_set(key), "cached textures: " + key)
		for d in ActorSpriteFrames.DIRECTIONS:
			var pose: Dictionary = set_data.directions[d]
			check(pose.walk.size() == 8, "8 walking frames: " + key + "/" + d)
			# Canvas-independent feet remain near the original 64px grid bottom.
			check(pose.anchor.y >= 27.0 and pose.anchor.y <= 32.0, "idle foot anchor: " + key + "/" + d)
			for f in pose.walk:
				var texture: Texture2D = f.texture
				var top: float = float(f.bounds.position.y) - texture.get_height() * 0.5
				check(float(set_data.reference_height) >= pose.anchor.y - top, "constant scale contains entire silhouette")
	check(ActorSpriteFrames.load_set("no_art").is_empty(), "unknown art falls back without loading")
	check(ActorSpriteFrames.direction_for(45.0,45.0) == "south", "towards camera is south")
	check(ActorSpriteFrames.direction_for(90.0,45.0) == "south-east", "+X projects right/down")
	check(ActorSpriteFrames.direction_for(0.0,45.0) == "south-west", "+Z projects left/down")
	check(ActorSpriteFrames.direction_for(-135.0,45.0) == "north", "away from camera is north")
	check(ActorSpriteFrames.direction_for(405.0,45.0) == "south", "angle wrapping")
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(10)
	view = world.get_node("StoreView3D")
	check(view.use_pixel_actors, "main uses uploaded sprites by default")
	# Freeze simulation only; manually drive the display for deterministic screenshot/animation.
	get_tree().paused = true
	freeze(world)
	var actors: Array[TestActor] = []
	for i in ActorSpriteFrames.KEYS.size():
		var key: String = ActorSpriteFrames.KEYS[i]
		if key.begins_with("player_"):
			continue  # 주인공 그림은 아래에서 따로 확인한다(직원·손님 역할이 아니다)
		var actor := TestActor.new()
		world.get_node("Actors").add_child(actor)
		if key.begins_with("worker_"):
			actor.employee_id = key
			actor.add_to_group("worker")
		else:
			actor.customer_type_id = key
			actor.add_to_group("customer")
		var cell := Vector2(2.0 + float(i % 6), 2.0 + float(i / 6) * 2.0)
		actor.global_position = world.get_node("Floor").to_global(world.get_node("Floor").grid_to_local(Vector2i(cell)))
		actors.append(actor)
	view._sync_actors(0.016)
	view._sort_and_update()
	for actor in actors:
		var entry: Dictionary = view._actors[actor.get_instance_id()]
		check(entry.figure is PixelActorFigure, "actual store actor uses sprite")
	var player_figure = view._actors[view.player.get_instance_id()].figure
	check(player_figure is PixelActorFigure and player_figure.sprite_key == "player_" + PlayerProgress.player_gender, "player uses the sprite of the chosen gender")
	var subtype_actor: TestActor = actors[3]
	subtype_actor.customer_type_id = "warrior"
	check(StoreActorVisuals.sprite_key(subtype_actor,"warrior") == "adventurer", "customer subtype maps to supplied group art")
	subtype_actor.set_meta("look_key","commuter")
	check(StoreActorVisuals.sprite_key(subtype_actor,"commuter").is_empty(), "modern cutscene costume overrides customer group art")
	subtype_actor.remove_meta("look_key")
	subtype_actor.customer_type_id = "normal"
	var actor: TestActor = actors[0]
	var figure: PixelActorFigure = view._actors[actor.get_instance_id()].figure
	check(figure.sprite_key == "worker_001", "worker selected by employee_id")
	check(is_equal_approx(figure.display_height, view.ACTOR_TOTAL * PixelActorFigure.PROJECTION_HEIGHT), "projected adult height matches existing models")
	var original_height := figure.display_height
	var seen: Dictionary = {}
	for d in range(8):
		actor.set_meta("face_lock", Vector2(sin(deg_to_rad(45.0 + d * 45.0)), cos(deg_to_rad(45.0 + d * 45.0))))
		for f in range(8):
			actor.global_position += Vector2(0.7,0.0)
			view._sync_actors(0.025)
			figure.move_speed = 1.0
			figure.phase = float(f) / 8.0
			figure.animate(0.0) # zero delta must show idle
			check(figure.frame_index == -1, "paused display shows idle")
			figure.phase = float(f) / 8.0
			figure.animate(0.001)
			view._sort_and_update()
			seen[figure.direction] = true
			check(figure.frame_index == f, "distance-based frame selection")
			check(figure._mesh.mesh.size == figure._id_mesh.mesh.size, "color/mask silhouette agree")
			check(figure._material.get_shader_parameter("frame_offset") == figure._id_material.get_shader_parameter("frame_offset"), "color/mask anchor agree")
			check(is_equal_approx(figure.display_height, original_height), "no direction/frame resize")
	check(seen.size() == 8, "all directions seen in real store")
	# 걷기 그림이 바뀌는 속도: 빨리 걸어도 초당 MAX_FPS 를 넘지 않고, 느려도 MIN_FPS 아래로 내려가지 않는다
	for speed in [0.4, 1.0, 2.0, 4.0]:
		figure.walking = true
		figure.move_speed = speed
		figure.phase = 0.0
		figure.frame_index = -1
		var changes := 0
		var last := -2
		for i in range(60):
			figure.animate(1.0 / 60.0)
			if figure.frame_index != last:
				changes += 1
				last = figure.frame_index
		check(changes <= int(PixelActorFigure.MAX_FPS) + 2, "walk frame rate capped at speed %.1f (changes/s=%d)" % [speed, changes])
		check(changes >= int(PixelActorFigure.MIN_FPS) - 1, "walk frame rate not frozen at speed %.1f (changes/s=%d)" % [speed, changes])
	figure.walking = false
	figure.animate(0.016)
	actor.visible = false
	view._sync_actors(0.016)
	check(not figure.visible and not figure._id_root.visible, "hidden actor also hides mask")
	actor.visible = true
	actor.remove_meta("face_lock")
	actor.employee_id = "worker_003"
	view._sync_actors(0.016)
	figure = view._actors[actor.get_instance_id()].figure
	check(figure.sprite_key == "worker_003", "changed employee updates artwork")
	actor.set_meta("sitting",true)
	view._sync_actors(0.016)
	check(not view._actors[actor.get_instance_id()].figure is PixelActorFigure, "seated cutscene retains pose-capable model")
	actor.remove_meta("sitting")
	view._sync_actors(0.016)
	check(view._actors[actor.get_instance_id()].figure is PixelActorFigure, "standing restores supplied sprite")
	view.use_pixel_actors = false
	view._sync_actors(0.016)
	check(not view._actors[actor.get_instance_id()].figure is PixelActorFigure, "renderer switch restores original")
	view.use_pixel_actors = true
	view._sync_actors(0.016)
	view._sort_and_update()
	await capture("idle")
	# Actual source frames rendered in the same position, with a fixed foot anchor.
	for f in [0,2,4,6]:
		for a in actors:
			var sprite: PixelActorFigure = view._actors[a.get_instance_id()].figure
			sprite.walking = true
			sprite.move_speed = 1.0
			sprite.facing_yaw_deg = 90.0
			sprite.phase = float(f) / 8.0
			sprite.animate(0.001)
		view._sort_and_update()
		await capture("walk-" + str(f))
	view.apply_hour(12.0)
	view._sync_actors(0.016)
	view._sort_and_update()
	var lit: PixelActorFigure = view._actors[actor.get_instance_id()].figure
	var daytime: Color = lit._material.get_shader_parameter("light_tint")
	await capture("day")
	view.apply_hour(22.0)
	view._sync_actors(0.016)
	view._sort_and_update()
	var nighttime: Color = lit._material.get_shader_parameter("light_tint")
	check(nighttime.get_luminance() < daytime.get_luminance(), "sprite follows night tint instead of glowing")
	await capture("night")
	# A real sorted counter goes in front of one actor and behind another.
	view.apply_hour(12.0)
	actor.global_position = view.cell_to_world(Vector2(4.0,4.0))
	actors[1].global_position = view.cell_to_world(Vector2(4.0,5.0))
	view._set_item("pixel_check_counter",Vector2(3.0,4.3),Vector2(5.0,4.7),1.1,"wood",Color.WHITE,"pixel-check")
	view._sync_actors(0.016)
	view._sort_and_update()
	var behind: PixelActorFigure = view._actors[actor.get_instance_id()].figure
	var front: PixelActorFigure = view._actors[actors[1].get_instance_id()].figure
	var counter_rank: float = view._items["pixel_check_counter"].material.get_shader_parameter("rank")
	check(float(behind._material.get_shader_parameter("rank")) < counter_rank, "sprite behind counter sorts behind it")
	check(float(front._material.get_shader_parameter("rank")) > counter_rank, "sprite in front of counter sorts in front of it")
	await capture("counter")
	view._remove_item("pixel_check_counter")
	var removed_id := actor.get_instance_id()
	actor.queue_free()
	await frames()
	view._sync_actors(0.016)
	check(not view._actors.has(removed_id), "removed actor cleaned from store")
	await frames()
	get_tree().paused = false
	print("[pixel actors] checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)


func capture(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	await frames(8)
	await RenderingServer.frame_post_draw
	var path := args[0] + "-" + label + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("[pixel actors] screenshot ",label)


func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)
