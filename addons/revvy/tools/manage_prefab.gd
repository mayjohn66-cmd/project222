@tool
extends RefCounted

# Tier-11 prefab override management (docs/design/tier11-prefab-overrides-contract.md).
# Lists, reverts, and applies the overrides an instanced PackedScene carries
# relative to its source .tscn, against the live edited scene. The descriptor
# is a shared artefact — it must be identical on every project and engine, so
# it is a pure literal.
#
# Godot mechanics, all measured in the Tier-11 probes:
#  - Enumeration diffs the live instance against a fresh reference instance of
#    the source pack (value comparison, so a property re-assigned to its pack
#    value is correctly not an override). SceneState was rejected: it reflects
#    the saved file, not the live instance (contract section 2.2).
#  - The instance root's placement (position, rotation, name) is never an
#    override, matching Unity's default-override classification (contract
#    section 2.1). The root's scale is not placement and stays reportable.
#  - Revert writes reference values back inside one EditorUndoRedoManager
#    action; apply flattens via PackedScene.pack + ResourceSaver.save and
#    reloads with CACHE_MODE_REPLACE against the measured cache poisoning.
#  - Godot persists child overrides only for editable instances (a file-format
#    rule), so writes that target nodes inside an instance enable editable on
#    the owning instance first and report it (contract section 8.2).

const ACTIONS := ["list_overrides", "revert", "apply"]
const KNOWN_ARGUMENTS := ["action", "target_id", "property"]
# Contract section 3: an argument the chosen action does not use is an error,
# never a silent ignore. revert may omit property (whole-instance revert).
const UNUSED_ARGUMENTS := {
	"list_overrides": ["property"],
	"revert": [],
	"apply": ["property"],
}
# The Tier-8 curated vocabulary revert accepts (contract section 5.1). The
# listing reports every override the diff finds, labelled with its raw engine
# property path; only the curated names are revertable.
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
# Engine property name to curated name. Node3D's stored `transform` is
# decomposed into position/rotation_degrees/scale for the diff, so those three
# engine names appear here instead of `transform`.
const ENGINE_TO_CURATED := {
	"position": "transform.position",
	"rotation_degrees": "transform.rotation",
	"scale": "transform.scale",
	"light_color": "light.color",
	"light_energy": "light.intensity",
	"omni_range": "light.range",
	"shadow_enabled": "light.shadows_enabled",
	"fov": "camera.field_of_view",
	"near": "camera.near_clip",
	"far": "camera.far_clip",
	"projection": "camera.orthographic",
}
# Framework properties that never carry gameplay meaning in an override
# listing. `transform` on a Node3D is handled decomposed; `name` is excluded
# only on the instance root (placement), at the diff site.
const FRAMEWORK_PROPERTIES := [
	"owner",
	"multiplayer",
	"unique_name_in_owner",
	"scene_file_path",
	"process_mode",
	"process_priority",
	"process_physics_priority",
	"process_thread_group",
	"process_thread_group_order",
	"process_thread_messages",
	"physics_interpolation_mode",
	"auto_translate_mode",
	"editor_description",
]
const APPLYABLE_EXTENSIONS := ["tscn", "scn"]

var _play_mode_tool = null


func _init(play_mode_tool = null) -> void:
	_play_mode_tool = play_mode_tool


