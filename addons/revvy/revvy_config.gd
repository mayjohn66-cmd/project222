@tool
extends RefCounted

const DEFAULT_EDITOR_PORT := 8088
const DEFAULT_PROXY_PORT := 8089
const CONFIG_FILENAME := "revvy-proxy.json"
const MANIFEST_FILENAME := "tools-manifest.json"


static func resolve_editor_port() -> int:
	var raw_port: String = OS.get_environment("REVVY_EDITOR_PORT").strip_edges()
	if raw_port.is_valid_int():
		var port: int = raw_port.to_int()
		if port >= 1 and port <= 65535:
			return port
	var read_result: Dictionary = _read_json_dictionary(resolve_config_path())
	if read_result.get("error", FAILED) == OK:
		var config: Dictionary = read_result.get("value", {})
		if _runtime_config_matches_current_project(config):
			# Godot's JSON parser represents every JSON number as TYPE_FLOAT, so
			# retain the source text and lex the top-level port field before handing
			# it to the integer-only validator. This rejects 8088.0 and 8.088e3
			# without also rejecting the valid JSON integer 8088.
			var source_text: String = str(read_result.get("source_text", ""))
			var configured_port: int = _configured_port(
				_strict_top_level_json_integer(source_text, "ue_port")
			)
			if configured_port != 0:
				return configured_port
	return DEFAULT_EDITOR_PORT


static func _runtime_config_matches_current_project(config: Dictionary) -> bool:
	if str(config.get("port_scope", "")).strip_edges().to_lower() != "project":
		return false
	return _runtime_config_identity_matches_current_project(config)


static func _runtime_config_identity_matches_current_project(config: Dictionary) -> bool:
	if str(config.get("engine", "")).strip_edges().to_lower() != "godot":
		return false

	var current_project: String = current_project_path()
	if _same_project_path(config.get("project_path", null), current_project):
		return true
	for field: String in ["installed_project", "active_project"]:
		if _project_object_matches_current_project(config, field):
			return true
	return false


static func _project_object_matches_current_project(config: Dictionary, field: String) -> bool:
	var project: Variant = config.get(field, null)
	return (
		typeof(project) == TYPE_DICTIONARY
		and _same_project_path(project.get("path", null), current_project_path())
	)


static func _sanitize_existing_project_ownership(config: Dictionary) -> bool:
	var current_project_owned: bool = _runtime_config_identity_matches_current_project(config)
	if not current_project_owned:
		# Snapshot ownership before the writer replaces engine/project identity.
		# A copied file must not turn its foreign pair, installer record, or
		# credentials into a durable allocation for the open project.
		for field: String in [
			"port_scope",
			"proxy_port",
			"installed_project",
			"active_project",
			"bearer_token",
			"bearer_scope",
			"backend_auth",
			"full_access_token",
			"bridge_instance_id",
			"bridge_running",
		]:
			config.erase(field)
		return false

	# A matching active/project path does not make a conflicting installer
	# record trustworthy. Preserve that field only when it independently owns
	# this project; unrelated unknown fields remain untouched.
	if config.has("installed_project") and not _project_object_matches_current_project(config, "installed_project"):
		config.erase("installed_project")
	return true


static func _configured_port(value: Variant) -> int:
	if typeof(value) != TYPE_INT:
		return 0
	var port: int = value
	return port if port >= 1 and port <= 65535 else 0


static func _strict_top_level_json_integer(text: String, field: String) -> Variant:
	var depth := 0
	var index := 0
	var found := false
	var found_value := 0
	while index < text.length():
		var character: String = text.substr(index, 1)
		if character == '"':
			var string_end: int = _json_string_end(text, index)
			if string_end < 0:
				return null
			if depth == 1:
				var cursor: int = _skip_json_whitespace(text, string_end + 1)
				if cursor < text.length() and text.substr(cursor, 1) == ":":
					var parsed_key: Variant = JSON.parse_string(text.substr(index, string_end - index + 1))
					if parsed_key == field:
						if found:
							return null
						cursor = _skip_json_whitespace(text, cursor + 1)
						var value_start: int = cursor
						if cursor < text.length() and text.substr(cursor, 1) == "-":
							cursor += 1
						var digit_start: int = cursor
						while cursor < text.length() and text.substr(cursor, 1).is_valid_int():
							cursor += 1
						if cursor == digit_start:
							return null
						var token_end: int = cursor
						cursor = _skip_json_whitespace(text, cursor)
						if cursor >= text.length() or text.substr(cursor, 1) not in [",", "}"]:
							return null
						found_value = text.substr(value_start, token_end - value_start).to_int()
						found = true
			index = string_end + 1
			continue
		if character == "{" or character == "[":
			depth += 1
		elif character == "}" or character == "]":
			depth -= 1
		index += 1
	return found_value if found else null


static func _json_string_end(text: String, opening_quote: int) -> int:
	var escaped := false
	for index: int in range(opening_quote + 1, text.length()):
		var character: String = text.substr(index, 1)
		if escaped:
			escaped = false
		elif character == "\\":
			escaped = true
		elif character == '"':
			return index
	return -1


static func _skip_json_whitespace(text: String, start: int) -> int:
	var index: int = start
	while index < text.length() and text.substr(index, 1) in [" ", "\t", "\r", "\n"]:
		index += 1
	return index


