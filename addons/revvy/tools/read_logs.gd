@tool
extends RefCounted

const DEFAULT_LIMIT := 100
const MAX_LIMIT := 1000

var _capture


func _init(log_capture) -> void:
	_capture = log_capture


func descriptor() -> Dictionary:
	return {
		"name": "read_logs",
		"description": "Read the Revvy ring buffer of Godot editor-process messages and errors.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"action": {"type": "string", "enum": ["tail", "search", "errors"]},
				"query": {"type": "string", "description": "Case-insensitive text filter for search."},
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
			"readOnlyHint": true,
			"destructiveHint": false,
			"idempotentHint": false,
			"openWorldHint": false,
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	if _capture == null:
		return {"success": false, "error": "log capture is not registered"}

	var action: String = str(arguments.get("action", ""))
	var limit: int = clampi(int(arguments.get("limit", DEFAULT_LIMIT)), 1, MAX_LIMIT)
	var query := ""
	var severities := PackedStringArray()
	match action:
		"tail":
			pass
		"search":
			query = str(arguments.get("query", "")).strip_edges()
			if query.is_empty():
				return {"success": false, "error": "query is required for action=search"}
		"errors":
			severities = PackedStringArray(["error", "script_error", "shader_error"])
		_:
			return {"success": false, "error": "action must be tail, search, or errors"}

	var entries: Array = _capture.read_entries(limit, query, severities)
	return {
		"success": true,
		"action": action,
		"entries": entries,
		"count": entries.size(),
		"captured_total": _capture.entry_count(),
		"capture_scope": "godot_editor_process_since_plugin_registration",
		"limitations": [
			"Messages emitted before the plugin registered its Logger are unavailable.",
			"A separately launched game process is not guaranteed to be captured.",
			"This is not a reader for the editor Output panel's historical backlog.",
		],
	}
