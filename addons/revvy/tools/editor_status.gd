@tool
extends RefCounted

var _editor_tree: SceneTree


func _init(editor_tree: SceneTree) -> void:
	_editor_tree = editor_tree


func descriptor() -> Dictionary:
	return {
		"name": "editor_status",
		"description": "Report Godot version, project identity, editor play state, scenes, and filesystem scan state.",
		"inputSchema": {
			"type": "object",
			"properties": {},
			"additionalProperties": false,
		},
		"annotations": {
			"readOnlyHint": true,
			"destructiveHint": false,
			"idempotentHint": true,
			"openWorldHint": false,
		},
	}


func invoke(_arguments: Dictionary) -> Dictionary:
	var project_path: String = ProjectSettings.globalize_path("res://")
	while project_path.length() > 1 and (project_path.ends_with("/") or project_path.ends_with("\\")):
		project_path = project_path.substr(0, project_path.length() - 1)

	var project_name: String = str(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
	if project_name.is_empty():
		project_name = project_path.get_file()

	var edited_scene: Dictionary = {"open": false, "name": "", "path": ""}
	var edited_root: Node = EditorInterface.get_edited_scene_root()
	if edited_root != null:
		edited_scene = {
			"open": true,
			"name": edited_root.name,
			"path": edited_root.scene_file_path,
		}

	var open_scenes: Array = []
	for scene_path: String in EditorInterface.get_open_scenes():
		open_scenes.append(scene_path)

	var editor_filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	return {
		"success": true,
		"engine": "godot",
		"engine_version": str(Engine.get_version_info().get("string", "unknown")),
		"project_name": project_name,
		"project_path": project_path,
		"headless": DisplayServer.get_name() == "headless",
		"editor_hint": Engine.is_editor_hint(),
		"editor_scene_tree_available": _editor_tree != null,
		"play_state": {
			"playing": EditorInterface.is_playing_scene(),
			"scene": EditorInterface.get_playing_scene(),
		},
		"edited_scene": edited_scene,
		"open_scenes": open_scenes,
		"filesystem": {
			"scanning": editor_filesystem.is_scanning(),
			"scan_progress": editor_filesystem.get_scanning_progress(),
		},
		"dirty_asset_state": {
			"supported": false,
			"state": "unknown",
			"reason": "Godot 4.5 EditorInterface has no public all-scenes/all-resources dirty-state query.",
		},
	}
