extends Node
## 실제 매장 인물의 식별·정지 그림·마스크·조명 연결을 검증한다.
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
	for i in count: await get_tree().process_frame

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(10)
	view = world.get_node("StoreView3D")
	get_tree().paused = true
	freeze(world)
	var actors: Array[StoryNpc] = []
	var index := 0
	for id in NpcSpriteArt.assets():
		var actor := StoryNpc.new()
		actor.setup({"npc_id": id, "beat_id": "art-check", "lines": []})
		world.get_node("Actors").add_child(actor)
		actor.mark.text = str(NpcSpriteArt.assets()[id].name)
		actor.mark.position = Vector2(-60,-86)
		actor.mark.size = Vector2(120,30)
		actor.mark.add_theme_font_size_override("font_size", 16)
		actor.global_position = view.cell_to_world(Vector2(1.5 + index % 5 * 1.7, 2.0 + int(index / 5) * 2.0))
		actors.append(actor)
		index += 1
	view._sync_actors(0.016)
	view._sort_and_update()
	for actor in actors:
		var key := NpcSpriteArt.key_for(str(actor.beat.npc_id))
		var figure = view._actors[actor.get_instance_id()].figure
		check(figure is PixelActorFigure, "named actor is 2D: " + key)
		if not figure is PixelActorFigure: continue
		check(figure.sprite_key == key, "correct identity: " + key)
		var sprite := figure as PixelActorFigure
		var frame: Dictionary = sprite.frame_set.directions["south-west"].idle
		check(frame.texture.get_size() == Vector2(96,96), "corrected 96px source: " + key)
		check(FileAccess.get_sha256(frame.path) == str(NpcSpriteArt.assets()[str(actor.beat.npc_id)].sha256), "source pixels preserved: " + key)
		var extent: Vector2 = sprite._mesh.mesh.size
		check(is_equal_approx(extent.x / extent.y, float(frame.bounds.size.x) / float(frame.bounds.size.y)), "no aspect distortion: " + key)
		for yaw in [0.0,90.0,180.0,270.0]:
			sprite.facing_yaw_deg = yaw
			sprite.walking = true
			sprite.animate(0.15)
			view._sort_and_update()
			check(sprite.direction == "south-west" and sprite.frame_index == -1, "prepared static direction remains valid during movement")
			check(sprite._mesh.mesh.size == extent and sprite._id_mesh.mesh.size == extent, "stable matching color/mask geometry")
		check(sprite._material.get_shader_parameter("normal_texture") != null, "normal map participates in world lighting")
		check(sprite._material.get_shader_parameter("frame_offset") == sprite._id_material.get_shader_parameter("frame_offset"), "color/mask feet agree")
	# Guide and merchant must not be confused with ordinary villager/peddler customers.
	var guide := CheckoutGuideCustomer.new()
	check(StoreActorVisuals.sprite_key(guide,"normal") == "npc:delvin", "first checkout guide is Delvin")
	guide.free()
	var resident := VillageResident.new()
	resident.resident_id = "naru"
	check(StoreActorVisuals.sprite_key(resident,"story_npc") == "npc:naru", "settled merchant retains identity")
	resident.resident_id = "fishing_visitor:traveler_water"
	check(StoreActorVisuals.sprite_key(resident,"story_npc") == "npc:traveler_water", "fishing visitor retains identity")
	resident.resident_id = "unnamed_visit"
	resident.customer_type_id = "miner"
	check(StoreActorVisuals.sprite_key(resident,"story_npc") == "miner", "other resident uses role artwork")
	resident.customer_group_id = "child"
	resident.customer_type_id = "future_story_child"
	check(StoreActorVisuals.sprite_key(resident,"story_npc") == "child", "story subtype preserves its supplied role group")
	resident.resident_id = "village_blacksmith"
	resident.set_meta("look_key","story_npc")
	check(StoreActorVisuals.sprite_key(resident,"story_npc") == "pose:blacksmith", "blacksmith uses dedicated 2D work clothes")
	resident.free()
	var extra := StoryNpc.new()
	extra.setup({"npc_id":"neighbor"})
	check(StoreActorVisuals.sprite_key(extra,"story_npc") == "npc:neighbor_bread", "legacy neighbor ID resolves correctly")
	extra.set_meta("look_key","backpacker")
	check(StoreActorVisuals.sprite_key(extra,"backpacker") == "traveler", "prologue visitor uses matching supplied role")
	extra.set_meta("look_key","commuter")
	check(StoreActorVisuals.sprite_key(extra,"commuter") == "pose:commuter", "modern costume uses dedicated office worker art")
	extra.free()
	var customer = load("res://script/actor/customer.gd").new()
	customer.customer_type_id = "peddler"
	customer.add_to_group("customer")
	check(StoreActorVisuals.sprite_key(customer,"normal") == CustomerTypeData.get_group_id("peddler"), "ordinary peddler is not named merchant")
	customer.free()
	# Real directors supply canonical IDs without parsing rendered labels.
	var tutorial: TutorialDirector = world.get_node("TutorialDirector")
	check(NpcPortraits.npc_id_of(tutorial.SETTINGS.merchant_name) == "naru", "tutorial merchant ID")
	var requests := ResidentRequestDirector.new()
	world.add_child(requests)
	requests.enabled = false
	requests._prepare_npc("art-request", "여행자 라슈", [])
	check(str(requests.npc.beat.get("npc_id")) == "traveler_water", "request spawn records speaker identity")
	requests.npc.queue_free()
	requests.queue_free()
	view.apply_hour(12.0)
	view._sync_actors(0.016)
	view._sort_and_update()
	var daytime: Image = await capture("day")
	view.apply_hour(22.0)
	view._sync_actors(0.016)
	view._sort_and_update()
	var nighttime: Image = await capture("night")
	if daytime != null and nighttime != null:
		check(daytime.get_data() != nighttime.get_data(), "actual renderer changes with time lighting")
	var removed: StoryNpc = actors[0]
	var removed_id := removed.get_instance_id()
	var removed_figure: PixelActorFigure = view._actors[removed_id].figure
	removed.visible = false
	view._sync_actors(0.016)
	check(not removed_figure.visible and not removed_figure._id_root.visible, "hidden NPC hides mask")
	removed.queue_free()
	await frames()
	view._sync_actors(0.016)
	check(not view._actors.has(removed_id), "departed NPC renderer cleaned up")
	get_tree().paused = false
	print("[npc sprite art] checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func capture(label: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await frames(8)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): image.save_png(args[0] + "-" + label + ".png")
	return image
