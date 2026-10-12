extends Node
## 별도 release QA 빌드에서 생산용 파일 목록·데이터·시작 흐름을 검사한다. 배포 PCK에는 넣지 않는다.
var checks := 0
var failures := 0
var report := {}

func _ready() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frames(count: int = 10) -> void:
	for i in count: await get_tree().process_frame
func collect(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null: return result
	for file in directory.get_files(): result.append(path.path_join(file))
	for child in directory.get_directories(): result.append_array(collect(path.path_join(child)))
	return result
func paths(value, found: Dictionary) -> void:
	if value is String and value.begins_with("res://art/"): found[value] = true
	elif value is Dictionary:
		for key in value:
			# aliases는 옛 경로를 현재 그림으로 찾는 식별 키이며 로드할 파일이 아니다.
			if str(key) != "aliases": paths(value[key],found)
	elif value is Array:
		for child in value: paths(child,found)
func run() -> void:
	var tree := get_tree()
	if OS.has_feature("editor"):
		print("SKIP_WINDOWS_RELEASE: use a separate native release QA build")
		tree.quit(0)
		return
	var root := tree.root
	var zip := ZIPReader.new()
	var zip_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--production-zip="): zip_path=arg.trim_prefix("--production-zip=")
	check(zip.open(zip_path)==OK,"production export archive opens")
	var shipped := zip.get_files()
	check(not OS.has_feature("editor"),"uses export template, not editor")
	check(OS.has_feature("release"),"uses release template")
	check(OS.get_user_data_dir().contains("release_checks"),"isolated release test saves")
	for folder in ["res://dev","res://docs","res://tools","res://addons"]:
		var prefix: String = folder.trim_prefix("res://")+"/"
		var present := false
		for file in shipped:
			if file.begins_with(prefix): present = true
		check(not present,"development files excluded from production: "+folder)
	var data_files := collect("res://data")
	var csv_count := 0
	var json_count := 0
	var artwork: Dictionary = {}
	for path in data_files:
		if path.ends_with(".csv"):
			csv_count += 1
			check(not FileAccess.get_file_as_string(path).is_empty(),"raw CSV readable: "+path)
			check(FileAccess.get_file_as_bytes(path)==zip.read_file(path.trim_prefix("res://")),"production raw CSV bytes match native QA: "+path)
		elif path.ends_with(".json"):
			json_count += 1
			var value = JSON.parse_string(FileAccess.get_file_as_string(path))
			check(value != null,"JSON readable: "+path)
			paths(value,artwork)
	for path in artwork: check(ResourceLoader.exists(path),"manifest art exported: "+str(path))
	check(csv_count>30 and json_count>10,"raw game data actually packed")
	check(ResourceLoader.exists("res://scenes/core/title/title_screen.tscn"),"title scene exported")
	tree.current_scene = null # Keep the runner while exercising real scene transitions.
	tree.change_scene_to_file("res://scenes/core/title/title_screen.tscn")
	await frames(15)
	var title = tree.current_scene
	check(title != null and title.new_game_button.visible,"real title opens")
	title.new_game_button.pressed.emit()
	if title.new_game_dialog.visible:
		title.new_game_dialog.hide()
		title.new_game_dialog.confirmed.emit()
	title.nickname_edit.text = "배포점검"
	title.nickname_dialog.confirmed.emit()
	title.nickname_dialog.hide()
	await frames(90)
	var world = tree.current_scene
	check(world != null and world.scene_file_path == "res://scenes/shop/main.tscn","real new game opens shop")
	if world != null and world.scene_file_path == "res://scenes/shop/main.tscn":
		var view = world.get_node("StoreView3D")
		check(view._ready_done and view._actors.size()>0,"actual renderer and player loaded")
		check(is_equal_approx(view.camera2d.zoom.x,1.15),"release play camera")
		var tutorial = world.get_node("TutorialDirector")
		check(tutorial.dialogue.open,"opening dialogue appears")
		check(VillageLifeFlow.friendship_name("naru")=="새 이웃","exported resource default arrays read correctly")
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_F10
		tutorial.layout_editor._unhandled_key_input(key)
		check(not tutorial.layout_editor.active,"F10 cannot edit shipped store")
		key.keycode = KEY_F6
		view._unhandled_key_input(key)
		check(view.season_override.is_empty(),"F6 cannot override release season")
		key.keycode = KEY_F7
		view._unhandled_key_input(key)
		check(view.weather_override.is_empty(),"F7 cannot override release weather")
		var editor = world.find_child("VillageMapEditor",true,false)
		if editor != null:
			key.keycode = KEY_F12
			editor._input(key)
			check(not editor.active,"F12 cannot edit shipped village")
		var samples: Array[float] = []
		for i in 120:
			await tree.process_frame
			samples.append(root.get_process_delta_time()*1000.0)
		samples.sort()
		report["frame_ms_median"] = samples[samples.size()/2]
		report["frame_ms_p95"] = samples[int(samples.size()*0.95)]
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--snap=") and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(arg.trim_prefix("--snap="))==OK,"release screen captured")
	report.merge({"checks":checks,"failures":failures,"csv_files":csv_count,"json_files":json_count,"manifest_art_paths":artwork.size(),"engine":Engine.get_version_info().string,"editor":OS.has_feature("editor")})
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report,"  "))
	print("CHECK_WINDOWS_RELEASE ",JSON.stringify(report))
	zip.close()
	tree.quit(1 if failures else 0)
