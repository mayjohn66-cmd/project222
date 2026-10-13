extends Node
const SETTINGS := preload("res://scenes/expedition/rooms/default_room_settings.tres")
var checks := 0
var failures := 0
var view: ExpeditionRoomView


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(2))
	run.call_deferred()


func frame_wait(count: int = 4) -> void:
	for i in count: await get_tree().process_frame


func room() -> ExpeditionRoomModel:
	var model := ExpeditionRoomModel.new()
	var enemy := EnemyData.get_enemy("field_slime").duplicate(true)
	enemy.id = "field_slime"
	enemy.max_hp = 1000
	var profile := ExpeditionAttackProfile.new()
	profile.reach = 1.35
	profile.cooldown = 0.4
	model.setup(SETTINGS,profile,100,100,12,3,enemy,1,false,"")
	model.obstacles.clear()
	model.player_position = Vector2(3.5,4.5)
	return model


func bind(model: ExpeditionRoomModel) -> void:
	view.model = model
	view.region_id = "forest"
	view.stage.rebuild(model,"forest")
	view.stage._layout()
	view.stage._sync(model,0.0)


func run() -> void:
	check(OS.get_user_data_dir().contains("foodbag_checks"),"isolated test save")
	if failures: get_tree().quit(1); return
	GameState.initialize_new_game()
	PlayerProgress.reset()
	for gender in ["male", "female"]:
		PlayerProgress.player_gender = gender
		view = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
		add_child(view)
		await frame_wait()
		view.set_physics_process(false)
		view.stage.set_process(false)
		var model := room()
		bind(model)
		var player: ExpeditionPixelPlayer = view.stage._player
		check(player.sprite_key == "player_"+gender,"selected gender uses matching source")
		var original_scale := player.display_height
		for direction in ActorSpriteFrames.DIRECTIONS:
			var faces := {"south":45.0,"south-east":90.0,"east":135.0,"north-east":180.0,
				"north":225.0,"north-west":270.0,"west":315.0,"south-west":0.0}
			var yaw: float = faces[direction]
			model.facing = Vector2(sin(deg_to_rad(yaw)),cos(deg_to_rad(yaw)))
			model.enemies[0].position = model.player_position+model.facing*0.8
			model.enemies[1].position = Vector2(7.0,7.0)
			model.attack_remaining = 0.0
			model.feedback.clear()
			var before: int = model.enemies[0].hp
			var serial := model.attack_serial
			check(model.basic_attack(),"real melee input accepted: "+direction)
			var expected := ExpeditionDamage.calculate(model.player_attack,int(model.enemies[0].defense))
			check(model.enemies[0].hp == before-expected and model.attack_serial == serial+1,"unchanged single immediate hit")
			check(model.feedback.any(func(note): return note.get("kind","") == "damage" and int(note.get("amount",0)) == expected),"damage digits retain actual HP reduction")
			view.stage._sync(model,0.0)
			check(player.attack_direction == direction,"attack locks actual facing "+direction)
			var poses := ExpeditionPlayerAttackArt.frames(player.sprite_key,direction)
			check(poses.size() == 4,"four native attack poses")
			check(not player.work_pose.is_empty() and player.work_pose.path == poses[1].path,"strike appears with existing hit")
			check(player._material.get_shader_parameter("frame_texture") == poses[1].texture,"actual color shader uses attack PNG")
			check(player._id_material.get_shader_parameter("frame_texture") == poses[1].texture,"mask uses same PNG")
			var path: String = player.work_pose.path
			check(not model.basic_attack() and model.attack_serial == serial+1,"cooldown rejection starts no extra attack")
			view.stage._sync(model,0.0)
			check(player.work_pose.path == path,"rejected input does not restart")
			get_tree().paused = true
			await get_tree().create_timer(0.04,true).timeout
			view.stage._sync(model,0.0)
			check(player.work_pose.path == path,"paused animation remains fixed")
			get_tree().paused = false
			var duration: float = player._atk_dur
			for segment in [[0.0,1],[0.20,2],[0.50,3],[0.85,0]]:
				player._atk_t = duration*float(segment[0])
				player.animate(0.0)
				check(player.work_pose.path == poses[int(segment[1])].path,"ordered strike/follow/recovery/ready")
				check(is_equal_approx(player.display_height,original_scale),"weapon never resizes player")
				check(player._mesh.mesh.size == player._id_mesh.mesh.size,"color and mask same dimensions")
				if direction == "south-east": await capture(gender+"-"+str(segment[1]))
			# Turning/moving during recovery does not rotate the already-fired strike.
			model.facing = -model.facing
			model.player_position.x += 0.01
			view.stage._sync(model,0.0)
			check(player.work_direction == direction,"attack heading fixed while movement remains possible")
			player.animate(duration+0.01)
			check(player.work_pose.is_empty(),"attack ends without looping")
			# Same flash stays positive at fast cooldown: serial must restart motion.
			model.attack_remaining = 0.0
			check(model.basic_attack(),"next legal attack")
			view.stage._sync(model,0.0)
			check(player._atk_t == 0.0 and not player.work_pose.is_empty(),"next successful input restarts even with positive flash")
			player.cancel_attack()
		# Projectile method must never display the newly drawn sword.
		model.attack_profile.method = ExpeditionAttackProfile.Method.PROJECTILE
		model.attack_remaining = 0.0
		check(model.basic_attack(),"existing projectile input")
		view.stage._sync(model,0.0)
		check(player.work_pose.is_empty() and model.projectiles.size() == 1,"projectile has existing shot, no false sword")
		model.attack_profile.method = ExpeditionAttackProfile.Method.MELEE
		model.attack_remaining = 0.0
		model.basic_attack()
		view.stage._sync(model,0.0)
		check(not player.work_pose.is_empty(),"melee restores sword after weapon swap")
		view.stage.rebuild(room(),"forest")
		check(player.work_pose.is_empty(),"new room clears unfinished animation")
		model = room()
		bind(model)
		model.basic_attack()
		view.stage._sync(model,0.0)
		model.player_hp = 0
		view.stage._sync(model,0.0)
		check(player.work_pose.is_empty(),"defeat clears attack")
		view.queue_free()
		await frame_wait()
	print("PLAYER ATTACK checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	view.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+name+".png")
