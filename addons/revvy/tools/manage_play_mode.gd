@tool
extends RefCounted

# Tier-9 pause/step extension (docs/design/tier9-play-pause-step-contract.md).
# The descriptor carries pause, resume, and step on both engines, but Godot
# cannot perform them: the played scene runs as a separate OS process and the
# 4.5 EditorInterface exposes no pause or frame-step entry point for it
# (contract section 1.3, confirmed against the 4.5 class reference and the
# local editor's ClassDB — no method containing pause, step, or debug exists).
# get_tree().paused would pause the editor's own SceneTree, not the game's,
# and the remote debugger's step is UI-driven, not scriptable. This bridge
# therefore answers with pause_unsupported plus a capabilities object — an
# honest degradation the caller can discover from status up front.

const TRANSITION_TIMEOUT_MSEC := 30_000
const MIN_FRAMES := 1
const MAX_FRAMES := 60
const ACTIONS := ["status", "start", "stop", "pause", "resume", "step"]
const KNOWN_ARGUMENTS := ["action", "frames"]
# Contract section 10 (Godot): advertised on every result so a caller learns
# the limitation from status rather than from a failed pause.
const CAPABILITIES := {"pause": false, "step": false}

var _has_requested_state := false
var _requested_playing := false
var _transition_deadline_msec := 0
var _transition_sequence := 0
var _transition_error := ""


