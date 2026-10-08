@tool
extends RefCounted

# Tier-8 curated node properties (docs/design/tier8-node-properties-contract.md).
# Reads and writes a closed, engine-neutral property vocabulary on objects that
# already live in the edited scene. The descriptor is a shared artefact — it
# must be identical on every project and engine, so it is a pure literal.

const ACTIONS := ["list", "get", "set"]
const KNOWN_ARGUMENTS := ["action", "target_id", "property", "value"]
# Contract section 4: an argument the chosen action does not use is an error,
# never a silent ignore. set uses everything it can be given.
const UNUSED_ARGUMENTS := {
	"list": ["property", "value"],
	"get": ["value"],
	"set": [],
}
# Contract section 9: the closed neutral vocabulary with its value types
# (contract section 10). Insertion order is the list-action reporting order.
const PROPERTY_TYPES := {
	"transform.position": "vector3",
	"transform.rotation": "vector3",
	"transform.scale": "vector3",
	"light.color": "color",
	"light.intensity": "float",
	"light.range": "float",
	"light.shadows_enabled": "bool",
	"camera.field_of_view": "float",
	"camera.near_clip": "float",
	"camera.far_clip": "float",
	"camera.orthographic": "bool",
}
# Contract section 9's Godot column. camera.orthographic is absent on purpose:
# it maps to Camera3D.projection, not a same-named property, and is special-cased
# at the read/write sites.
const ENGINE_PROPERTIES := {
	"transform.position": "position",
	"transform.rotation": "rotation_degrees",
	"transform.scale": "scale",
	"light.color": "light_color",
	"light.intensity": "light_energy",
	"light.range": "omni_range",
	"light.shadows_enabled": "shadow_enabled",
	"camera.field_of_view": "fov",
	"camera.near_clip": "near",
	"camera.far_clip": "far",
}

var _play_mode_tool = null


func _init(play_mode_tool = null) -> void:
	_play_mode_tool = play_mode_tool