static func _same_project_path(candidate: Variant, current_project: String) -> bool:
	if typeof(candidate) != TYPE_STRING:
		return false
	var canonical_candidate: String = _canonicalize_project_path(str(candidate))
	var canonical_current: String = _canonicalize_project_path(current_project)
	if canonical_candidate.is_empty() or canonical_current.is_empty():
		return false
	if OS.get_name() == "Windows":
		return canonical_candidate.to_lower() == canonical_current.to_lower()
	return canonical_candidate == canonical_current


static func resolve_state_directory() -> String:
	var override_path: String = OS.get_environment("REVVY_STATE_DIR").strip_edges()
	if not override_path.is_empty():
		return _absolute_override_path(override_path)
	return _project_path().path_join(".revvy")


static func resolve_config_path() -> String:
	var override_path: String = OS.get_environment("REVVY_CONFIG").strip_edges()
	if not override_path.is_empty():
		return _absolute_override_path(override_path)
	return resolve_state_directory().path_join(CONFIG_FILENAME)


static func resolve_manifest_path() -> String:
	return resolve_state_directory().path_join(MANIFEST_FILENAME)


static func write_runtime_config(editor_port: int, bridge_instance_id: String) -> Error:
	var config_path: String = resolve_config_path()
	var read_result: Dictionary = _read_json_dictionary(config_path)
	var read_error: Error = read_result.get("error", FAILED)
	if read_error != OK:
		return read_error

	var config: Dictionary = read_result.get("value", {})
	var source_text: String = str(read_result.get("source_text", ""))
	var current_project_owned: bool = _sanitize_existing_project_ownership(config)
	var project_path: String = _project_path()
	var project_name: String = str(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
	if project_name.is_empty():
		project_name = project_path.get_file()

	var engine_version: String = str(Engine.get_version_info().get("string", "unknown"))
	var bearer_token: String = str(config.get("bearer_token", ""))
	if bearer_token.length() < 32:
		bearer_token = Crypto.new().generate_random_bytes(32).hex_encode()

	var proxy_port := 0
	if current_project_owned:
		proxy_port = _configured_port(
			_strict_top_level_json_integer(source_text, "proxy_port")
		)
	if proxy_port == 0:
		proxy_port = DEFAULT_PROXY_PORT

	config["config_version"] = 3
	config["engine"] = "godot"
	config["engine_version"] = engine_version
	config["bridge_instance_id"] = bridge_instance_id
	config["project_name"] = project_name
	config["project_path"] = project_path
	config["active_project"] = {"name": project_name, "path": project_path}
	config["bearer_token"] = bearer_token
	config["bearer_scope"] = "read_only"
	config["proxy_port"] = proxy_port
	config["ue_port"] = editor_port
	config["updated_at"] = Time.get_datetime_string_from_system(true) + "Z"

	return _atomic_write_json(config_path, config)


static func write_tools_manifest(tool_descriptors: Array) -> Error:
	return _atomic_write_json(resolve_manifest_path(), tool_descriptors)


static func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": OK, "value": {}}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "value": {}}

	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var text: String = _decode_json_text(bytes)
	if text.is_empty() and not bytes.is_empty():
		return {"error": ERR_PARSE_ERROR, "value": {}}

	var parser := JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"error": ERR_PARSE_ERROR, "value": {}}

	return {"error": OK, "value": parser.data, "source_text": text}


static func _decode_json_text(bytes: PackedByteArray) -> String:
	if bytes.size() >= 2:
		var has_utf16_bom: bool = (
			(bytes[0] == 0xff and bytes[1] == 0xfe)
			or (bytes[0] == 0xfe and bytes[1] == 0xff)
		)
		if has_utf16_bom:
			return bytes.get_string_from_utf16()

	if bytes.size() >= 3 and bytes[0] == 0xef and bytes[1] == 0xbb and bytes[2] == 0xbf:
		return bytes.slice(3).get_string_from_utf8()

	return bytes.get_string_from_utf8()


static func _atomic_write_json(path: String, value: Variant) -> Error:
	var directory: String = path.get_base_dir()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK and not DirAccess.dir_exists_absolute(directory):
		return directory_error

	var temporary_path: String = directory.path_join(
		".%s.%d.%d.tmp" % [path.get_file(), OS.get_process_id(), Time.get_ticks_msec()]
	)
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(value, "  ", true) + "\n")
	file.flush()
	file.close()

	var rename_error: Error = DirAccess.rename_absolute(temporary_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
	return rename_error


static func _absolute_override_path(path: String) -> String:
	var expanded: String = _expand_user(path)
	if expanded.begins_with("res://") or expanded.begins_with("user://"):
		return ProjectSettings.globalize_path(expanded)
	if expanded.is_absolute_path():
		return expanded
	return current_project_path().path_join(expanded)


static func _expand_user(path: String) -> String:
	if path == "~":
		return OS.get_environment("HOME")
	if path.begins_with("~/") or path.begins_with("~\\"):
		return OS.get_environment("HOME").path_join(path.substr(2))
	return path


static func current_project_path() -> String:
	return _canonicalize_project_path(ProjectSettings.globalize_path("res://"))


static func _canonicalize_project_path(value: String) -> String:
	var path: String = _expand_user(value.strip_edges())
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	path = path.simplify_path().replace("\\", "/")
	while path.length() > 1 and path.ends_with("/"):
		# Preserve Windows drive roots such as C:/.
		if path.length() == 3 and path.substr(1, 1) == ":":
			break
		path = path.substr(0, path.length() - 1)
	return path


static func _project_path() -> String:
	return current_project_path()