func descriptor() -> Dictionary:
	return {
		"name": "manage_play_mode",
		"description": "Inspect, start, stop, pause, resume, or single-frame step play mode for the currently edited scene.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"action": {
					"type": "string",
					"description": "Operation to perform.",
					"enum": ["status", "start", "stop", "pause", "resume", "step"],
				},
				"frames": {
					"type": "integer",
					"description": "For step: how many frames to advance. Each frame is advanced individually and the game stays paused afterwards.",
					"minimum": 1,
					"maximum": 60,
					"default": 1,
				},
			},
			"required": ["action"],
			"additionalProperties": false,
		},
		"annotations": {
			"readOnlyHint": false,
			"destructiveHint": true,
			"idempotentHint": false,
			"openWorldHint": true,
			"readOnlyActions": ["status"],
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	# Contract section 9 validation order: schema bounds (unknown arguments,
	# frames integer and bounds), then action, then per-action argument
	# presence, then the capability check, then the play-mode guard. The
	# capability check precedes the guard deliberately: on an engine that can
	# never pause, telling the caller to start play mode first would send it
	# down a path that ends in the same refusal.
	for raw_key: Variant in arguments.keys():
		var key := str(raw_key)
		if key not in KNOWN_ARGUMENTS:
			return _error("invalid_argument", "Unknown argument '%s'." % key)
	if _is_present(arguments, "frames"):
		var frames_error: Dictionary = _check_frames(arguments["frames"])
		if not frames_error.is_empty():
			return frames_error

	var action_value: Variant = arguments.get("action", null)
	if action_value == null or (typeof(action_value) == TYPE_STRING and str(action_value).is_empty()):
		return _error("invalid_argument", "Argument 'action' is required.")
	if typeof(action_value) != TYPE_STRING:
		return _error("invalid_argument", "action must be a string.")
	var action := str(action_value).strip_edges().to_lower()
	if action not in ACTIONS:
		return _error(
			"invalid_argument",
			"Unknown action '%s'. Expected one of: status, start, stop, pause, resume, step." % str(action_value),
		)

	# Contract section 4: frames defaults to 1, a legal value, so an explicit 1
	# is indistinguishable from omission and is never rejected as unused. Any
	# other value on a non-step action is invalid_argument.
	if action != "step" and _is_present(arguments, "frames") and int(arguments["frames"]) != 1:
		return _error(
			"invalid_argument",
			"Argument 'frames' is not used by action '%s'; omit it." % action,
		)

	match action:
		"status":
			_refresh_transition()
			if not _transition_error.is_empty():
				return _take_transition_error()
			return _build_result(action, false, false)
		"start":
			return _request_state(true, action)
		"stop":
			return _request_state(false, action)
		_:
			# pause, resume, step: contract section 10 (Godot). The capability
			# check fires here, before any play-mode guard, so the refusal is
			# identical in edit mode and play mode.
			return _error(
				"pause_unsupported",
				"This bridge cannot pause or step play mode: Godot runs the played scene as a separate process and EditorInterface exposes no pause or frame-step API.",
				{"capabilities": CAPABILITIES},
			)


func is_transitioning() -> bool:
	_refresh_transition()
	return _has_requested_state


func _request_state(target_playing: bool, action: String) -> Dictionary:
	_refresh_transition()
	if not _transition_error.is_empty():
		# Deferred failures are delivered by status; a new mutation supersedes them.
		_transition_error = ""

	if _has_requested_state and _requested_playing == target_playing:
		return _build_result(action, false, true)
	if not _has_requested_state and EditorInterface.is_playing_scene() == target_playing:
		return _build_result(action, false, true)

	if target_playing:
		var blocker: String = _start_blocker()
		if not blocker.is_empty():
			return {"success": false, "error": blocker}

	_transition_sequence += 1
	_has_requested_state = true
	_requested_playing = target_playing
	_transition_deadline_msec = Time.get_ticks_msec() + TRANSITION_TIMEOUT_MSEC
	_transition_error = ""

	var editor_tree := Engine.get_main_loop() as SceneTree
	if editor_tree == null:
		_fail_transition(_transition_sequence, "Cannot schedule a play-mode transition without the editor SceneTree.")
		return _take_transition_error()
	var connect_error: Error = editor_tree.process_frame.connect(
		_apply_play_transition.bind(_transition_sequence, target_playing),
		CONNECT_ONE_SHOT,
	)
	if connect_error != OK:
		_fail_transition(
			_transition_sequence,
			"Cannot schedule the play-mode transition (error %d)." % connect_error,
		)
		return _take_transition_error()

	return _build_result(action, true, true)


func _apply_play_transition(sequence: int, target_playing: bool) -> void:
	if sequence != _transition_sequence or not _has_requested_state or _requested_playing != target_playing:
		return

	if target_playing:
		var blocker: String = _start_blocker()
		if not blocker.is_empty():
			_fail_transition(sequence, blocker)
			return
		EditorInterface.play_current_scene()
	else:
		EditorInterface.stop_playing_scene()

	_refresh_transition()


func _start_blocker() -> String:
	var edited_root: Node = EditorInterface.get_edited_scene_root()
	if edited_root == null or edited_root.scene_file_path.is_empty():
		return "Cannot start play mode because there is no current saved scene."

	var editor_filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if editor_filesystem != null and editor_filesystem.is_scanning():
		return "Cannot start play mode while Godot is scanning or importing resources."
	return ""


func _build_result(action: String, changed: bool, include_verify: bool) -> Dictionary:
	_refresh_transition()

	var playing: bool = EditorInterface.is_playing_scene()
	var transitioning: bool = _has_requested_state
	var result := {
		"success": true,
		"action": action,
		"engine": "godot",
		"changed": changed,
		"transition_pending": transitioning,
		"state": {
			"playing": playing,
			# Contract section 10 (Godot): the editor cannot observe the
			# separate game process's pause state, so paused is always false
			# and pending_steps always 0.
			"paused": false,
			"transitioning": transitioning,
			"pending_steps": 0,
			"scene": _edited_scene_path(),
		},
		"capabilities": CAPABILITIES,
	}
	if include_verify:
		result["verify_with"] = {
			"tool": "manage_play_mode",
			"arguments": {"action": "status"},
		}
	return result


func _refresh_transition() -> void:
	if not _has_requested_state:
		return

	var reached_target: bool = EditorInterface.is_playing_scene() == _requested_playing
	if reached_target:
		_clear_transition(_transition_sequence)
	elif Time.get_ticks_msec() >= _transition_deadline_msec:
		var target_name := "playing" if _requested_playing else "stopped"
		_fail_transition(
			_transition_sequence,
			"Godot did not reach the requested %s state within %d seconds." % [
				target_name,
				TRANSITION_TIMEOUT_MSEC / 1000,
			],
		)


func _fail_transition(sequence: int, message: String) -> void:
	if sequence != _transition_sequence:
		return
	_transition_error = message
	_clear_transition(sequence)


func _clear_transition(sequence: int) -> void:
	if sequence != _transition_sequence:
		return
	_has_requested_state = false
	_transition_deadline_msec = 0


func _take_transition_error() -> Dictionary:
	var message := _transition_error
	_transition_error = ""
	return {"success": false, "error": message}


func _edited_scene_path() -> String:
	var edited_root: Node = EditorInterface.get_edited_scene_root()
	return edited_root.scene_file_path if edited_root != null else ""


func _check_frames(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT] or float(raw_value) != floor(float(raw_value)):
		return _error("invalid_argument", "frames must be an integer.")
	var value := int(raw_value)
	if value < MIN_FRAMES or value > MAX_FRAMES:
		return _error(
			"invalid_argument",
			"frames must be between %d and %d." % [MIN_FRAMES, MAX_FRAMES],
		)
	return {}


func _is_present(arguments: Dictionary, key: String) -> bool:
	# Absent means omitted or JSON null (Tier-3 section 3).
	return arguments.has(key) and arguments[key] != null


func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var payload := {
		"success": false,
		"engine": "godot",
		"error_code": code,
		"error": message,
	}
	for extra_key: Variant in extra.keys():
		payload[extra_key] = extra[extra_key]
	return payload
