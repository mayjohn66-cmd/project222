@tool
extends EditorExportPlugin
func _get_name() -> String: return "Project222RuntimeCSV"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	add_csv_files("res://data")
func add_csv_files(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file in directory.get_files():
		if file.ends_with(".csv"):
			var source := path.path_join(file)
			add_file(source,FileAccess.get_file_as_bytes(source),false)
	for child in directory.get_directories(): add_csv_files(path.path_join(child))
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# CSV는 원본만 한 번 넣는다. Godot의 번역용 대체 산출물은 런타임에서 쓰지 않는다.
	if path.begins_with("res://data/") and path.ends_with(".csv"): skip()
