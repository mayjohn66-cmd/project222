@tool
extends RefCounted

const DEFAULT_MAX_DEPTH := 3
const MAX_MAX_DEPTH := 16
const DEFAULT_LIMIT := 200
const MAX_LIMIT := 500
const MAX_OFFSET := 10_000
const ALLOWED_ARGUMENTS := ["root_id", "max_depth", "offset", "limit"]

var _play_mode_tool = null


func _init(play_mode_tool = null) -> void:
	_play_mode_tool = play_mode_tool


func descriptor() -> Dictionary:
	return {
		"name": "inspect_scene",
		"description": "Inspect a bounded portion of the currently edited scene hierarchy without modifying editor state.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"root_id": {
					"type": "string",
					"description": "Opaque node ID returned by an earlier inspect_scene call. Empty starts at all scene roots.",
					"default": "",
				},
				"max_depth": {
					"type": "integer",
					"description": "Maximum descendant depth relative to each traversal root. Depth zero returns only the root objects.",
					"minimum": 0,
					"maximum": MAX_MAX_DEPTH,
					"default": DEFAULT_MAX_DEPTH,
				},
				"offset": {
					"type": "integer",
					"description": "Number of entries to skip in deterministic depth-first pre-order.",
					"minimum": 0,
					"maximum": MAX_OFFSET,
					"default": 0,
				},
				"limit": {
					"type": "integer",
					"description": "Maximum hierarchy entries to return.",
					"minimum": 1,
					"maximum": MAX_LIMIT,
					"default": DEFAULT_LIMIT,
				},
			},
			"additionalProperties": false,
		},
		"annotations": {
			"title": "Inspect scene",
			"readOnlyHint": true,
			"destructiveHint": false,
			"idempotentHint": true,
			"openWorldHint": false,
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	for raw_key: Variant in arguments.keys():
		var key := str(raw_key)
		if key not in ALLOWED_ARGUMENTS:
			return _error("invalid_argument", "Unknown argument '%s'." % key)

	var root_value: Variant = arguments.get("root_id", "")
	if typeof(root_value) != TYPE_STRING:
		return _error("invalid_argument", "root_id must be a string.")
	var root_id := str(root_value).strip_edges()

	var depth_result := _bounded_integer(arguments, "max_depth", DEFAULT_MAX_DEPTH, 0, MAX_MAX_DEPTH)
	if not bool(depth_result.get("success", false)):
		return depth_result
	var offset_result := _bounded_integer(arguments, "offset", 0, 0, MAX_OFFSET)
	if not bool(offset_result.get("success", false)):
		return offset_result
	var limit_result := _bounded_integer(arguments, "limit", DEFAULT_LIMIT, 1, MAX_LIMIT)
	if not bool(limit_result.get("success", false)):
		return limit_result

	if EditorInterface.is_playing_scene() or (
		_play_mode_tool != null and bool(_play_mode_tool.is_transitioning())
	):
		return _error("play_mode_active", "Scene inspection is unavailable while play mode is active or transitioning.")

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _error("no_edited_scene", "There is no currently edited scene.")

	var traversal_roots: Array[Node] = []
	if root_id.is_empty():
		traversal_roots.append(scene_root)
	else:
		var resolved := _resolve_root_id(root_id, scene_root)
		if resolved == null:
			return _error(
				"invalid_root_id",
				"root_id does not identify a node in the currently edited scene.",
			)
		traversal_roots.append(resolved)

	var max_depth := int(depth_result["value"])
	var offset := int(offset_result["value"])
	var limit := int(limit_result["value"])
	var state := {"seen": 0, "nodes": [], "has_more": false}
	for traversal_root: Node in traversal_roots:
		if _visit_node(traversal_root, scene_root, 0, max_depth, offset, limit, state):
			break

	var nodes: Array = state["nodes"]
	var truncated := bool(state["has_more"])
	return {
		"success": true,
		"engine": "godot",
		"scene": {
			"name": str(scene_root.name),
			"path": scene_root.scene_file_path,
			"saved": not scene_root.scene_file_path.is_empty(),
		},
		"root_id": root_id,
		"max_depth": max_depth,
		"offset": offset,
		"limit": limit,
		"returned": nodes.size(),
		"truncated": truncated,
		"next_offset": offset + nodes.size() if truncated else null,
		"nodes": nodes,
	}


func _bounded_integer(
	arguments: Dictionary,
	key: String,
	default_value: int,
	minimum: int,
	maximum: int,
) -> Dictionary:
	var raw_value: Variant = arguments.get(key, default_value)
	var raw_type := typeof(raw_value)
	if raw_type not in [TYPE_INT, TYPE_FLOAT] or float(raw_value) != floor(float(raw_value)):
		return _error("invalid_argument", "%s must be an integer." % key)
	var value := int(raw_value)
	if value < minimum or value > maximum:
		return _error(
			"invalid_argument",
			"%s must be between %d and %d." % [key, minimum, maximum],
		)
	return {"success": true, "value": value}


func _resolve_root_id(root_id: String, scene_root: Node) -> Node:
	if not root_id.begins_with("godot:"):
		return null
	var raw_instance_id := root_id.trim_prefix("godot:")
	if not raw_instance_id.is_valid_int():
		return null
	var candidate := instance_from_id(raw_instance_id.to_int()) as Node
	if candidate == null:
		return null
	if candidate != scene_root and not scene_root.is_ancestor_of(candidate):
		return null
	return candidate


func _visit_node(
	node: Node,
	scene_root: Node,
	depth: int,
	max_depth: int,
	offset: int,
	limit: int,
	state: Dictionary,
) -> bool:
	var seen := int(state["seen"])
	var nodes: Array = state["nodes"]
	if seen < offset:
		state["seen"] = seen + 1
	elif nodes.size() < limit:
		nodes.append(_describe_node(node, scene_root, depth))
		state["seen"] = seen + 1
	else:
		state["has_more"] = true
		return true

	if depth >= max_depth:
		return false
	for child: Node in node.get_children():
		if _visit_node(child, scene_root, depth + 1, max_depth, offset, limit, state):
			return true
	return false


func _describe_node(node: Node, scene_root: Node, depth: int) -> Dictionary:
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
		"depth": depth,
		"child_count": node.get_child_count(),
	}


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
