extends Node
## 새 게임 프롤로그 연출 확인: 도입(검은 화면→도시)→독백→전환(깜빡임·다가가기·번쩍)→숲→마무리 화면을 시간 간격으로 저장한다.
## 사용: godot --path . res://dev/spike3d/prologue_shot.tscn -- <저장 폴더>   (헤드리스에서는 연출이 꺼지므로 xvfb 등 화면이 있어야 한다)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func snap(dir: String, name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("SNAP ", name)

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func state(director: TutorialDirector) -> String:
	return "moment=%s phase=%s active=%s talking=%s dlg=%s line=%d zoom=%.2f" % [OpeningPrologueFlow.current().get("id", "-"), director.cutscene._phase, director.cutscene.active, director.talking, director.dialogue.open, director.dialogue.line_index, director.cutscene.camera2d.zoom.x if director.cutscene.camera2d != null else 0.0]

# 대사가 열려 있으면 끝까지 읽는다(한 줄에 두 번: 글자 다 보이기 → 다음 줄).
func read_all(director: TutorialDirector) -> void:
	var guard := 0
	while director.dialogue.open and guard < 40:
		director.dialogue._advance()
		await wait(0.08)
		guard += 1

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "/tmp/prologue_shot"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	var director: TutorialDirector = world.get_node("TutorialDirector")
	var skip_mode: bool = args.size() > 1 and args[1] == "skip"
	var shots := {"a_black": 0.6, "b_fade": 1.8, "c_city": 4.0, "c_city2": 5.6}
	var t := 0.0
	var order := shots.keys()
	var i := 0
	# 도입이 끝나 독백 1이 열릴 때까지(최대 14초) 일정한 간격으로 찍는다
	while t < 14.0 and not director.dialogue.open:
		await wait(0.2)
		t += 0.2
		if skip_mode and t > 1.0:
			director.cutscene._skip = true
		if i < order.size() and t >= float(shots[order[i]]):
			await snap(dir, str(order[i]))
			i += 1
	print("T=%.1f " % t, state(director), " skip_mode=", skip_mode)
	await wait(1.0)
	await snap(dir, "d_monologue1")
	await read_all(director)
	print("after monologue1 ", state(director))
	# 전환 연출: 0.4초 간격으로 찍는다
	var k := 0
	while not director.dialogue.open and k < 40:
		await wait(0.4)
		k += 1
		if skip_mode:
			director.cutscene._skip = true
		if k in [1, 3, 5, 8, 10, 12, 14, 16]:
			await snap(dir, "t_%02d" % k)
			print("t_%02d " % k, state(director))
	print("transition done k=", k, " ", state(director))
	await wait(1.0)
	await snap(dir, "j_forest")
	await read_all(director)
	await wait(0.6)
	await snap(dir, "k_outro_start")
	await wait(2.4)
	await snap(dir, "l_outro_end")
	print("end ", state(director))
	get_tree().quit()
