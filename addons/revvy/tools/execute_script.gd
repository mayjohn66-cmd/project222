@tool
extends RefCounted

const MAX_EXPRESSION_LENGTH := 64 * 1024


func descriptor() -> Dictionary:
	return {
		"name": "execute_script",
		"description": (
			"Evaluate one Godot Expression on the editor main thread. This is a constrained, "
			+ "const-call-only expression subset, not arbitrary or multiline GDScript."
		),
		"inputSchema": {
			"type": "object",
			"properties": {
				"code": {
					"type": "string",
					"description": "One Expression-compatible expression.",
					"minLength": 1,
					"maxLength": MAX_EXPRESSION_LENGTH,
				},
				"inputs": {
					"type": "object",
					"description": "Optional JSON values bound as named expression inputs.",
					"additionalProperties": true,
				},
			},
			"required": ["code"],
			"additionalProperties": false,
		},
		"annotations": {
			"readOnlyHint": false,
			"destructiveHint": true,
			"idempotentHint": false,
			"openWorldHint": false,
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	var code: String = str(arguments.get("code", "")).strip_edges()
	if code.is_empty():
		return {"success": false, "error": "code must be a non-empty expression"}
	if code.length() > MAX_EXPRESSION_LENGTH:
		return {"success": false, "error": "expression exceeds 64 KiB"}

	var raw_inputs: Variant = arguments.get("inputs", {})
	if typeof(raw_inputs) != TYPE_DICTIONARY:
		return {"success": false, "error": "inputs must be an object"}
	var inputs: Dictionary = raw_inputs

	var input_names := PackedStringArray()
	var input_values: Array = []
	for key: Variant in inputs:
		if typeof(key) != TYPE_STRING:
			return {"success": false, "error": "input names must be strings"}
		var input_name: String = key
		if not input_name.is_valid_identifier():
			return {"success": false, "error": "invalid input identifier: " + input_name}
		input_names.append(input_name)
		input_values.append(inputs[key])

	var expression := Expression.new()
	var parse_error: Error = expression.parse(code, input_names)
	if parse_error != OK:
		return {
			"success": false,
			"error": "Expression parse failed: " + expression.get_error_text(),
		}

	# A null base instance and const_calls_only=true deliberately withhold
	# EditorInterface, SceneTree, Nodes, and arbitrary mutating method calls.
	var result: Variant = expression.execute(input_values, null, false, true)
	if expression.has_execute_failed():
		return {
			"success": false,
			"error": "Expression execution failed: " + expression.get_error_text(),
		}

	return {
		"success": true,
		"result": _json_safe(result),
		"result_type": type_string(typeof(result)),
		"execution_mode": "expression_const_calls_only",
		"security": (
			"No editor or scene objects are bound. Expression is still not a formal sandbox; "
			+ "use the authenticated Revvy proxy for untrusted clients."
		),
	}


func _json_safe(value: Variant, depth: int = 0) -> Variant:
	if depth > 8:
		return {"type": type_string(typeof(value)), "value": "<depth limit>"}

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			var number: float = value
			return str(number) if is_nan(number) or is_inf(number) else number
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_ARRAY:
			var safe_array: Array = []
			for item: Variant in value:
				safe_array.append(_json_safe(item, depth + 1))
			return safe_array
		TYPE_DICTIONARY:
			var safe_dictionary: Dictionary = {}
			for key: Variant in value:
				safe_dictionary[str(key)] = _json_safe(value[key], depth + 1)
			return safe_dictionary
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR4:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_VECTOR4I:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_OBJECT:
			if value == null or not is_instance_valid(value):
				return null
			return {"type": value.get_class(), "value": str(value)}
		_:
			return {"type": type_string(typeof(value)), "value": str(value)}
