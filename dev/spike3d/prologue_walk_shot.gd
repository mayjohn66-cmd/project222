extends Node
## 프롤로그 독백 사이의 움직임 확인: 줄마다 대사창이 숨겨지는지, 주인공이 어디로 걷는지 위치를 찍고 화면을 저장한다.
## 사용: godot --path . res://dev/spike3d/prologue_walk_shot.tscn -- <저장 폴더>   (xvfb 등 화면 필요)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func snap(dir: String, name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "/tmp/prologue_walk"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	var director: TutorialDirector = world.get_node("TutorialDirector")
	var view = world.get_node("StoreView3D")
	var player: Node2D = world.get_node("Actors/Player")
	var guard := 0
	var shot := 0
	var warm := 0
	while not OpeningPrologueFlow.pending() and warm < 100:
		await wait(0.1)
		warm += 1
	while OpeningPrologueFlow.pending() and guard < 400:
		guard += 1
		if director.cutscene.active:
			director.cutscene._skip = true  # 도입·전환 연출은 건너뛴다
		if not director.dialogue.open:
			await wait(0.2)
			continue
		var dlg = director.dialogue
		var id := str(OpeningPrologueFlow.current().get("id", "-"))
		await wait(0.5)
		var i: int = dlg.line_index
		var before: Vector2 = view.world_to_cell(player.global_position)
		dlg._advance()  # 글자 다 보이기
		await wait(0.1)
		dlg._advance()  # 다음 줄(걷기 동작이 있으면 대사창이 숨겨진다)
		await wait(0.7)
		var hidden: bool = not dlg.root.visible and dlg.open
		var mid: Vector2 = view.world_to_cell(player.global_position)
		if hidden:
			shot += 1
			await snap(dir, "walk_%02d_%s_l%d" % [shot, id, i])
		while hidden and not dlg.root.visible and dlg.open:
			await wait(0.2)
		print("%s line %d: 시작 %s → 걷는 중 %s (대사창 숨김=%s) → 끝 %s" % [id, i, before.snapped(Vector2(0.1, 0.1)), mid.snapped(Vector2(0.1, 0.1)), hidden, view.world_to_cell(player.global_position).snapped(Vector2(0.1, 0.1))])
	await snap(dir, "end")
	print("prologue pending=", OpeningPrologueFlow.pending(), " guard=", guard)
	get_tree().quit()
