@tool
extends RefCounted

const DEFAULT_MAX_DIMENSION := 1024
const MIN_MAX_DIMENSION := 64
const MAX_MAX_DIMENSION := 4096
const ALLOWED_ARGUMENTS := ["max_dimension", "inline"]

# Captures live at <project>/.revvy/captures. The dot-folder is outside
# Godot's asset database — the editor's filesystem scan skips it, so a capture
# never triggers an import (an import would be an editor state change). Names
# are viewport-<UTC>-<counter>.png and sort chronologically as plain strings.
const CAPTURE_DIR := ".revvy/captures"
const CAPTURE_NAME_PREFIX := "viewport-"
# Rotation keeps at most MAX_CAPTURES files; before each write the oldest
# viewport-*.png files are deleted until MAX_CAPTURES - 1 remain. A single PNG
# may never exceed MAX_CAPTURE_BYTES: an oversized encode is refused with
# capture_too_large instead of being silently re-encoded.
const MAX_CAPTURES := 20
const MAX_CAPTURE_BYTES := 4 * 1024 * 1024
# Tier-10 §5: inline images get a separate, lower cap than the file — base64
# inflates by 4/3 and the bytes cross the MCP transport into a model's context
# rather than sitting on disk. An inline request over the cap fails with
# capture_too_large before the file is written, leaving no capture behind.
const MAX_INLINE_BYTES := 1024 * 1024


func descriptor() -> Dictionary:
	# Tier-10 §3: inline is appended after max_dimension, so a Tier-6 client's
	# view of the first property is byte-identical; everything else matches the
	# Tier-6 descriptor unchanged.
	return {
		"name": "capture_viewport",
		"description": "Capture the editor viewport of the currently edited scene to a PNG file inside the project and return its path.",
		"inputSchema": {
			"type": "object",
			"properties": {
				"max_dimension": {
					"type": "integer",
					"description": "Maximum length of the longer image edge in pixels. The capture is downscaled to fit, preserving aspect ratio; it is never upscaled.",
					"minimum": MIN_MAX_DIMENSION,
					"maximum": MAX_MAX_DIMENSION,
					"default": DEFAULT_MAX_DIMENSION,
				},
				"inline": {
					"type": "boolean",
					"description": "Also return the PNG as a base64 image content block so the caller can see it without reading the file. Subject to a smaller size limit than the file.",
					"default": false,
				},
			},
			"additionalProperties": false,
		},
		"annotations": {
			"title": "Capture viewport",
			"readOnlyHint": true,
			"destructiveHint": false,
			"idempotentHint": true,
			"openWorldHint": false,
		},
	}


func invoke(arguments: Dictionary) -> Dictionary:
	# Argument validation runs before every environment guard (tier-6 contract
	# section 4): a caller bug is reported before an environment problem, and
	# bounds stay testable on a headless machine.
	for raw_key: Variant in arguments.keys():
		var key := str(raw_key)
		if key not in ALLOWED_ARGUMENTS:
			return _error("invalid_argument", "Unknown argument '%s'." % key)

	var dimension_result := _bounded_integer(
		arguments, "max_dimension", DEFAULT_MAX_DIMENSION, MIN_MAX_DIMENSION, MAX_MAX_DIMENSION
	)
	if not bool(dimension_result.get("success", false)):
		return dimension_result
	var max_dimension := int(dimension_result["value"])

	# Tier-10: inline is a strict boolean — absent means false, and anything
	# that is not a JSON boolean is a caller bug reported as invalid_argument
	# before every environment guard, exactly like the schema bounds above.
	var inline_result := _optional_boolean(arguments, "inline", false)
	if not bool(inline_result.get("success", false)):
		return inline_result
	var inline := bool(inline_result["value"])

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _error("no_edited_scene", "There is no currently edited scene.")

	# Headless runs render through a stub backend: the viewport texture exists
	# but can never contain real pixels. The contract refuses rather than
	# returning a blank placeholder, and writes no file.
	var renderer := _renderer_info()
	if bool(renderer.get("headless", false)):
		return _error(
			"viewport_unavailable",
			"The editor has no graphics device (running headless), so no real pixels can be captured.",
			{"renderer": renderer},
		)

	var viewport: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if viewport == null:
		return _error(
			"viewport_unavailable",
			"The editor has no 3D viewport open, so no pixels can be captured.",
			{"renderer": renderer},
		)

	var viewport_texture: ViewportTexture = viewport.get_texture()
	var image: Image = viewport_texture.get_image() if viewport_texture != null else null
	if image == null or image.is_empty():
		return _error("editor_api_failure", "The editor viewport texture could not be read back.")

	var width := image.get_width()
	var height := image.get_height()
	_downscale(image, max_dimension)
	var saved_width := image.get_width()
	var saved_height := image.get_height()

	var buffer: PackedByteArray = image.save_png_to_buffer()
	if buffer.is_empty():
		return _error("editor_api_failure", "Encoding the capture as PNG failed.")
	if buffer.size() > MAX_CAPTURE_BYTES:
		return _error(
			"capture_too_large",
			"The encoded PNG is %d bytes, over the %d-byte limit; lower max_dimension." % [buffer.size(), MAX_CAPTURE_BYTES],
		)
	# Tier-10 §5/§7: the inline cap is lower than the file cap and is checked
	# after the file size check and before the write, so an oversized inline
	# request leaves no capture behind and consumes no rotation slot.
	if inline and buffer.size() > MAX_INLINE_BYTES:
		return _error(
			"capture_too_large",
			"The encoded PNG is %d bytes, over the %d-byte inline image limit; lower max_dimension or drop inline." % [buffer.size(), MAX_INLINE_BYTES],
		)

	var directory_absolute: String = ProjectSettings.globalize_path("res://").path_join(CAPTURE_DIR)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory_absolute)
	if directory_error != OK and not DirAccess.dir_exists_absolute(directory_absolute):
		return _error("editor_api_failure", "Could not create the captures directory (error %d)." % directory_error)

	_rotate_captures(directory_absolute)

	var file_name := _next_capture_name(directory_absolute)
	var file_absolute := directory_absolute.path_join(file_name)
	var capture_file := FileAccess.open(file_absolute, FileAccess.WRITE)
	if capture_file == null:
		return _error("editor_api_failure", "Could not open the capture file for writing (error %d)." % FileAccess.get_open_error())
	capture_file.store_buffer(buffer)
	capture_file.close()

	var payload := {
		"success": true,
		"engine": "godot",
		"format": "png",
		"file_path": CAPTURE_DIR.path_join(file_name),
		"byte_length": buffer.size(),
		"width": width,
		"height": height,
		"saved_width": saved_width,
		"saved_height": saved_height,
		"max_dimension": max_dimension,
		"downscaled": saved_width != width or saved_height != height,
		# Capturing is allowed during play mode (tier-6 contract section 5): a
		# screenshot is read-only and conflates no object graphs, unlike
		# inspect_scene/mutate_scene. play_mode tells the caller which world it
		# is looking at.
		"play_mode": EditorInterface.is_playing_scene(),
		# Tier-10 §6: inline echoes what the caller asked for, so a result is
		# self-describing without correlating it against the request.
		"inline": inline,
		"renderer": renderer,
		"scene": {
			"name": str(scene_root.name),
			"path": scene_root.scene_file_path,
			"saved": not scene_root.scene_file_path.is_empty(),
		},
	}
	if inline:
		# Tier-10 §4/§11: the base64 is encoded from the same PackedByteArray
		# that was just written to disk, so the inline data cannot drift from
		# the file. The server lifts _content_blocks out of the payload before
		# serializing the text block, so the image is carried once as its own
		# content block and never duplicated into the text block's JSON.
		payload["_content_blocks"] = [
			{
				"type": "image",
				"mimeType": "image/png",
				"data": Marshalls.raw_to_base64(buffer),
			},
		]
	return payload


