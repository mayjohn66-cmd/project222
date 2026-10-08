@tool
extends RefCounted

const DEFAULT_LIMIT := 200
const MAX_LIMIT := 5000


func descriptor() -> Dictionary:
	return {
		"name": "manage_asset",
		"description": "List/search, import, refresh, move, or permanently delete Godot project assets.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"action": {
					"type": "string",
					"enum": ["list", "search", "import", "refresh", "move", "delete"],
				},
				"path": {
					"type": "string",
					"description": "Source file/directory under res:// (defaults to res:// for reads).",
				},
				"destination": {
					"type": "string",
					"description": "Destination res:// path for move; it must not already exist.",
				},
				"query": {"type": "string", "description": "Case-insensitive path filter for search."},
				"recursive": {
					"type": "boolean",
					"default": false,
					"description": "Recurse while listing, or permit recursive directory deletion.",
				},
				"limit": {
					"type": "integer",
					"minimum": 1,
					"maximum": MAX_LIMIT,
					"default": DEFAULT_LIMIT,
				},
			},
			"required": ["action"],
			"additionalProperties": false,
		},
		"annotations": {
			"readOnlyHint": false,
			"destructiveHint": true,
			"idempotentHint": false,
			"openWorldHint": false,
			"readOnlyActions": ["list", "search"],
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	var action: String = str(arguments.get("action", ""))
	match action:
		"list":
			return _list_assets(arguments, false)
		"search":
			return _list_assets(arguments, true)
		"import":
			return _import_asset(arguments)
		"refresh":
			return _refresh_assets(arguments)
		"move":
			return _move_asset(arguments)
		"delete":
			return _delete_asset(arguments)
		_:
			return {"success": false, "error": "action must be list, search, import, refresh, move, or delete"}


func _list_assets(arguments: Dictionary, search: bool) -> Dictionary:
	var path: String = _normalize_res_path(arguments.get("path", "res://"))
	if path.is_empty():
		return _invalid_path_error("path")

	var editor_filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	var directory: EditorFileSystemDirectory = (
		editor_filesystem.get_filesystem()
		if path == "res://"
		else editor_filesystem.get_filesystem_path(path)
	)
	if directory == null:
		return {"success": false, "error": "path is not an indexed project directory", "path": path}

	var limit: int = clampi(int(arguments.get("limit", DEFAULT_LIMIT)), 1, MAX_LIMIT)
	var query: String = str(arguments.get("query", "")).to_lower() if search else ""
	var recursive: bool = true if search else bool(arguments.get("recursive", false))
	var results: Array = []
	_collect_directory(directory, query, recursive, limit, results)

	return {
		"success": true,
		"action": "search" if search else "list",
		"path": path,
		"query": query,
		"recursive": recursive,
		"items": results,
		"count": results.size(),
		"limit": limit,
		"possibly_truncated": results.size() >= limit,
		"filesystem_scanning": editor_filesystem.is_scanning(),
	}


func _collect_directory(
	directory: EditorFileSystemDirectory,
	query: String,
	recursive: bool,
	limit: int,
	results: Array,
) -> void:
	for file_index: int in range(directory.get_file_count()):
		if results.size() >= limit:
			return
		var file_path: String = directory.get_file_path(file_index)
		if query.is_empty() or file_path.to_lower().contains(query):
			results.append({
				"kind": "file",
				"name": directory.get_file(file_index),
				"path": file_path,
				"resource_type": str(directory.get_file_type(file_index)),
				"import_valid": directory.get_file_import_is_valid(file_index),
			})

	for subdir_index: int in range(directory.get_subdir_count()):
		if results.size() >= limit:
			return
		var subdirectory: EditorFileSystemDirectory = directory.get_subdir(subdir_index)
		var subdirectory_path: String = subdirectory.get_path()
		if query.is_empty() or subdirectory_path.to_lower().contains(query):
			results.append({
				"kind": "directory",
				"name": subdirectory.get_name(),
				"path": subdirectory_path,
			})
		if recursive:
			_collect_directory(subdirectory, query, true, limit, results)


func _import_asset(arguments: Dictionary) -> Dictionary:
	var path: String = _normalize_res_path(arguments.get("path", ""))
	if path.is_empty() or path == "res://":
		return _invalid_path_error("path")
	if not FileAccess.file_exists(path):
		return {"success": false, "error": "import path must be an existing file", "path": path}

	var editor_filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if editor_filesystem.is_scanning():
		return {"success": false, "error": "EditorFileSystem is already scanning; retry after it completes"}

	var known_type: String = editor_filesystem.get_file_type(path)
	editor_filesystem.update_file(path)
	if known_type.is_empty():
		editor_filesystem.scan()
		return {
			"success": true,
			"path": path,
			"import_completed": false,
			"scan_started": true,
			"note": "New files are discovered asynchronously by EditorFileSystem.scan().",
		}

	editor_filesystem.reimport_files(PackedStringArray([path]))
	return {
		"success": true,
		"path": path,
		"import_completed": true,
		"scan_started": false,
	}


func _refresh_assets(arguments: Dictionary) -> Dictionary:
	var editor_filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if editor_filesystem.is_scanning():
		return {
			"success": true,
			"scan_started": false,
			"already_scanning": true,
			"progress": editor_filesystem.get_scanning_progress(),
		}

	var raw_path: String = str(arguments.get("path", "")).strip_edges()
	if not raw_path.is_empty():
		var path: String = _normalize_res_path(raw_path)
		if path.is_empty():
			return _invalid_path_error("path")
		if FileAccess.file_exists(path):
			editor_filesystem.update_file(path)

	editor_filesystem.scan_sources()
	editor_filesystem.scan()
	return {
		"success": true,
		"scan_started": true,
		"completed": false,
		"note": "EditorFileSystem.scan() is asynchronous.",
	}


func _move_asset(arguments: Dictionary) -> Dictionary:
	var source: String = _normalize_res_path(arguments.get("path", ""))
	var destination: String = _normalize_res_path(arguments.get("destination", ""))
	if not _mutation_path_allowed(source):
		return _invalid_path_error("path")
	if not _mutation_path_allowed(destination):
		return _invalid_path_error("destination")
	if not _path_exists(source):
		return {"success": false, "error": "source does not exist", "path": source}
	if _path_exists(destination):
		return {"success": false, "error": "destination already exists; overwrite is intentionally disabled", "destination": destination}

	var parent_error: Error = DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if parent_error != OK and not DirAccess.dir_exists_absolute(destination.get_base_dir()):
		return {"success": false, "error": "could not create destination directory", "error_code": parent_error}

	var move_error: Error = DirAccess.rename_absolute(source, destination)
	if move_error != OK:
		return {"success": false, "error": "filesystem move failed", "error_code": move_error}

	EditorInterface.get_resource_filesystem().scan()
	return {
		"success": true,
		"source": source,
		"destination": destination,
		"scan_started": true,
		"warning": "Godot resource references and UID companion files may require manual repair after a raw filesystem move.",
	}


func _delete_asset(arguments: Dictionary) -> Dictionary:
	var path: String = _normalize_res_path(arguments.get("path", ""))
	if not _mutation_path_allowed(path):
		return _invalid_path_error("path")
	if not _path_exists(path):
		return {"success": false, "error": "path does not exist", "path": path}

	var recursive: bool = bool(arguments.get("recursive", false))
	var delete_error: Error
	if DirAccess.dir_exists_absolute(path) and recursive:
		delete_error = _remove_tree(path)
	else:
		delete_error = DirAccess.remove_absolute(path)
	if delete_error != OK:
		return {
			"success": false,
			"error": "filesystem delete failed; non-empty directories require recursive=true",
			"error_code": delete_error,
		}

	EditorInterface.get_resource_filesystem().scan()
	return {
		"success": true,
		"path": path,
		"recursive": recursive,
		"scan_started": true,
		"warning": "Deletion is permanent and does not use the operating-system trash.",
	}


func _remove_tree(path: String) -> Error:
	if _is_link(path):
		return DirAccess.remove_absolute(path)

	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	directory.include_hidden = true

	for file_name: String in directory.get_files():
		var file_error: Error = DirAccess.remove_absolute(path.path_join(file_name))
		if file_error != OK:
			return file_error
	for subdirectory_name: String in directory.get_directories():
		var subdirectory_error: Error = _remove_tree(path.path_join(subdirectory_name))
		if subdirectory_error != OK:
			return subdirectory_error
	return DirAccess.remove_absolute(path)


func _is_link(path: String) -> bool:
	var parent: DirAccess = DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())


func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func _mutation_path_allowed(path: String) -> bool:
	return (
		not path.is_empty()
		and path != "res://"
		and path != "res://.godot"
		and not path.begins_with("res://.godot/")
	)


func _normalize_res_path(value: Variant) -> String:
	var path: String = str(value).strip_edges().replace("\\", "/")
	if path.is_empty():
		return "res://"
	if path.contains("\u0000"):
		return ""
	if path.contains("://") and not path.begins_with("res://"):
		return ""
	if not path.begins_with("res://"):
		while path.begins_with("/"):
			path = path.substr(1)
		path = "res://" + path

	var normalized_segments := PackedStringArray()
	for segment: String in path.substr(6).split("/", false):
		if segment == ".":
			continue
		if segment == ".." or segment.contains(":"):
			return ""
		normalized_segments.append(segment)
	return "res://" + "/".join(normalized_segments)


func _invalid_path_error(field: String) -> Dictionary:
	return {
		"success": false,
		"error": "%s must resolve inside res:// and may not target the project root or .godot" % field,
	}
