extends Node
## 실제 게임 화면을 도트 배율(3배 = 지금, 2배, 1배)별로 저장해 비교한다(개발용, 화면 필요: xvfb).
## 사용: godot --path . res://dev/spike3d/pixel_scale_shot.tscn -- <저장 폴더> [배율들 예: 3,2]
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "/tmp/pixel_scale"
	var scales: PackedStringArray = (args[1] if args.size() > 1 else "3,2").split(",")
	DirAccess.make_dir_recursive_absolute(dir)
	GameState.initialize_new_game()
	PlayerProgress.player_name = "테스터"
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	var view: StoreView3D = null
	for n in world.find_children("*", "", true, false):
		if n is StoreView3D: view = n; break
	if view == null:
		print("StoreView3D 없음"); get_tree().quit(); return
	var n_shrink: int = int(scales[0])
	view.configure_scale(n_shrink)   # _build_view 가 돌기 전(같은 프레임)에 정한다
	for i in range(90): await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/scale_%dx.png" % [dir, n_shrink])
	print("saved scale ", n_shrink, " tile_low=", view.tile_low)
	get_tree().quit()