func _renderer_info() -> Dictionary:
	var headless := _is_headless()
	return {
		"mode": "dummy" if headless else "real",
		"device": RenderingServer.get_current_rendering_driver_name(),
		"headless": headless,
	}


# The headless display server reports its own name. OS.has_feature("headless")
# is kept as a second signal for dedicated headless builds, and the dummy
# driver name covers rigs that stub the renderer without either.
func _is_headless() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if OS.has_feature("headless"):
		return true
	return RenderingServer.get_current_rendering_driver_name() == "dummy"


# The capture is downscaled on its long edge, preserving aspect ratio, and is
# never upscaled: a viewport smaller than max_dimension saves at native size.
func _downscale(image: Image, max_dimension: int) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var long_edge: int = maxi(width, height)
	if long_edge <= max_dimension:
		return
	var scale := float(max_dimension) / float(long_edge)
	var new_width: int = maxi(1, int(round(float(width) * scale)))
	var new_height: int = maxi(1, int(round(float(height) * scale)))
	image.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)


# Names carry a UTC second stamp plus a zero-padded counter that makes them
# unique within the second, so every capture keeps its own file and the plain
# string sort is chronological.
func _next_capture_name(directory_absolute: String) -> String:
	var now := Time.get_datetime_dict_from_system(true)
	var stamp := "%04d%02d%02dT%02d%02d%02dZ" % [
		int(now["year"]), int(now["month"]), int(now["day"]),
		int(now["hour"]), int(now["minute"]), int(now["second"]),
	]
	var counter := 0
	while true:
		var file_name := "%s%s-%03d.png" % [CAPTURE_NAME_PREFIX, stamp, counter]
		if not FileAccess.file_exists(directory_absolute.path_join(file_name)):
			return file_name
		counter += 1
	return ""


# Rotation keeps the newest MAX_CAPTURES captures: before a write, the oldest
# are deleted until MAX_CAPTURES - 1 remain. Only viewport-*.png files are
# ever removed, so an unrelated file dropped in the directory is untouched.
func _rotate_captures(directory_absolute: String) -> void:
	var directory := DirAccess.open(directory_absolute)
	if directory == null:
		return
	var names: Array[String] = []
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if not directory.current_is_dir() and entry.begins_with(CAPTURE_NAME_PREFIX) and entry.ends_with(".png"):
			names.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	# UTC stamps are fixed-width, so a lexical sort is chronological.
	names.sort()
	while names.size() > MAX_CAPTURES - 1:
		directory.remove(names[0])
		names.remove_at(0)


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


# A strict boolean: absent binds the default, a JSON boolean is taken as-is,
# and anything else is invalid_argument rather than silently coerced.
func _optional_boolean(arguments: Dictionary, key: String, default_value: bool) -> Dictionary:
	var raw_value: Variant = arguments.get(key, default_value)
	if typeof(raw_value) != TYPE_BOOL:
		return _error("invalid_argument", "%s must be a boolean." % key)
	return {"success": true, "value": raw_value}


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