func descriptor() -> Dictionary:
	return {
		"name": "manage_properties",
		"description": "Read and write curated properties of an object in the currently edited scene.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"action": {
					"type": "string",
					"description": "Operation to perform.",
					"enum": ["list", "get", "set"],
				},
				"target_id": {
					"type": "string",
					"description": "Opaque ID of the object, as returned by inspect_scene or mutate_scene.",
					"default": "",
				},
				"property": {
					"type": "string",
					"description": "For get and set: engine-neutral property name from the curated vocabulary.",
					"enum": [
						"transform.position",
						"transform.rotation",
						"transform.scale",
						"light.color",
						"light.intensity",
						"light.range",
						"light.shadows_enabled",
						"camera.field_of_view",
						"camera.near_clip",
						"camera.far_clip",
						"camera.orthographic",
					],
					"default": "",
				},
				"value": {
					"description": "For set: the new value, encoded per the property's type (contract section 10).",
					"default": null,
				},
			},
			"required": ["action"],
			"additionalProperties": false,
		},
		"annotations": {
			"title": "Manage properties",
			"readOnlyHint": false,
			"destructiveHint": false,
			"idempotentHint": false,
			"openWorldHint": false,
			"readOnlyActions": ["list", "get"],
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	# Contract section 8 fixes the validation order: schema (unknown arguments,
	# known-argument types), then action, then per-action argument presence, then
	# the property vocabulary, then the play-mode and edited-scene guards, then
	# target_id, then applicability, then value type, then value range, then the
	# write. Argument and vocabulary validation precede the guards deliberately:
	# a misspelled property is a caller bug that survives leaving play mode, so
	# reporting it first is more useful than reporting the environment.
	for raw_key: Variant in arguments.keys():
		var key := str(raw_key)
		if key not in KNOWN_ARGUMENTS:
			return _error("invalid_argument", "Unknown argument '%s'." % key)
	for string_key: String in ["action", "target_id", "property"]:
		if _is_present(arguments, string_key) and typeof(arguments[string_key]) != TYPE_STRING:
			return _error("invalid_argument", "%s must be a string." % string_key)

	var action_value: Variant = arguments.get("action", null)
	if action_value == null or (typeof(action_value) == TYPE_STRING and str(action_value).is_empty()):
		return _error("invalid_argument", "Argument 'action' is required.")
	var action := str(action_value)
	if action not in ACTIONS:
		return _error(
			"invalid_argument",
			"Unknown action '%s'. Expected one of: list, get, set." % action,
		)

	# Per-action argument presence (contract section 4). An explicit empty string
	# is invalid for a required argument and is treated as omitted for an unused
	# one; value defaults to null, so absent and explicitly null are the same.
	if not _is_present(arguments, "target_id") or str(arguments["target_id"]).is_empty():
		return _error("invalid_argument", "Argument 'target_id' is required for action '%s'." % action)
	if action in ["get", "set"] and (not _is_present(arguments, "property") or str(arguments["property"]).is_empty()):
		return _error("invalid_argument", "Argument 'property' is required for action '%s'." % action)
	if action == "set" and not _is_present(arguments, "value"):
		return _error("invalid_argument", "Argument 'value' is required for action 'set'.")
	for unused_key: String in UNUSED_ARGUMENTS[action]:
		if not _is_present(arguments, unused_key):
			continue
		if typeof(arguments[unused_key]) == TYPE_STRING and str(arguments[unused_key]).is_empty():
			continue
		return _error(
			"invalid_argument",
			"Argument '%s' is not used by action '%s'; omit it." % [unused_key, action],
		)

	# Contract section 4: the property name is matched exactly, byte for byte.
	# "Transform.Position", " light.color", and engine paths like "m_Intensity"
	# or "light_energy" are all invalid_argument and never fuzzy-matched.
	var property := ""
	if action in ["get", "set"]:
		property = str(arguments["property"])
		if property not in PROPERTY_TYPES:
			return _error(
				"invalid_argument",
				"Unknown property '%s'. Engine property paths are never accepted; expected one of the curated names: transform.position, transform.rotation, transform.scale, light.color, light.intensity, light.range, light.shadows_enabled, camera.field_of_view, camera.near_clip, camera.far_clip, camera.orthographic." % property,
			)

	# Contract section 5: every action, reads included, is refused while play
	# mode is active or entering/exiting — scene tools are edit-mode tools.
	if EditorInterface.is_playing_scene() or (
		_play_mode_tool != null and bool(_play_mode_tool.is_transitioning())
	):
		return _error(
			"play_mode_active",
			"Property access is unavailable while play mode is active or transitioning.",
		)

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _error("no_edited_scene", "There is no currently edited scene.")

	var target_id := str(arguments["target_id"])
	var target := _resolve_scene_node(target_id, scene_root)
	if target == null:
		return _error(
			"invalid_target_id",
			"target_id '%s' does not identify a live node in the currently edited scene." % target_id,
		)

	match action:
		"list":
			return _list(target_id, target)
		"get":
			if not _applies(property, target):
				return _not_applicable(property, target)
			return {
				"success": true,
				"engine": "godot",
				"action": "get",
				"target_id": target_id,
				"property": property,
				"type": PROPERTY_TYPES[property],
				"value": _read_value(property, target),
			}
		_:
			return _write(target_id, property, target, arguments["value"], scene_root)


# Contract section 7.1: list reports exactly the properties applicable to this
# object, with current values, so a caller can discover what it may set without
# guessing. A plain Node (Tier-5's "object") has no 3D transform on Godot, so
# its list is honestly empty.
func _list(target_id: String, target: Node) -> Dictionary:
	var properties: Array = []
	for property: String in PROPERTY_TYPES.keys():
		if not _applies(property, target):
			continue
		properties.append({
			"property": property,
			"type": PROPERTY_TYPES[property],
			"value": _read_value(property, target),
		})
	return {
		"success": true,
		"engine": "godot",
		"action": "list",
		"target_id": target_id,
		"properties": properties,
		"count": properties.size(),
	}


func _write(target_id: String, property: String, target: Node, raw_value: Variant, scene_root: Node) -> Dictionary:
	if not _applies(property, target):
		return _not_applicable(property, target)

	# Value type first, then range (contract section 8's order): a caller learns
	# its value is the wrong shape before learning it is out of bounds.
	var checked: Dictionary = _check_value_type(property, raw_value)
	if checked.get("ok") != true:
		return checked
	var value: Variant = checked["value"]
	var range_error: Dictionary = _check_value_range(property, value)
	if not range_error.is_empty():
		return range_error

	# previous_value is read before the write, so a caller can undo in its own
	# head or report what it replaced.
	var previous: Variant = _read_value(property, target)
	# Contract section 1.5: editing an instanced PackedScene's node produces a
	# local override automatically, exactly as the inspector would; the flag is
	# informational and the write happens either way.
	var prefab_override := _belongs_to_scene_instance(target, scene_root)
	if _to_engine_value(property, previous) == _to_engine_value(property, value):
		# Contract section 7.3: a set to the value already stored still succeeds
		# but records no undo step and does not dirty the scene — matching
		# mutate_scene's same-name rename. No write means no editable-instance
		# side effect either (Tier-11 section 8.2).
		return {
			"success": true,
			"engine": "godot",
			"action": "set",
			"target_id": target_id,
			"property": property,
			"type": PROPERTY_TYPES[property],
			"previous_value": previous,
			"value": previous,
			"changed": false,
			"prefab_override": prefab_override,
			"override_created": false,
			"editable_enabled": false,
		}

	# Tier-11 sections 8.2/8.3: a write targeting a node inside a scene
	# instance survives a save only when the owning instance is editable — a
	# file-format rule, not a bridge choice. The bridge turns it on before the
	# write and reports having done so; a write on the instance root itself
	# persists without it.
	var editable_enabled := false
	var instance_root := _nearest_instance_root(target, scene_root)
	if instance_root != null and instance_root != target:
		var holder: Node = instance_root.owner if instance_root.owner != null else scene_root
		if holder != null and not holder.is_editable_instance(instance_root):
			holder.set_editable_instance(instance_root, true)
			editable_enabled = true

	# Tier-15 contract section 2.1 (Godot): override_created is the before/after
	# pair around the write — the property is an override when the live value
	# differs from the value the packed scene supplies for this node. The
	# reference comes from the same GEN_EDIT_STATE_INSTANCE load path
	# manage_prefab uses, so both tools read identical source values. A plain
	# object, a failed reference, or an added node (no pack counterpart) can
	# create no override and reports false.
	var reference_root: Node = null
	var reference_node: Node = null
	if instance_root != null:
		reference_root = _instantiate_reference(instance_root.scene_file_path)
		if reference_root != null:
			reference_node = _reference_counterpart(reference_root, instance_root, target)
	var override_before := _is_property_override(property, target, reference_node)

	# Tier-3's one-call-one-undo rule carries over unchanged: exactly one editor
	# undo step per set via the edited scene's EditorUndoRedoManager.
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy set property")
	if property == "camera.orthographic":
		var new_projection := Camera3D.PROJECTION_ORTHOGONAL if value else Camera3D.PROJECTION_PERSPECTIVE
		var old_projection := Camera3D.PROJECTION_ORTHOGONAL if previous else Camera3D.PROJECTION_PERSPECTIVE
		undo_redo.add_do_property(target, "projection", new_projection)
		undo_redo.add_undo_property(target, "projection", old_projection)
	else:
		undo_redo.add_do_property(target, ENGINE_PROPERTIES[property], _to_engine_value(property, value))
		undo_redo.add_undo_property(target, ENGINE_PROPERTIES[property], _to_engine_value(property, previous))
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()

	var override_after := _is_property_override(property, target, reference_node)
	if reference_root != null:
		reference_root.free()

	# The echoed value is read back from the engine after the write, so the
	# caller sees what was actually stored, quantisation included (section 10).
	return {
		"success": true,
		"engine": "godot",
		"action": "set",
		"target_id": target_id,
		"property": property,
		"type": PROPERTY_TYPES[property],
		"previous_value": previous,
		"value": _read_value(property, target),
		"changed": true,
		"prefab_override": prefab_override,
		"override_created": override_after and not override_before,
		"editable_enabled": editable_enabled,
	}


# The nearest instance root above (or at) the node: the first ancestor below
# the edited scene root with a non-empty scene_file_path. Same walk as
# _belongs_to_scene_instance, returning the root itself (Tier-11 section 8.2
# needs it to toggle the editable flag on the owning instance).
func _nearest_instance_root(node: Node, scene_root: Node) -> Node:
	var current := node
	while current != null and current != scene_root:
		if not current.scene_file_path.is_empty():
			return current
		current = current.get_parent()
	return null


# Contract section 9's applicability column. light.range applies to point
# lights only (OmniLight3D carries omni_range); on a directional light it is
# property_not_applicable, the silent-no-op case from section 1.3.
func _applies(property: String, target: Node) -> bool:
	match property:
		"transform.position", "transform.rotation", "transform.scale":
			return target is Node3D
		"light.color", "light.intensity", "light.shadows_enabled":
			return target is Light3D
		"light.range":
			return target is OmniLight3D
		"camera.field_of_view", "camera.near_clip", "camera.far_clip", "camera.orthographic":
			return target is Camera3D
	return false


func _not_applicable(property: String, target: Node) -> Dictionary:
	var reason := ""
	if property.begins_with("transform."):
		reason = "requires an object with a 3D transform"
	elif property == "light.range":
		reason = "applies to point lights only"
	elif property.begins_with("light."):
		reason = "requires an object with a light"
	else:
		reason = "requires an object with a camera"
	return _error(
		"property_not_applicable",
		"Property '%s' %s; the target is a %s." % [property, reason, target.get_class()],
	)


func _read_value(property: String, target: Node) -> Variant:
	if property == "camera.orthographic":
		return (target as Camera3D).projection == Camera3D.PROJECTION_ORTHOGONAL
	var engine_value: Variant = target.get(ENGINE_PROPERTIES[property])
	return _to_wire_value(property, engine_value)


func _to_wire_value(property: String, engine_value: Variant) -> Variant:
	match PROPERTY_TYPES[property]:
		"vector3":
			var vector: Vector3 = engine_value
			return {"x": vector.x, "y": vector.y, "z": vector.z}
		"color":
			var color_value: Color = engine_value
			return {"r": color_value.r, "g": color_value.g, "b": color_value.b, "a": color_value.a}
	return engine_value


func _to_engine_value(property: String, wire_value: Variant) -> Variant:
	match PROPERTY_TYPES[property]:
		"vector3":
			return Vector3(float(wire_value["x"]), float(wire_value["y"]), float(wire_value["z"]))
		"color":
			return Color(float(wire_value["r"]), float(wire_value["g"]), float(wire_value["b"]), float(wire_value["a"]))
	return wire_value


# Contract section 10: strict shapes, no silently defaulted components. A
# missing field, an extra field, or a wrong JSON kind is value_type_mismatch.
# Returns {"ok": true, "value": ...} or an error dictionary.
func _check_value_type(property: String, raw_value: Variant) -> Dictionary:
	match PROPERTY_TYPES[property]:
		"bool":
			if typeof(raw_value) != TYPE_BOOL:
				return _error("value_type_mismatch", "Property '%s' expects a JSON boolean." % property)
			return {"ok": true, "value": raw_value}
		"float":
			# Integers are accepted and widened; strings and booleans are not.
			if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT]:
				return _error("value_type_mismatch", "Property '%s' expects a JSON number." % property)
			return {"ok": true, "value": float(raw_value)}
		"vector3":
			return _check_struct_value(property, raw_value, ["x", "y", "z"])
		_:
			return _check_struct_value(property, raw_value, ["r", "g", "b", "a"])


