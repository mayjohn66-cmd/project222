@tool
extends RefCounted

const ACTIONS := ["create", "rename", "reparent", "delete", "instantiate"]
const KNOWN_ARGUMENTS := ["action", "parent_id", "name", "node_type", "target_id", "new_parent_id", "asset_path"]
const UNUSED_ARGUMENTS := {
	"create": ["target_id", "new_parent_id", "asset_path"],
	"rename": ["parent_id", "node_type", "new_parent_id", "asset_path"],
	"reparent": ["parent_id", "name", "node_type", "asset_path"],
	"delete": ["parent_id", "name", "node_type", "new_parent_id", "asset_path"],
	"instantiate": ["target_id", "new_parent_id", "node_type"],
}
const MIN_NAME_LENGTH := 1
const MAX_NAME_LENGTH := 128
# Tier-5: the curated portable types create accepts. The wire value is never
# handed to the engine; this table is the only path from a requested node_type
# to an engine class, so raw engine class names are rejected with the rest.
const NODE_TYPE_CLASSES := {
	"object": "Node",
	"camera": "Camera3D",
	"light_point": "OmniLight3D",
	"light_directional": "DirectionalLight3D",
}

var _play_mode_tool = null


func _init(play_mode_tool = null) -> void:
	_play_mode_tool = play_mode_tool


