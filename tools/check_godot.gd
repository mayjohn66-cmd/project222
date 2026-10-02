extends Node

# 프로젝트의 모든 .gd 스크립트와 .tscn 씬을 불러와서 파싱·로드 오류를 찾는다.
# 실행: godot --headless --path . res://tools/check_godot.tscn
# (--script 방식은 자동 로드(GameState 등)가 등록되지 않아 가짜 오류가 나므로 씬으로 실행한다)
# 오류는 Godot 로그(SCRIPT ERROR / ERROR)에 출력되고, 실패한 파일 목록은 마지막에 요약한다.

func _ready() -> void:
	var failed: Array[String] = []
	var total: int = 0

	for path in _collect("res://"):
		total += 1
		var resource = ResourceLoader.load(
			path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		)

		if resource == null:
			failed.append(path)

	print("[검사] 대상 ", total, "개 / 로드 실패 ", failed.size(), "개")

	for path in failed:
		print("[실패] ", path)

	get_tree().quit(1 if not failed.is_empty() else 0)


func _collect(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)

	if dir == null:
		return result

	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue

		result.append_array(
			_collect(dir_path.path_join(sub))
		)

	for file_name in dir.get_files():
		if file_name.begins_with("check_godot."):
			continue

		if file_name.ends_with(".gd") or file_name.ends_with(".tscn"):
			result.append(
				dir_path.path_join(file_name)
			)

	return result
