@tool
extends RefCounted

# Tier-7 simulated input (docs/design/tier7-simulated-input-contract.md).
# Delivers discrete keyboard/mouse state changes to the running game during
# play mode. Godot's Input singleton supplies the built-in backend, so its
# description is fixed; only the REVVY_INPUT_BACKEND=none kill switch (contract
# section 13) can make resolution fail. The descriptor is a shared artefact —
# it must be identical on every project and engine, so it is a pure literal.

const MAX_COORDINATE := 16384
const ACTIONS := ["status", "key_down", "key_up", "mouse_move", "mouse_button_down", "mouse_button_up"]
const KNOWN_ARGUMENTS := ["action", "key", "button", "x", "y"]
# Contract section 9: the closed neutral vocabulary, mapped to Godot Key
# constants. Modifier names are unsided and resolve to the left key; Godot's
# KEY_SHIFT/KEY_CTRL/KEY_ALT are exactly those left-side constants.
const KEY_KEYCODES := {
	"a": KEY_A, "b": KEY_B, "c": KEY_C, "d": KEY_D, "e": KEY_E, "f": KEY_F,
	"g": KEY_G, "h": KEY_H, "i": KEY_I, "j": KEY_J, "k": KEY_K, "l": KEY_L,
	"m": KEY_M, "n": KEY_N, "o": KEY_O, "p": KEY_P, "q": KEY_Q, "r": KEY_R,
	"s": KEY_S, "t": KEY_T, "u": KEY_U, "v": KEY_V, "w": KEY_W, "x": KEY_X,
	"y": KEY_Y, "z": KEY_Z,
	"0": KEY_0, "1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
	"5": KEY_5, "6": KEY_6, "7": KEY_7, "8": KEY_8, "9": KEY_9,
	"space": KEY_SPACE,
	"enter": KEY_ENTER,
	"escape": KEY_ESCAPE,
	"tab": KEY_TAB,
	"backspace": KEY_BACKSPACE,
	"delete": KEY_DELETE,
	"up": KEY_UP,
	"down": KEY_DOWN,
	"left": KEY_LEFT,
	"right": KEY_RIGHT,
	"shift": KEY_SHIFT,
	"ctrl": KEY_CTRL,
	"alt": KEY_ALT,
}
const BUTTON_INDICES := {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
}
# Contract section 4: x and y default to 0, a legal coordinate, so they can
# never be rejected as unused; only key and button are refused on actions that
# do not use them.
const UNUSED_ARGUMENTS := {
	"status": ["key", "button"],
	"key_down": ["button"],
	"key_up": ["button"],
	"mouse_move": ["key", "button"],
	"mouse_button_down": ["key"],
	"mouse_button_up": ["key"],
}

# The pointer position from the most recent mouse_move, stamped onto button
# events so a click reads as happening where the caller parked the pointer.
var _last_pointer := Vector2.ZERO