func _check_struct_value(property: String, raw_value: Variant, fields: Array) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _error(
			"value_type_mismatch",
			"Property '%s' expects an object with fields: %s." % [property, ", ".join(fields)],
		)
	for field: String in fields:
		if not raw_value.has(field):
			return _error(
				"value_type_mismatch",
				"Property '%s' value is missing required field '%s'." % [property, field],
			)
	if raw_value.size() != fields.size():
		return _error(
			"value_type_mismatch",
			"Property '%s' value carries an unknown field; expected exactly: %s." % [property, ", ".join(fields)],
		)
	var converted := {}
	for field: String in fields:
		if typeof(raw_value[field]) not in [TYPE_INT, TYPE_FLOAT]:
			return _error(
				"value_type_mismatch",
				"Property '%s' field '%s' expects a JSON number." % [property, field],
			)
		converted[field] = float(raw_value[field])
	return {"ok": true, "value": converted}


# Contract section 9's bounds: the value is the right type but outside the
# documented range.
func _check_value_range(property: String, value: Variant) -> Dictionary:
	match property:
		"light.intensity":
			if value < 0.0:
				return _out_of_range(property, "must be >= 0")
		"light.range", "camera.near_clip", "camera.far_clip":
			if value <= 0.0:
				return _out_of_range(property, "must be > 0")
		"camera.field_of_view":
			if value < 1.0 or value > 179.0:
				return _out_of_range(property, "must be between 1 and 179")
		"light.color":
			for field: String in ["r", "g", "b", "a"]:
				if value[field] < 0.0 or value[field] > 1.0:
					return _out_of_range(property, "field '%s' must be between 0 and 1" % field)
	# transform.scale is unbounded, including negative and zero (section 9).
	return {}


