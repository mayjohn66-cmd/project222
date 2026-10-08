extends Node
## 대화창 초상화 모양 확인: 주인공 표정 2종 + 타블렌(표정 있음) + 코르빈(기본만)을 화면으로 저장한다.
## 사용: godot --path . res://dev/spike3d/dialogue_portrait_shot.tscn -- <저장 폴더>   (xvfb 등 화면 필요)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
var _dir: String = "/tmp/dlg_shot"
func snap(name: String) -> void:
	for i in range(3): await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: _dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	GameState.initialize_new_game()
	PlayerProgress.player_name = "테스터"
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(30): await get_tree().process_frame
	var d: TutorialDirector = world.get_node("TutorialDirector")
	var dlg = d.dialogue
	var cases := [
		["나", ["{놀람}방금 무슨 소리였지. 지진이라도 난 건가?"], "p_surprised"],
		["나", ["*{피곤}눈꺼풀이 무겁다. 아주 잠깐만 눈을 붙여야지."], "p_narration"],
		["행상인 타블렌", ["{놀람}이렇게 맑은 판으로 문을 만들었다고? 안의 먹을 것까지 훤하네."], "n_naru_surprised"],
		["코르빈", ["{걱정}진열대 다리가 흔들려서 받침을 괴었어."], "n_doyun_fallback"],
	]
	for c in cases:
		var lines: Array[String] = []
		lines.assign(c[1])
		dlg.start(c[0], null, lines)
		dlg.text_label.visible_ratio = 1.0
		await snap(c[2])
		dlg.close()
	print("saved to ", _dir)
	get_tree().quit()