func descriptor() -> Dictionary:
	return {
		"name": "simulate_input",
		"description": "Send simulated keyboard and mouse input to the running game during play mode.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"action": {
					"type": "string",
					"description": "Input event to deliver, or status to report backend availability without sending anything.",
					"enum": ["status", "key_down", "key_up", "mouse_move", "mouse_button_down", "mouse_button_up"],
				},
				"key": {
					"type": "string",
					"description": "For key_down and key_up: engine-neutral key name from the curated vocabulary.",
					"enum": [
						"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
						"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
						"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
						"space", "enter", "escape", "tab", "backspace", "delete",
						"up", "down", "left", "right",
						"shift", "ctrl", "alt",
					],
					"default": "",
				},
				"button": {
					"type": "string",
					"description": "For mouse_button_down and mouse_button_up: which mouse button.",
					"enum": ["left", "right", "middle"],
					"default": "",
				},
				"x": {
					"type": "integer",
					"description": "For mouse_move: pointer X in game-view pixels, origin top-left.",
					"minimum": 0,
					"maximum": 16384,
					"default": 0,
				},
				"y": {
					"type": "integer",
					"description": "For mouse_move: pointer Y in game-view pixels, origin top-left, increasing downward.",
					"minimum": 0,
					"maximum": 16384,
					"default": 0,
				},
			},
			"required": ["action"],
			"additionalProperties": false,
		},
		"annotations": {
			"title": "Simulate input",
			"readOnlyHint": false,
			"destructiveHint": false,
			"idempotentHint": false,
			"openWorldHint": false,
			"readOnlyActions": ["status"],
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	# Contract section 8 fixes the validation order: schema bounds (unknown
	# arguments, types, coordinate bounds), then action, then per-action
	# argument presence, then vocabulary, then the play-mode guard, then
	# backend resolution, then delivery. Argument validation precedes both
	# guards deliberately: a caller who sends a misspelled key should learn
	# that regardless of whether the editor happens to be playing, because
	# that bug survives entering play mode.
	for raw_key: Variant in arguments.keys():
		var key := str(raw_key)
		if key not in KNOWN_ARGUMENTS:
			return _error("invalid_argument", "Unknown argument '%s'." % key)
	for string_key: String in ["key", "button"]:
		if _is_present(arguments, string_key) and typeof(arguments[string_key]) != TYPE_STRING:
			return _error("invalid_argument", "%s must be a string." % string_key)
	for axis: String in ["x", "y"]:
		var coordinate_error: Dictionary = _check_coordinate(arguments, axis)
		if not coordinate_error.is_empty():
			return coordinate_error

	var action_value: Variant = arguments.get("action", null)
	if action_value == null or (typeof(action_value) == TYPE_STRING and str(action_value).is_empty()):
		return _error("invalid_argument", "Argument 'action' is required.")
	if typeof(action_value) != TYPE_STRING:
		return _error("invalid_argument", "action must be a string.")
	var action := str(action_value).strip_edges().to_lower()
	if action not in ACTIONS:
		return _error(
			"invalid_argument",
			"Unknown action '%s'. Expected one of: status, key_down, key_up, mouse_move, mouse_button_down, mouse_button_up." % str(action_value),
		)

	# An argument the chosen action does not use is an error, never a silent
	# ignore; an explicit empty string is treated as omitted (Tier-3 section 3).
	for unused_key: String in UNUSED_ARGUMENTS[action]:
		if not _is_present(arguments, unused_key):
			continue
		if str(arguments[unused_key]).is_empty():
			continue
		return _error(
			"invalid_argument",
			"Argument '%s' is not used by action '%s'; omit it." % [unused_key, action],
		)

	match action:
		"status":
			return _status()
		"key_down", "key_up":
			if not _is_present(arguments, "key") or str(arguments["key"]).is_empty():
				return _error("invalid_argument", "Argument 'key' is required for this action.")
			var key := str(arguments["key"])
			# Contract section 4: matched exactly, byte for byte. "A", " space",
			# and raw engine identifiers like "KEY_A" are all invalid_argument.
			if key not in KEY_KEYCODES:
				return _error(
					"invalid_argument",
					"Unknown key '%s'. Engine key identifiers are never accepted; expected one of the curated names, e.g. a-z, 0-9, space, enter, escape, tab, backspace, delete, up, down, left, right, shift, ctrl, alt." % key,
				)
			return _deliver_key(action, key, action == "key_down")
		"mouse_move":
			return _deliver_mouse_move(_coordinate(arguments, "x"), _coordinate(arguments, "y"))
		_:
			# mouse_button_down / mouse_button_up.
			if not _is_present(arguments, "button") or str(arguments["button"]).is_empty():
				return _error("invalid_argument", "Argument 'button' is required for this action.")
			var button := str(arguments["button"])
			if button not in BUTTON_INDICES:
				return _error(
					"invalid_argument",
					"Unknown button '%s'. Expected one of: left, right, middle." % button,
				)
			return _deliver_mouse_button(action, button, action == "mouse_button_down")


# Contract section 5: status answers a capability question, not an input
# question, so it succeeds in both modes. It is how a caller discovers whether
# simulation is possible before entering play mode.
func _status() -> Dictionary:
	var backend_available := _backend_available()
	# screen reports the coordinate space mouse_move expects; when no game view
	# exists yet it reports zeros.
	var screen := {"width": 0, "height": 0}
	if backend_available and EditorInterface.is_playing_scene():
		screen = {
			"width": int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)),
			"height": int(ProjectSettings.get_setting("display/window/size/viewport_height", 648)),
		}
	return {
		"success": true,
		"engine": "godot",
		"action": "status",
		"play_mode": EditorInterface.is_playing_scene(),
		"backend": _describe_backend(backend_available),
		"screen": screen,
	}