func _out_of_range(property: String, bound: String) -> Dictionary:
	return _error("value_out_of_range", "Property '%s' %s." % [property, bound])


# Contract sections 1.4 and 1.5: a node is part of a prefab instance when it or
# any ancestor below the edited scene root is an instance root, which is exactly
# what a non-empty scene_file_path marks. The edited scene root's own path is
# the open document, not an instance, so the walk stops before it.
func _belongs_to_scene_instance(node: Node, scene_root: Node) -> bool:
	var current := node
	while current != null and current != scene_root:
		if not current.scene_file_path.is_empty():
			return true
		current = current.get_parent()
	return false


# Tier-15 contract section 2.1 (Godot): a property is an override when the
# instance's current value differs from the value the packed scene supplies for
# that node. The comparison runs on the wire encoding, so vector3 and colour
# dictionaries compare by content, with the same float exactness as
# manage_prefab's != on the raw engine values. A target with no pack
# counterpart — an added node, or a reference that failed to load — is never
# an override here.
func _is_property_override(property: String, target: Node, reference_node: Node) -> bool:
	if reference_node == null:
		return false
	return _read_value(property, target) != _read_value(property, reference_node)


# The reference node paired with target: the reference root itself for the
# instance root, the node at the same relative path otherwise — the same
# pairing manage_prefab's _corresponding_node uses.
func _reference_counterpart(reference: Node, instance_root: Node, target: Node) -> Node:
	if target == instance_root:
		return reference
	return reference.get_node_or_null(instance_root.get_path_to(target))


# Instantiates the source asset for value comparison, through the same
# GEN_EDIT_STATE_INSTANCE load path manage_prefab's _instantiate_reference
# uses, so the source values behind override_created and list_overrides come
# from the same place (Tier-15 contract section 4). On Godot what is shared is
# the reference path, not the diff walk: the walk treats root placement
# specially, and this predicate must not (section 5).
func _instantiate_reference(asset_path: String) -> Node:
	if not ResourceLoader.exists(asset_path):
		return null
	var packed := ResourceLoader.load(asset_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)


# Tier-3 contract section 4.1, the same resolution mutate_scene uses: liveness
# is validated at resolution time, so a deleted or undone node fails the
# ancestor check and is reported as stale.
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
	# as present here so required arguments reject it; unused arguments apply
	# their own empty-string tolerance at the use site (Tier-3 section 3).
	return arguments.has(key) and arguments[key] != null


func _error(code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"engine": "godot",
		"error_code": code,
		"error": message,
	}