func descriptor() -> Dictionary:
	return {
		"name": "manage_prefab",
		"description": "List, revert, or apply the overrides a prefab instance carries relative to its source asset.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"action": {
					"type": "string",
					"description": "Operation to perform.",
					"enum": ["list_overrides", "revert", "apply"],
				},
				"target_id": {
					"type": "string",
					"description": "Opaque ID of the prefab instance root, or of a node inside it, as returned by inspect_scene or mutate_scene.",
					"default": "",
				},
				"property": {
					"type": "string",
					"description": "For revert: engine-neutral property name from the curated vocabulary. Omit to revert every override on the instance.",
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
			},
			"required": ["action"],
			"additionalProperties": false,
		},
		"annotations": {
			"title": "Manage prefab overrides",
			"readOnlyHint": false,
			"destructiveHint": true,
			"idempotentHint": false,
			"openWorldHint": false,
			"readOnlyActions": ["list_overrides"],
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	# Contract section 10's validation order: schema (unknown arguments,
	# known-argument types), then action, then per-action argument presence,
	# then the property vocabulary, then the play-mode and edited-scene guards,
	# then target_id, then instance resolution, then applyability, then the
	# operation. Vocabulary validation precedes the guards for the same reason
	# Tier-8 section 8 gives: a misspelled property is a caller bug that
	# survives leaving play mode.
	for raw_key: Variant in arguments.keys():
		var key := str(raw_key)
		if key not in KNOWN_ARGUMENTS:
			return _error("invalid_argument", "Unknown argument '%s'." % key)
	for string_key: String in KNOWN_ARGUMENTS:
		if _is_present(arguments, string_key) and typeof(arguments[string_key]) != TYPE_STRING:
			return _error("invalid_argument", "%s must be a string." % string_key)

	var action_value: Variant = arguments.get("action", null)
	if action_value == null or (typeof(action_value) == TYPE_STRING and str(action_value).is_empty()):
		return _error("invalid_argument", "Argument 'action' is required.")
	var action := str(action_value)
	if action not in ACTIONS:
		return _error(
			"invalid_argument",
			"Unknown action '%s'. Expected one of: list_overrides, revert, apply." % action,
		)

	if not _is_present(arguments, "target_id") or str(arguments["target_id"]).is_empty():
		return _error("invalid_argument", "Argument 'target_id' is required for action '%s'." % action)
	for unused_key: String in UNUSED_ARGUMENTS[action]:
		if not _is_present(arguments, unused_key):
			continue
		if typeof(arguments[unused_key]) == TYPE_STRING and str(arguments[unused_key]).is_empty():
			continue
		return _error(
			"invalid_argument",
			"Argument '%s' is not used by action '%s'; omit it." % [unused_key, action],
		)

	# Contract section 5.1: revert accepts only the curated vocabulary. An
	# override whose engine property has no curated name is reverted through
	# execute_script, the documented escape hatch — the error names it rather
	# than leaving the caller guessing.
	var property := ""
	if action == "revert" and _is_present(arguments, "property") and not str(arguments["property"]).is_empty():
		property = str(arguments["property"])
		if property not in PROPERTY_TYPES:
			return _error(
				"invalid_argument",
				"Unknown property '%s'. Engine property paths are never accepted; expected one of the curated names: transform.position, transform.rotation, transform.scale, light.color, light.intensity, light.range, light.shadows_enabled, camera.field_of_view, camera.near_clip, camera.far_clip, camera.orthographic. To revert an override outside the curated vocabulary, use execute_script." % property,
			)

	# Every action, reads included, is refused while play mode is active or
	# entering/exiting — scene tools are edit-mode tools.
	if EditorInterface.is_playing_scene() or (
		_play_mode_tool != null and bool(_play_mode_tool.is_transitioning())
	):
		return _error(
			"play_mode_active",
			"Prefab override management is unavailable while play mode is active or transitioning.",
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

	# Contract section 6: the nearest instance root, always. The edited scene
	# root's own scene_file_path is the open document, not an instance, so the
	# walk stops before it (same rule as manage_properties).
	var instance_root := _nearest_instance_root(target, scene_root)
	if instance_root == null:
		return _error(
			"not_a_prefab_instance",
			"target_id '%s' identifies a node that is not part of any prefab instance." % target_id,
		)
	var asset_path := instance_root.scene_file_path
	if asset_path.is_empty():
		return _error(
			"ambiguous_prefab_target",
			"The nearest prefab instance root for target_id '%s' has no source asset path." % target_id,
		)

	match action:
		"list_overrides":
			return _list_overrides(target_id, instance_root, scene_root, asset_path)
		"revert":
			return _revert(target_id, property, target, instance_root, scene_root, asset_path)
		_:
			return _apply(target_id, instance_root, scene_root, asset_path)


# --- list_overrides ----------------------------------------------------------


func _list_overrides(target_id: String, instance_root: Node, scene_root: Node, asset_path: String) -> Dictionary:
	var enumeration: Dictionary = _enumerate_instance(instance_root, scene_root, asset_path)
	if enumeration.get("ok") != true:
		return enumeration.get("error", {})

	var property_overrides: Array = []
	for record: Dictionary in enumeration["records"]:
		property_overrides.append(_wire_override(record, scene_root))
	var added_objects: Array = []
	for added: Dictionary in enumeration["added"]:
		added_objects.append({
			"node_id": _node_id(added["node"]),
			"node_path": _display_path(added["node"], scene_root),
		})

	# For a read the field reports the instance's current editable state; the
	# bridge never turns it on for list_overrides (contract section 8.2).
	var holder := _editable_holder(instance_root, scene_root)
	var editable_now: bool = holder != null and holder.is_editable_instance(instance_root)
	return {
		"success": true,
		"engine": "godot",
		"action": "list_overrides",
		"target_id": target_id,
		"instance": {
			"root_id": _node_id(instance_root),
			"asset_path": asset_path,
			"status": "connected",
			"applyable": _is_applyable(asset_path),
		},
		"has_overrides": not property_overrides.is_empty() or not added_objects.is_empty(),
		"property_overrides": property_overrides,
		# Godot has neither components nor a removed-override concept; both
		# pairs of arrays are always present and always empty (sections 8.1).
		"added_components": [],
		"added_objects": added_objects,
		"removed_components": [],
		"removed_objects": [],
		"editable_enabled": editable_now,
	}


# --- revert ------------------------------------------------------------------


func _revert(
	target_id: String,
	property: String,
	target: Node,
	instance_root: Node,
	scene_root: Node,
	asset_path: String,
) -> Dictionary:
	var reference := _instantiate_reference(asset_path)
	if reference == null:
		return _error(
			"editor_api_failure",
			"The source scene '%s' could not be instantiated for comparison." % asset_path,
		)

	if not property.is_empty():
		return _revert_property(target_id, property, target, instance_root, scene_root, reference)
	return _revert_instance(target_id, instance_root, scene_root, reference)


# Contract section 9.2, scope "property": revert one curated property on the
# node the caller named. changed is false when there was no such override to
# revert; the call still succeeds and records no undo step.
func _revert_property(
	target_id: String,
	property: String,
	target: Node,
	instance_root: Node,
	scene_root: Node,
	reference: Node,
) -> Dictionary:
	var base := {
		"success": true,
		"engine": "godot",
		"action": "revert",
		"target_id": target_id,
		"property": property,
		"scope": "property",
	}

	# An added node has no pack counterpart, and a property whose component is
	# absent cannot be overridden; both are a changed:false no-op, never a
	# fabricated error.
	var reference_node := _corresponding_node(reference, instance_root, target)
	if reference_node == null or not _applies(property, target):
		reference.free()
		base["reverted_count"] = 0
		base["changed"] = false
		base["undoable"] = true
		base["editable_enabled"] = false
		return base

	var previous: Variant = _read_value(property, target)
	var source: Variant = _read_value(property, reference_node)
	if _to_engine_value(property, previous) == _to_engine_value(property, source):
		reference.free()
		base["reverted_count"] = 0
		base["previous_value"] = previous
		base["value"] = previous
		base["changed"] = false
		base["undoable"] = true
		base["editable_enabled"] = false
		return base

	# Contract section 8.2: a write targeting a node inside an instance enables
	# editable on the owning instance first, so the reverted state survives a
	# save. A root-property revert persists without it.
	var editable_enabled := _ensure_editable(target != instance_root, instance_root, scene_root)

	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy revert prefab override")
	if property == "camera.orthographic":
		var new_projection := Camera3D.PROJECTION_ORTHOGONAL if source else Camera3D.PROJECTION_PERSPECTIVE
		var old_projection := Camera3D.PROJECTION_ORTHOGONAL if previous else Camera3D.PROJECTION_PERSPECTIVE
		undo_redo.add_do_property(target, "projection", new_projection)
		undo_redo.add_undo_property(target, "projection", old_projection)
	else:
		var engine_property: String = _engine_property_for(property)
		undo_redo.add_do_property(target, engine_property, _to_engine_value(property, source))
		undo_redo.add_undo_property(target, engine_property, _to_engine_value(property, previous))
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	reference.free()

	base["reverted_count"] = 1
	base["previous_value"] = previous
	base["value"] = _read_value(property, target)
	base["changed"] = true
	base["undoable"] = true
	base["editable_enabled"] = editable_enabled
	return base


# Contract section 9.2, scope "instance": revert every override the diff
# finds — property overrides and added nodes together — inside one undo
# action, so a single editor undo restores all of them.
func _revert_instance(target_id: String, instance_root: Node, scene_root: Node, reference: Node) -> Dictionary:
	var enumeration: Dictionary = _enumerate_with_reference(instance_root, scene_root, reference)
	var records: Array = enumeration["records"]
	var added: Array = enumeration["added"]

	if records.is_empty() and added.is_empty():
		reference.free()
		return {
			"success": true,
			"engine": "godot",
			"action": "revert",
			"target_id": target_id,
			"scope": "instance",
			"reverted_count": 0,
			"changed": false,
			"undoable": true,
			"editable_enabled": false,
		}

	var touches_children := not added.is_empty()
	for record: Dictionary in records:
		if record["node"] != instance_root:
			touches_children = true
			break
	var editable_enabled := _ensure_editable(touches_children, instance_root, scene_root)

	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Revvy revert prefab instance")
	for record: Dictionary in records:
		undo_redo.add_do_property(record["node"], record["engine_property"], record["source_value"])
		undo_redo.add_undo_property(record["node"], record["engine_property"], record["live_value"])
	for entry: Dictionary in added:
		var added_node: Node = entry["node"]
		var parent := added_node.get_parent()
		var previous_owner: Node = added_node.owner
		undo_redo.add_do_method(parent, "remove_child", added_node)
		undo_redo.add_undo_method(parent, "add_child", added_node)
		if previous_owner != null:
			undo_redo.add_undo_method(added_node, "set_owner", previous_owner)
		# The node is never freed: the do-reference keeps it alive so undo restores it.
		undo_redo.add_do_reference(added_node)
	undo_redo.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	reference.free()

	return {
		"success": true,
		"engine": "godot",
		"action": "revert",
		"target_id": target_id,
		"scope": "instance",
		"reverted_count": records.size() + added.size(),
		"changed": true,
		"undoable": true,
		"editable_enabled": editable_enabled,
	}


# --- apply -------------------------------------------------------------------


# Contract section 7: apply flattens the live instance over its source asset
# on disk and is declared non-undoable. Matching Unity, the root's placement
# (position, rotation, name) is not applied — it belongs to the outer scene,
# not the asset — so the pack is taken while the root temporarily carries the
# source values, then the live values are restored. The root's scale is not
# placement and is applied.
func _apply(target_id: String, instance_root: Node, scene_root: Node, asset_path: String) -> Dictionary:
	if not _is_applyable(asset_path):
		return _error(
			"prefab_not_applyable",
			"The source asset '%s' is not a text or binary scene this bridge can rewrite." % asset_path,
		)

	var reference := _instantiate_reference(asset_path)
	if reference == null:
		return _error(
			"editor_api_failure",
			"The source scene '%s' could not be instantiated for comparison." % asset_path,
		)
	var enumeration: Dictionary = _enumerate_with_reference(instance_root, scene_root, reference)
	var applied_count: int = enumeration["records"].size() + enumeration["added"].size()

	var live_name := str(instance_root.name)
	var live_position := Vector3.ZERO
	var live_rotation := Vector3.ZERO
	var has_3d_root := instance_root is Node3D
	if has_3d_root:
		live_position = (instance_root as Node3D).position
		live_rotation = (instance_root as Node3D).rotation

	var pack_source := PackedScene.new()
	instance_root.set_name(str(reference.name))
	if has_3d_root and reference is Node3D:
		(instance_root as Node3D).position = (reference as Node3D).position
		(instance_root as Node3D).rotation = (reference as Node3D).rotation
	var pack_error: Error = pack_source.pack(instance_root)
	instance_root.set_name(live_name)
	if has_3d_root:
		(instance_root as Node3D).position = live_position
		(instance_root as Node3D).rotation = live_rotation
	reference.free()
	if pack_error != OK:
		return _error(
			"editor_api_failure",
			"PackedScene.pack() failed with error %d while applying to '%s'." % [pack_error, asset_path],
		)

	var save_error: Error = ResourceSaver.save(pack_source, asset_path)
	if save_error != OK:
		return _error(
			"editor_api_failure",
			"ResourceSaver.save() failed with error %d while writing '%s'." % [save_error, asset_path],
		)
	# The probes measured same-process cache poisoning on reload after a save;
	# CACHE_MODE_REPLACE makes the editor's next load see the file just written.
	ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REPLACE)

	return {
		"success": true,
		"engine": "godot",
		"action": "apply",
		"target_id": target_id,
		"instance": {
			"root_id": _node_id(instance_root),
			"asset_path": asset_path,
		},
		"applied_count": applied_count,
		# Contract section 7: treat apply as permanent; Godot's apply is a plain
		# ResourceSaver.save with no undo integration at all.
		"undoable": false,
		"editable_enabled": false,
	}


# --- enumeration -------------------------------------------------------------


# Instantiates the source asset for value comparison. GEN_EDIT_STATE_INSTANCE
# keeps the internal ownership shape identical to an editor-created instance,
# which the added-node detection relies on.
func _instantiate_reference(asset_path: String) -> Node:
	if not ResourceLoader.exists(asset_path):
		return null
	var packed := ResourceLoader.load(asset_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)


func _enumerate_instance(instance_root: Node, scene_root: Node, asset_path: String) -> Dictionary:
	var reference := _instantiate_reference(asset_path)
	if reference == null:
		return {
			"ok": false,
			"error": _error(
				"editor_api_failure",
				"The source scene '%s' could not be instantiated for comparison." % asset_path,
			),
		}
	var result := _enumerate_with_reference(instance_root, scene_root, reference)
	reference.free()
	result["ok"] = true
	return result


# Diffs the live instance against the reference node-pair-wise. Returns raw
# engine records (node, engine_property, live_value, source_value) plus the
# added-node list; wire shaping happens at the result sites.
func _enumerate_with_reference(instance_root: Node, scene_root: Node, reference: Node) -> Dictionary:
	var records: Array = []
	var added: Array = []
	_diff_pair(instance_root, reference, instance_root, true, records, added)
	return {"records": records, "added": added}


func _diff_pair(
	live: Node,
	reference: Node,
	boundary: Node,
	is_root: bool,
	records: Array,
	added: Array,
) -> void:
	# Node3D's stored `transform` is decomposed so each component maps onto the
	# curated vocabulary. On the instance root only scale is compared: position
	# and rotation are placement, matching Unity's default-override exclusion.
	if live is Node3D and reference is Node3D:
		if not is_root:
			_record_if_different(records, live, reference, "position")
			_record_if_different(records, live, reference, "rotation_degrees")
		_record_if_different(records, live, reference, "scale")

	for info: Dictionary in live.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var prop := str(info["name"])
		if prop in FRAMEWORK_PROPERTIES:
			continue
		if is_root and prop == "name":
			# The root's name is placement in the outer scene, like its position.
			continue
		if live is Node3D and prop == "transform":
			continue
		var live_value: Variant = live.get(prop)
		var reference_value: Variant = reference.get(prop)
		if live_value != reference_value:
			records.append({
				"node": live,
				"engine_property": prop,
				"live_value": live_value,
				"source_value": reference_value,
			})

	# Children. A child belongs to the pack when its owner is the boundary
	# node; any other owner (the outer scene root, another node, or none) means
	# the instance gained a node the source does not have.
	var reference_by_name := {}
	var reference_unmatched: Array = []
	for reference_child: Node in reference.get_children():
		reference_by_name[str(reference_child.name)] = reference_child
		reference_unmatched.append(reference_child)
	var deferred: Array = []
	for live_child: Node in live.get_children():
		if live_child.owner != boundary:
			added.append({"node": live_child})
			continue
		var key := str(live_child.name)
		if reference_by_name.has(key):
			var matched: Node = reference_by_name[key]
			reference_unmatched.erase(matched)
			_diff_children(live_child, matched, boundary, records, added)
		else:
			deferred.append(live_child)
	# A renamed pack child no longer matches by name; pair the leftovers in
	# tree order. Live pack children beyond that have no source counterpart and
	# are honestly reported as added.
	for index: int in range(mini(deferred.size(), reference_unmatched.size())):
		_diff_children(deferred[index], reference_unmatched[index], boundary, records, added)
	for index: int in range(reference_unmatched.size(), deferred.size()):
		added.append({"node": deferred[index]})


func _diff_children(live: Node, reference: Node, parent_boundary: Node, records: Array, added: Array) -> void:
	# A child that is itself an instance root owns its own pack children, so
	# the ownership boundary moves to it for the next level down.
	var boundary := parent_boundary
	if not live.scene_file_path.is_empty():
		boundary = live
	_diff_pair(live, reference, boundary, false, records, added)


func _record_if_different(records: Array, live: Node, reference: Node, prop: String) -> void:
	var live_value: Variant = live.get(prop)
	var reference_value: Variant = reference.get(prop)
	if live_value != reference_value:
		records.append({
			"node": live,
			"engine_property": prop,
			"live_value": live_value,
			"source_value": reference_value,
		})


# --- result shaping ------------------------------------------------------------


func _wire_override(record: Dictionary, scene_root: Node) -> Dictionary:
	var node: Node = record["node"]
	var engine_property := str(record["engine_property"])
	var curated := _curated_for(engine_property, node)
	var instance_value: Variant
	var source_value: Variant
	if curated.is_empty():
		# Non-curated overrides stay informational: raw values are normalised
		# to JSON-safe shapes rather than dropped (contract section 5.1).
		instance_value = _json_safe(record["live_value"])
		source_value = _json_safe(record["source_value"])
	else:
		instance_value = _to_wire_value(curated, record["live_value"], engine_property)
		source_value = _to_wire_value(curated, record["source_value"], engine_property)
	return {
		"node_id": _node_id(node),
		"node_path": _display_path(node, scene_root),
		"property": null if curated.is_empty() else curated,
		"engine_property": engine_property,
		"instance_value": instance_value,
		"source_value": source_value,
		# revertable is false exactly when property is null, so a caller can
		# filter without re-deriving the rule.
		"revertable": not curated.is_empty(),
	}


func _curated_for(engine_property: String, node: Node) -> String:
	var curated: String = ENGINE_TO_CURATED.get(engine_property, "")
	if curated.is_empty():
		return ""
	if not _applies(curated, node):
		return ""
	return curated


func _engine_property_for(property: String) -> String:
	for engine_property: String in ENGINE_TO_CURATED:
		if ENGINE_TO_CURATED[engine_property] == property:
			return engine_property
	return ""


func _json_safe(value: Variant) -> Variant:
	var value_type := typeof(value)
	if value_type in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return value
	if value_type in [TYPE_STRING_NAME, TYPE_NODE_PATH]:
		return str(value)
	if value_type == TYPE_ARRAY:
		var out: Array = []
		for element: Variant in value:
			out.append(_json_safe(element))
		return out
	if value_type == TYPE_DICTIONARY:
		var out := {}
		for key: Variant in value:
			out[str(key)] = _json_safe(value[key])
		return out
	# Packed arrays, math types, Resources, and anything else: the string form
	# is honest and always JSON-safe.
	return str(value)


# --- Tier-8 curated value model (kept identical to manage_properties) ---------


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


func _read_value(property: String, target: Node) -> Variant:
	if property == "camera.orthographic":
		return (target as Camera3D).projection == Camera3D.PROJECTION_ORTHOGONAL
	var engine_value: Variant = target.get(_engine_property_for(property))
	return _to_wire_value(property, engine_value, _engine_property_for(property))


func _to_wire_value(property: String, engine_value: Variant, engine_property: String) -> Variant:
	if engine_property == "projection":
		return engine_value == Camera3D.PROJECTION_ORTHOGONAL
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


# --- shared helpers ------------------------------------------------------------


func _is_applyable(asset_path: String) -> bool:
	return asset_path.get_extension().to_lower() in APPLYABLE_EXTENSIONS


func _nearest_instance_root(node: Node, scene_root: Node) -> Node:
	var current := node
	while current != null and current != scene_root:
		if not current.scene_file_path.is_empty():
			return current
		current = current.get_parent()
	return null


# The editable flag lives on the instance root's owner (the edited scene root
# for a top-level instance, the outer instance root for a nested one).
func _editable_holder(instance_root: Node, scene_root: Node) -> Node:
	if instance_root.owner != null:
		return instance_root.owner
	return scene_root


# Contract section 8.2: returns true only when this call actually turned the
# flag on; an already-editable instance reports false.
func _ensure_editable(needed: bool, instance_root: Node, scene_root: Node) -> bool:
	if not needed:
		return false
	var holder := _editable_holder(instance_root, scene_root)
	if holder == null or holder.is_editable_instance(instance_root):
		return false
	holder.set_editable_instance(instance_root, true)
	return true


func _corresponding_node(reference: Node, instance_root: Node, target: Node) -> Node:
	if target == instance_root:
		return reference
	return reference.get_node_or_null(instance_root.get_path_to(target))


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


func _node_id(node: Node) -> String:
	return "godot:%d" % node.get_instance_id()


func _display_path(node: Node, scene_root: Node) -> String:
	if node == scene_root:
		return "/" + str(scene_root.name)
	return "/%s/%s" % [scene_root.name, scene_root.get_path_to(node)]


func _is_present(arguments: Dictionary, key: String) -> bool:
	# Absent means omitted or JSON null. An explicit empty string still counts
	# as present here so required arguments reject it; the unused-argument and
	# vocabulary checks apply their own empty-string tolerance at the use site.
	return arguments.has(key) and arguments[key] != null


func _error(code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"engine": "godot",
		"error_code": code,
		"error": message,
	}
