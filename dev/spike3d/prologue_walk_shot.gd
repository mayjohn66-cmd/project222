extends Node
## 프롤로그 전체 확인: 도입(손님 장면)→독백 줄마다 화면 저장·로그→졸음→깨어남→잔해 정리까지 끝까지 진행한다.
## 줄이 다 보이면 0.3초 뒤에 저장하고 다음 줄로 넘긴다. 저장 위치: <저장 폴더>/p_01.png …  (xvfb 등 화면 필요)
## 사용: godot --path . res://dev/spike3d/prologue_walk_shot.tscn -- <저장 폴더>
## 화면 없는 환경은 프레임이 느려(4fps 안팎) 연출 시간이 실제보다 길게 나온다. 시간은 PC에서 확인한다.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func snap(name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])
var _dir: String = "/tmp/prologue_flow"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	var d: TutorialDirector = world.get_node("TutorialDirector")
	var dlg = d.dialogue
	var shot := 0
	var last := ""
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while frames < 6000 and (frames < 120 or OpeningPrologueFlow.pending() or dlg.open):
		await get_tree().process_frame
		frames += 1
		var key := "%s|%d|%s" % [dlg.lines[0] if dlg.lines.size() > 0 else "-", dlg.line_index, dlg.root.visible]
		if dlg.open and key != last:
			last = key
			print("[%.1fs] open=%s visible=%s idx=%d line=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, dlg.open, dlg.root.visible, dlg.line_index, dlg.lines[dlg.line_index]])
		if dlg.open and dlg.root.visible and dlg.text_label.visible_ratio >= 1.0 and not dlg._beat_busy:
			shot += 1
			await snap("p_%02d" % shot)
			await get_tree().create_timer(0.3, true, false, true).timeout
			dlg._advance()
	print("done frames=", frames, " pending=", OpeningPrologueFlow.pending())
	get_tree().quit()