func _deliver_key(action: String, key: String, pressed: bool) -> Dictionary:
	var refusal := _require_delivery_backend()
	if not refusal.is_empty():
		return refusal
	# Contract section 10: InputEventKey with keycode and pressed, dispatched
	# via Input.parse_input_event(). Single events carry no whole-device state,
	# so no held-state tracking is required.
	var event := InputEventKey.new()
	event.keycode = KEY_KEYCODES[key]
	event.pressed = pressed
	Input.parse_input_event(event)
	return _delivered(action, {"key": key})


func _deliver_mouse_move(x: int, y: int) -> Dictionary:
	var refusal := _require_delivery_backend()
	if not refusal.is_empty():
		return refusal
	# Contract section 10: the viewport origin is already top-left, so no flip
	# is needed. warp_mouse covers games that read the OS pointer instead of
	# the event stream.
	var event := InputEventMouseMotion.new()
	event.position = Vector2(x, y)
	Input.parse_input_event(event)
	Input.warp_mouse(Vector2(x, y))
	_last_pointer = Vector2(x, y)
	return _delivered("mouse_move", {"x": x, "y": y})


func _deliver_mouse_button(action: String, button: String, pressed: bool) -> Dictionary:
	var refusal := _require_delivery_backend()
	if not refusal.is_empty():
		return refusal
	var event := InputEventMouseButton.new()
	event.button_index = BUTTON_INDICES[button]
	event.pressed = pressed
	event.position = _last_pointer
	Input.parse_input_event(event)
	return _delivered(action, {"button": button})


# Contract section 5 then section 8: the play-mode guard first, then backend
# resolution. Input delivered in edit mode has nowhere to go — no game loop is
# consuming it — so accepting it would report success for an action that did
# nothing.
func _require_delivery_backend() -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return _error(
			"play_mode_required",
			"Simulated input requires play mode; nothing is consuming input in edit mode. Start play mode with manage_play_mode and retry.",
		)
	if not _backend_available():
		return _error(
			"input_backend_unavailable",
			"No input backend is available. The Godot input backend is disabled by REVVY_INPUT_BACKEND=none; unset it or set it to any other value to enable simulated input.",
			{"backend": _describe_backend(false)},
		)
	return {}


# Contract section 13: REVVY_INPUT_BACKEND=none makes backend resolution
# return nothing, exactly as a project without a backend would report. Any
# other value, including unset, means normal resolution. The check runs on
# every call, so toggling the variable takes effect immediately.
func _backend_available() -> bool:
	return OS.get_environment("REVVY_INPUT_BACKEND").strip_edges().to_lower() != "none"


func _describe_backend(available: bool) -> Dictionary:
	if not available:
		return {
			"available": false,
			"name": "",
			"detail": "disabled by REVVY_INPUT_BACKEND=none",
		}
	return {
		"available": true,
		"name": "godot-input",
		"detail": "Godot %s Input singleton" % str(Engine.get_version_info().get("string", "")),
		"devices": ["Keyboard", "Mouse"],
	}


func _check_coordinate(arguments: Dictionary, axis: String) -> Dictionary:
	if not _is_present(arguments, axis):
		return {}
	var raw_value: Variant = arguments[axis]
	if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT] or float(raw_value) != floor(float(raw_value)):
		return _error("invalid_argument", "%s must be an integer." % axis)
	var value := int(raw_value)
	if value < 0 or value > MAX_COORDINATE:
		return _error(
			"invalid_argument",
			"%s must be between 0 and %d." % [axis, MAX_COORDINATE],
		)
	return {}


func _coordinate(arguments: Dictionary, axis: String) -> int:
	if not _is_present(arguments, axis):
		return 0
	return int(arguments[axis])


func _delivered(action: String, delivered: Dictionary) -> Dictionary:
	return {
		"success": true,
		"engine": "godot",
		"action": action,
		"play_mode": EditorInterface.is_playing_scene(),
		"backend": _describe_backend(true),
		# delivered echoes exactly what was sent, so a caller can confirm the
		# interpretation of its own request without re-deriving it.
		"delivered": delivered,
	}


func _is_present(arguments: Dictionary, key: String) -> bool:
	# Absent means omitted or JSON null. An explicit empty string still counts
	# as present here so required arguments reject it; unused arguments apply
	# their own empty-string tolerance at the use site (Tier-3 section 3).
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