func descriptor() -> Dictionary:
	return {
		"name": "mutate_scene",
		"description": "Create, instantiate a prefab, rename, reparent, or delete a single object in the currently edited scene.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"action": {
					"type": "string",
					"description": "Structural edit to perform.",
					"enum": ["create", "rename", "reparent", "delete", "instantiate"],
				},
				"parent_id": {
					"type": "string",
					"description": "For create and instantiate: opaque ID of the parent object. Empty places the object at the scene root.",
					"default": "",
				},
				"name": {
					"type": "string",
					"description": "For create and rename: the object name. For instantiate: optional override of the instance root name. 1 to 128 characters, not whitespace-only, no control characters.",
					"default": "",
				},
				"node_type": {
					"type": "string",
					"description": "For create: the kind of object to create. Engine-neutral names only; use execute_script for arbitrary engine classes.",
					"enum": ["object", "camera", "light_point", "light_directional"],
					"default": "object",
				},
				"target_id": {
					"type": "string",
					"description": "For rename, reparent, and delete: opaque ID of the object to modify.",
					"default": "",
				},
				"new_parent_id": {
					"type": "string",
					"description": "For reparent: opaque ID of the new parent. Empty moves the object to the scene root.",
					"default": "",
				},
				"asset_path": {
					"type": "string",
					"description": "For instantiate: project-relative path of the asset to instantiate. Unity accepts Assets/....prefab; Godot accepts res://....tscn or res://....scn.",
					"default": "",
				},
			},
			"required": ["action"],
			"additionalProperties": false,
		},
		"annotations": {
			"title": "Mutate scene",
			"readOnlyHint": false,
			"destructiveHint": true,
			"idempotentHint": false,
			"openWorldHint": false,
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	# Contract section 6 fixes the validation order so a caller with several
	# problems always sees the same one first: play-mode and scene guards, then
	# action, then per-action arguments, then name, then IDs, then the cycle check.
	if EditorInterface.is_playing_scene() or (
		_play_mode_tool != null and bool(_play_mode_tool.is_transitioning())
	):
		return _error(
			"play_mode_active",
			"Scene mutation is unavailable while play mode is active or transitioning.",
		)

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _error("no_edited_scene", "There is no currently edited scene.")

	var action_value: Variant = arguments.get("action", null)
	if typeof(action_value) != TYPE_STRING or str(action_value) not in ACTIONS:
		return _error(
			"invalid_argument",
			"Unknown action '%s'. Expected one of: create, rename, reparent, delete, instantiate." % str(action_value),
		)
	var action := str(action_value)

	for raw_key: Variant in arguments.keys():
		var key := str(raw_key)
		if key not in KNOWN_ARGUMENTS:
			return _error("invalid_argument", "Unknown argument '%s'." % key)
	for known_key: String in KNOWN_ARGUMENTS:
		if _is_present(arguments, known_key) and typeof(arguments[known_key]) != TYPE_STRING:
			return _error("invalid_argument", "%s must be a string." % known_key)

	# Contract section 3: an argument the chosen action does not use is an error,
	# never a silent ignore. An explicit empty string and the default node_type
	# "object" carry no information, so they are treated as omitted even where
	# the argument itself is unused. This matches the Unity bridge, whose
	# dispatcher cannot distinguish them from omitted values.
	for unused_key: String in UNUSED_ARGUMENTS[action]:
		if not _is_present(arguments, unused_key):
			continue
		var unused_value := str(arguments[unused_key])
		if unused_value.is_empty():
			continue
		if unused_key == "node_type" and unused_value == "object":
			continue
		return _error(
			"invalid_argument",
			"Argument '%s' is not used by action '%s'; omit it." % [unused_key, action],
		)

	match action:
		"create":
			return _create(scene_root, arguments)
		"rename":
			return _rename(scene_root, arguments)
		"reparent":
			return _reparent(scene_root, arguments)
		"instantiate":
			return _instantiate(scene_root, arguments)
		_:
			return _delete(scene_root, arguments)


func _create(scene_root: Node, arguments: Dictionary) -> Dictionary:
	var node_type := _string_argument(arguments, "node_type")
	if node_type.is_empty():
		node_type = "object"
	if node_type not in NODE_TYPE_CLASSES:
		return _error(
			"invalid_argument",
			"Unknown node_type '%s'. Expected one of: object, camera, light_point, light_directional." % str(arguments["node_type"]),
		)
	if not _is_present(arguments, "name"):
		return _error("invalid_argument", "Argument 'name' is required for action 'create'.")
	var node_name := str(arguments["name"])
	var name_error := _validate_name(node_name)
	if not name_error.is_empty():
		return name_error

	var parent := scene_root
	var parent_id := _string_argument(arguments, "parent_id")
	if not parent_id.is_empty():
		parent = _resolve_scene_node(parent_id, scene_root)
		if parent == null:
			return _error(
				"invalid_parent_id",
				"parent_id '%s' does not identify a live node in the currently edited scene." % parent_id,
			)

	var node := ClassDB.instantiate(NODE_TYPE_CLASSES[node_type]) as Node
	node.set_name(node_name)
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy create node")
	undo_redo.add_do_method(parent, "add_child", node, true)
	undo_redo.add_do_method(node, "set_owner", scene_root)
	undo_redo.add_undo_method(parent, "remove_child", node)
	undo_redo.add_do_reference(node)
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	# The create result echoes the curated node_type the caller asked for, next
	# to the node payload whose type field carries the mapped engine class.
	return _node_result("create", true, scene_root, node, {"node_type": node_type})


func _rename(scene_root: Node, arguments: Dictionary) -> Dictionary:
	var target_id := _string_argument(arguments, "target_id")
	if target_id.is_empty():
		return _error("invalid_argument", "Argument 'target_id' is required for action 'rename'.")
	if not _is_present(arguments, "name"):
		return _error("invalid_argument", "Argument 'name' is required for action 'rename'.")
	var node_name := str(arguments["name"])
	var name_error := _validate_name(node_name)
	if not name_error.is_empty():
		return name_error

	var target := _resolve_scene_node(target_id, scene_root)
	if target == null:
		return _error(
			"invalid_target_id",
			"target_id '%s' does not identify a live node in the currently edited scene." % target_id,
		)

	var previous_name := str(target.name)
	if previous_name == node_name:
		# Contract section 5.1: a no-op still succeeds, but performs no edit,
		# records no undo step, and does not dirty the scene.
		return _node_result("rename", false, scene_root, target, {"previous_name": previous_name})

	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy rename node")
	undo_redo.add_do_method(target, "set_name", node_name)
	undo_redo.add_undo_method(target, "set_name", previous_name)
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	return _node_result("rename", true, scene_root, target, {"previous_name": previous_name})


func _reparent(scene_root: Node, arguments: Dictionary) -> Dictionary:
	var target_id := _string_argument(arguments, "target_id")
	if target_id.is_empty():
		return _error("invalid_argument", "Argument 'target_id' is required for action 'reparent'.")

	var target := _resolve_scene_node(target_id, scene_root)
	if target == null:
		return _error(
			"invalid_target_id",
			"target_id '%s' does not identify a live node in the currently edited scene." % target_id,
		)
	if target == scene_root:
		return _error(
			"invalid_target_id",
			"target_id identifies the edited scene root, which cannot be reparented.",
		)

	var new_parent := scene_root
	var new_parent_id := _string_argument(arguments, "new_parent_id")
	if not new_parent_id.is_empty():
		new_parent = _resolve_scene_node(new_parent_id, scene_root)
		if new_parent == null:
			return _error(
				"invalid_parent_id",
				"new_parent_id '%s' does not identify a live node in the currently edited scene." % new_parent_id,
			)
		if new_parent == target:
			return _error(
				"invalid_reparent",
				"new_parent_id identifies target_id itself; an object cannot be its own parent.",
			)
		if target.is_ancestor_of(new_parent):
			return _error(
				"invalid_reparent",
				"new_parent_id identifies a descendant of target_id; reparenting there would create a cycle.",
			)

	var old_parent := target.get_parent()
	var previous_parent_id := _node_id(old_parent) if old_parent != null else ""
	if new_parent == old_parent:
		return _node_result("reparent", false, scene_root, target, {"previous_parent_id": previous_parent_id})

	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy reparent node")
	undo_redo.add_do_method(target, "reparent", new_parent)
	undo_redo.add_undo_method(target, "reparent", old_parent)
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	# reparent() preserves the owner within the same scene, so the node stays saved.
	return _node_result("reparent", true, scene_root, target, {"previous_parent_id": previous_parent_id})


func _delete(scene_root: Node, arguments: Dictionary) -> Dictionary:
	var target_id := _string_argument(arguments, "target_id")
	if target_id.is_empty():
		return _error("invalid_argument", "Argument 'target_id' is required for action 'delete'.")

	var target := _resolve_scene_node(target_id, scene_root)
	if target == null:
		return _error(
			"invalid_target_id",
			"target_id '%s' does not identify a live node in the currently edited scene." % target_id,
		)
	if target == scene_root:
		return _error(
			"invalid_target_id",
			"target_id identifies the edited scene root, which cannot be deleted.",
		)

	# Contract section 5.2: deleted describes the object as it was immediately
	# before the edit, so everything is captured before any editor call.
	var deleted := _describe_node(target, scene_root)
	var parent := target.get_parent()
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy delete node")
	undo_redo.add_do_method(parent, "remove_child", target)
	undo_redo.add_undo_method(parent, "add_child", target)
	undo_redo.add_undo_method(target, "set_owner", scene_root)
	# The node is never freed: the do-reference keeps it alive so undo restores it.
	undo_redo.add_do_reference(target)
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	return {
		"success": true,
		"engine": "godot",
		"action": "delete",
		"changed": true,
		"scene": _scene_summary(scene_root),
		"deleted": deleted,
		"verify_with": {
			"tool": "inspect_scene",
			"arguments": {"root_id": "", "max_depth": 3},
		},
	}


func _instantiate(scene_root: Node, arguments: Dictionary) -> Dictionary:
	var asset_path := _string_argument(arguments, "asset_path")
	if asset_path.is_empty():
		return _error("invalid_argument", "Argument 'asset_path' is required for action 'instantiate'.")
	# Contract section 3: backslashes are normalized before validation so a
	# Windows caller is not punished for a path separator; no other rewriting
	# occurs, and the normalized path is the one echoed back in the result.
	asset_path = asset_path.replace("\\", "/")
	# Contract section 6 fixes argument checks before ID resolution, so the
	# asset_path form checks run here. The existence check runs at the load
	# site, after parent resolution, because it must touch the asset database.
	if asset_path.contains(".."):
		return _error("invalid_argument", "asset_path '%s' must not contain '..'." % asset_path)
	if not asset_path.begins_with("res://"):
		return _error("invalid_argument", "asset_path '%s' must be a res:// path inside the project." % asset_path)
	if asset_path.get_extension().to_lower() not in ["tscn", "scn"]:
		return _error("invalid_argument", "asset_path '%s' must end in .tscn or .scn." % asset_path)

	# name is optional for instantiate: an explicit empty string is omitted, so
	# the instantiated root keeps the asset's own root name (contract section 3).
	var node_name := _string_argument(arguments, "name")
	if not node_name.is_empty():
		var name_error := _validate_name(node_name)
		if not name_error.is_empty():
			return name_error

	var parent := scene_root
	var parent_id := _string_argument(arguments, "parent_id")
	if not parent_id.is_empty():
		parent = _resolve_scene_node(parent_id, scene_root)
		if parent == null:
			return _error(
				"invalid_parent_id",
				"parent_id '%s' does not identify a live node in the currently edited scene." % parent_id,
			)

	if not ResourceLoader.exists(asset_path):
		return _error(
			"asset_not_found",
			"asset_path '%s' does not identify a loadable resource." % asset_path,
		)
	var packed_scene := ResourceLoader.load(asset_path) as PackedScene
	if packed_scene == null:
		return _error(
			"asset_not_found",
			"asset_path '%s' could not be loaded as a PackedScene." % asset_path,
		)

	# Children of the instantiated scene keep their ownership from the packed
	# scene, so only the instance root is re-owned to the edited scene root.
	var instance_root := packed_scene.instantiate()
	if instance_root == null:
		return _error(
			"editor_api_failure",
			"PackedScene.instantiate() returned no node for asset_path '%s'." % asset_path,
		)
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy instantiate scene")
	undo_redo.add_do_method(parent, "add_child", instance_root, true)
	undo_redo.add_do_method(instance_root, "set_owner", scene_root)
	undo_redo.add_undo_method(parent, "remove_child", instance_root)
	undo_redo.add_do_reference(instance_root)
	if not node_name.is_empty():
		# The rename rides inside the same undo action, after add_child: the
		# requested name is applied verbatim and undo removes the whole instance.
		undo_redo.add_do_method(instance_root, "set_name", node_name)
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	return _node_result("instantiate", true, scene_root, instance_root, {"asset_path": asset_path})


func _node_result(
	action: String,
	changed: bool,
	scene_root: Node,
	node: Node,
	extra: Dictionary = {},
) -> Dictionary:
	var node_id := _node_id(node)
	var result := {
		"success": true,
		"engine": "godot",
		"action": action,
		"changed": changed,
		"scene": _scene_summary(scene_root),
		"node": _describe_node(node, scene_root),
		"verify_with": {
			"tool": "inspect_scene",
			"arguments": {"root_id": node_id, "max_depth": 1},
		},
	}
	for extra_key: Variant in extra.keys():
		result[extra_key] = extra[extra_key]
	return result


func _scene_summary(scene_root: Node) -> Dictionary:
	return {
		"name": str(scene_root.name),
		"path": scene_root.scene_file_path,
		"saved": not scene_root.scene_file_path.is_empty(),
	}


# Same field set as an inspect_scene node minus depth, which is a
# traversal-relative concept with no meaning for a single edited object.
func _describe_node(node: Node, scene_root: Node) -> Dictionary:
	var parent_id := ""
	if node != scene_root:
		var parent := node.get_parent()
		if parent != null and (parent == scene_root or scene_root.is_ancestor_of(parent)):
			parent_id = _node_id(parent)
	return {
		"id": _node_id(node),
		"parent_id": parent_id,
		"name": str(node.name),
		"path": _display_path(node, scene_root),
		"type": node.get_class(),
		"child_count": node.get_child_count(),
	}


# Contract section 3 name rules. Returns an empty dictionary when the name is
# valid; the name is otherwise used verbatim and never trimmed.
func _validate_name(node_name: String) -> Dictionary:
	if node_name.length() < MIN_NAME_LENGTH or node_name.length() > MAX_NAME_LENGTH:
		return _error(
			"invalid_argument",
			"name must be between 1 and 128 characters; received %d." % node_name.length(),
		)
	if node_name.strip_edges().is_empty():
		return _error("invalid_argument", "name must not be whitespace only.")
	for index: int in range(node_name.length()):
		var code := node_name.unicode_at(index)
		if code <= 31 or (code >= 127 and code <= 159):
			return _error(
				"invalid_argument",
				"name must not contain control characters (found one at index %d)." % index,
			)
	return {}


# Contract section 4.1: liveness is validated at resolution time. A deleted or
# undone node fails the ancestor check and is reported as stale; the emitted-ID
# set is never wholesale-invalidated when the hierarchy changes.
func _resolve_scene_node(opaque_id: String, scene_root: Node) -> Node:
	if not opaque_id.begins_with("godot:"):
		return null
	var raw_instance_id := opaque_id.trim_prefix("godot:")
	if not raw_instance_id.is_valid_int():
		return null
	var candidate := instance_from_id(raw_instance_id.to_int()) as Node
	if candidate == null:
		return null
	if candidate != scene_root and not scene_root.is_ancestor_of(candidate):
		return null
	return candidate


func _is_present(arguments: Dictionary, key: String) -> bool:
	# Absent means omitted or JSON null. An explicit empty string still counts
	# as present here so required arguments reject it; optional/unused arguments
	# apply their own empty-string tolerance at the use site (contract section 3).
	return arguments.has(key) and arguments[key] != null


func _string_argument(arguments: Dictionary, key: String) -> String:
	if not _is_present(arguments, key):
		return ""
	return str(arguments[key])


func _node_id(node: Node) -> String:
	return "godot:%d" % node.get_instance_id()


func _display_path(node: Node, scene_root: Node) -> String:
	if node == scene_root:
		return "/" + str(scene_root.name)
	return "/%s/%s" % [scene_root.name, scene_root.get_path_to(node)]


func _error(code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"engine": "godot",
		"error_code": code,
		"error": message,
	}
