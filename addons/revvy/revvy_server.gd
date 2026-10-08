@tool
extends RefCounted

const CONFIG_SCRIPT := preload("res://addons/revvy/revvy_config.gd")
const ENDPOINT_PATH := "/mcp"
const HEALTH_PATH := "/health"
const MAX_HEADER_BYTES := 64 * 1024
const MAX_BODY_BYTES := 8 * 1024 * 1024
const REQUEST_TIMEOUT_MSEC := 120_000
const SUPPORTED_PROTOCOL_VERSIONS := ["2025-11-25", "2025-06-18", "2024-11-05"]
const BRIDGE_AUTH_ALGORITHM := "hmac-sha1-exact-v2"
const BRIDGE_SIGNATURE_VERSION := "v2"
const ALLOWED_CLOCK_SKEW_SECONDS := 30
const REPLAY_RETENTION_SECONDS := 60

var _listener: TCPServer = TCPServer.new()
var _clients: Array[Dictionary] = []
var _sessions: Dictionary = {}
var _tools: Dictionary
var _version: String
var _bridge_instance_id: String
var _port := 0
var _polling := false
var _seen_nonces: Dictionary = {}


func _init(tools: Dictionary, version: String = "0.1.0") -> void:
	_tools = tools
	_version = version
	_bridge_instance_id = Crypto.new().generate_random_bytes(16).hex_encode()


func start(port: int) -> Error:
	stop()
	var listen_error: Error = _listener.listen(port, "127.0.0.1")
	if listen_error == OK:
		_port = port
	return listen_error


func stop() -> void:
	for state: Dictionary in _clients:
		var peer: StreamPeerTCP = state.get("peer")
		if peer != null:
			peer.disconnect_from_host()
	_clients.clear()
	_sessions.clear()
	_seen_nonces.clear()
	_listener.stop()
	_port = 0
	_polling = false


func is_running() -> bool:
	return _listener.is_listening()


func tool_descriptors(read_only: bool = false) -> Array:
	var descriptors: Array = []
	for tool_name: String in _tools:
		var tool = _tools[tool_name]
		var descriptor: Dictionary = tool.descriptor()
		if read_only and not _descriptor_visible_to_read_only(descriptor):
			continue
		var published: Dictionary = descriptor.duplicate(true)
		if read_only and not _descriptor_is_safe_read_only(published):
			published = _narrow_read_only_descriptor(published)
			if published.is_empty():
				continue
		descriptors.append(published)
	return descriptors


func bridge_instance_id() -> String:
	return _bridge_instance_id


func poll() -> void:
	if _polling or not _listener.is_listening():
		return

	# EditorFileSystem imports can re-enter the editor loop. This guard keeps a
	# second _process callback from dispatching another request concurrently.
	_polling = true
	_accept_connections()
	for index: int in range(_clients.size() - 1, -1, -1):
		if _poll_client(_clients[index]):
			_clients.remove_at(index)
	_polling = false


func _accept_connections() -> void:
	while _listener.is_connection_available():
		var peer: StreamPeerTCP = _listener.take_connection()
		if peer == null:
			break
		peer.set_no_delay(true)
		_clients.append({
			"peer": peer,
			"buffer": PackedByteArray(),
			"started_msec": Time.get_ticks_msec(),
		})


func _poll_client(state: Dictionary) -> bool:
	var peer: StreamPeerTCP = state.get("peer")
	if peer == null:
		return true

	peer.poll()
	var buffer: PackedByteArray = state.get("buffer", PackedByteArray())
	var available: int = peer.get_available_bytes()
	if available > 0:
		var remaining_capacity: int = MAX_HEADER_BYTES + MAX_BODY_BYTES + 4 - buffer.size()
		var read_size: int = mini(available, maxi(1, remaining_capacity + 1))
		var read_result: Array = peer.get_partial_data(read_size)
		if int(read_result[0]) != OK:
			peer.disconnect_from_host()
			return true
		var chunk: PackedByteArray = read_result[1]
		buffer.append_array(chunk)
		state["buffer"] = buffer

	if buffer.size() > MAX_HEADER_BYTES + MAX_BODY_BYTES + 4:
		_send_json(peer, 413, "Payload Too Large", {"error": "HTTP request exceeds bridge limits"})
		return true

	var header_end: int = _find_header_end(buffer)
	if header_end < 0:
		if buffer.size() > MAX_HEADER_BYTES:
			_send_json(peer, 431, "Request Header Fields Too Large", {"error": "HTTP headers exceed 64 KiB"})
			return true
		return _should_drop_incomplete_peer(peer, state)

	var header_text: String = buffer.slice(0, header_end).get_string_from_utf8()
	var parsed_header: Dictionary = _parse_request_header(header_text)
	if not bool(parsed_header.get("ok", false)):
		_send_json(peer, 400, "Bad Request", {"error": parsed_header.get("error", "Malformed HTTP request")})
		return true

	var content_length: int = int(parsed_header.get("content_length", 0))
	if content_length > MAX_BODY_BYTES:
		_send_json(peer, 413, "Payload Too Large", {"error": "HTTP body exceeds 8 MiB"})
		return true

	var request_size: int = header_end + 4 + content_length
	if buffer.size() < request_size:
		return _should_drop_incomplete_peer(peer, state)

	var body: PackedByteArray = buffer.slice(header_end + 4, request_size)
	_handle_http_request(peer, parsed_header, body)
	return true


func _should_drop_incomplete_peer(peer: StreamPeerTCP, state: Dictionary) -> bool:
	if Time.get_ticks_msec() - int(state.get("started_msec", 0)) > REQUEST_TIMEOUT_MSEC:
		_send_json(peer, 408, "Request Timeout", {"error": "Timed out waiting for a complete HTTP request"})
		return true
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()
		return true
	return false


func _find_header_end(buffer: PackedByteArray) -> int:
	for index: int in range(0, buffer.size() - 3):
		if buffer[index] == 13 and buffer[index + 1] == 10 and buffer[index + 2] == 13 and buffer[index + 3] == 10:
			return index
	return -1


func _parse_request_header(header_text: String) -> Dictionary:
	var lines: PackedStringArray = header_text.split("\r\n", false)
	if lines.is_empty():
		return {"ok": false, "error": "Missing request line"}

	var request_parts: PackedStringArray = lines[0].split(" ", false)
	if request_parts.size() != 3 or not request_parts[2].begins_with("HTTP/"):
		return {"ok": false, "error": "Malformed request line"}

	var headers: Dictionary = {}
	for index: int in range(1, lines.size()):
		var line: String = lines[index]
		var colon: int = line.find(":")
		if colon <= 0:
			return {"ok": false, "error": "Malformed HTTP header"}
		var name: String = line.substr(0, colon).strip_edges().to_lower()
		var value: String = line.substr(colon + 1).strip_edges()
		if headers.has(name):
			headers[name] = str(headers[name]) + ", " + value
		else:
			headers[name] = value

	var transfer_encoding: String = str(headers.get("transfer-encoding", "")).to_lower()
	if not transfer_encoding.is_empty() and transfer_encoding != "identity":
		return {"ok": false, "error": "Chunked transfer encoding is not supported"}

	var content_length := 0
	var raw_length: String = str(headers.get("content-length", "0"))
	if not raw_length.is_valid_int():
		return {"ok": false, "error": "Invalid Content-Length"}
	content_length = raw_length.to_int()
	if content_length < 0:
		return {"ok": false, "error": "Negative Content-Length"}

	return {
		"ok": true,
		"method": request_parts[0].to_upper(),
		"path": request_parts[1],
		"headers": headers,
		"content_length": content_length,
	}


func _handle_http_request(peer: StreamPeerTCP, request: Dictionary, body: PackedByteArray) -> void:
	var headers: Dictionary = request.get("headers", {})
	var origin: String = str(headers.get("origin", ""))
	if not _origin_allowed(origin):
		_send_json(peer, 403, "Forbidden", {"error": "Origin is not allowed"})
		return

	var response_headers: Dictionary = _base_response_headers(origin)
	var method: String = str(request.get("method", ""))
	var path: String = str(request.get("path", "/")).get_slice("?", 0)

	if method == "OPTIONS":
		response_headers["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
		_send_response(peer, 204, "No Content", "", PackedByteArray(), response_headers)
		return

	if path == HEALTH_PATH:
		if method != "GET":
			response_headers["Allow"] = "GET"
			_send_json(peer, 405, "Method Not Allowed", {"error": "Method not allowed"}, response_headers)
			return
		var health: Dictionary = _bridge_identity()
		health["service"] = "revvy-godot-bridge"
		health["engine_version"] = str(Engine.get_version_info().get("string", "unknown"))
		health["port"] = _port
		health["tools"] = _tools.size()
		_send_json(peer, 200, "OK", health, response_headers)
		return

	if path != ENDPOINT_PATH:
		_send_json(peer, 404, "Not Found", {"error": "Unknown endpoint"}, response_headers)
		return

	if method == "GET":
		_send_json(peer, 406, "Not Acceptable", {
			"error": "SSE GET streams are not implemented by the GDScript bridge",
			"supported_transport": "POST with application/json",
		}, response_headers)
		return

	if method == "DELETE":
		var session_id: String = str(headers.get("mcp-session-id", ""))
		if not session_id.is_empty():
			_sessions.erase(session_id)
		_send_json(peer, 200, "OK", {"ok": true}, response_headers)
		return

	if method != "POST":
		response_headers["Allow"] = "GET, POST, DELETE, OPTIONS"
		_send_json(peer, 405, "Method Not Allowed", {"error": "Method not allowed"}, response_headers)
		return

	var authorization: Dictionary = _authorize_post(headers, body)
	if not bool(authorization.get("ok", false)):
		_send_json(peer, 401, "Unauthorized", {"error": "Unauthorized editor bridge request"}, response_headers)
		return

	var outcome: Dictionary = _handle_rpc(
		body.get_string_from_utf8(),
		str(authorization.get("scope", "read_only")),
	)
	if bool(outcome.get("notification", false)):
		_send_response(peer, 202, "Accepted", "", PackedByteArray(), response_headers, authorization)
		return

	for header_name: String in outcome.get("headers", {}):
		response_headers[header_name] = outcome["headers"][header_name]
	_send_json(peer, 200, "OK", outcome.get("response", {}), response_headers, authorization)


func _authorize_post(headers: Dictionary, body: PackedByteArray) -> Dictionary:
	var has_signature_headers: bool = false
	for header_name: String in [
		"x-revvy-bridge-instance",
		"x-revvy-access-scope",
		"x-revvy-request-timestamp",
		"x-revvy-request-nonce",
		"x-revvy-request-signature",
	]:
		if headers.has(header_name):
			has_signature_headers = true
			break

	if _is_public_ping(body) and not has_signature_headers:
		return {"ok": true, "signed": false}

	var instance: String = str(headers.get("x-revvy-bridge-instance", "")).strip_edges()
	var scope: String = str(headers.get("x-revvy-access-scope", "")).strip_edges()
	var timestamp: String = str(headers.get("x-revvy-request-timestamp", "")).strip_edges()
	var nonce: String = str(headers.get("x-revvy-request-nonce", "")).strip_edges()
	var presented: String = str(headers.get("x-revvy-request-signature", "")).strip_edges()
	if scope != "read_only" and scope != "full":
		return {"ok": false}
	if instance.is_empty() or instance != _bridge_instance_id or _port < 1 or _port > 65535:
		return {"ok": false}
	if timestamp.is_empty() or not timestamp.is_valid_int():
		return {"ok": false}
	var timestamp_seconds: int = timestamp.to_int()
	var now: int = int(Time.get_unix_time_from_system())
	if timestamp_seconds < now - ALLOWED_CLOCK_SKEW_SECONDS or timestamp_seconds > now + ALLOWED_CLOCK_SKEW_SECONDS:
		return {"ok": false}
	if not _valid_nonce(nonce):
		return {"ok": false}
	if presented.length() != 43 or not presented.begins_with(BRIDGE_SIGNATURE_VERSION + "="):
		return {"ok": false}

	var key: String = _load_bridge_hmac_key()
	if key.length() < 32:
		return {"ok": false}
	var prefix := (
		"revvy-proxy-v2\n%s\n%s\n%d\n%s\n%s\n%d\n"
		% [scope, instance, _port, timestamp, nonce, body.size()]
	).to_utf8_buffer()
	var canonical: PackedByteArray = prefix.duplicate()
	canonical.append_array(body)
	var expected: String = BRIDGE_SIGNATURE_VERSION + "=" + _hmac_sha1_hex(key, canonical)
	if not _constant_time_equals(presented, expected):
		return {"ok": false}

	_purge_expired_nonces(now)
	var replay_key := instance + "\n" + nonce
	if _seen_nonces.has(replay_key):
		return {"ok": false}
	_seen_nonces[replay_key] = now
	return {
		"ok": true,
		"signed": true,
		"scope": scope,
		"instance": instance,
		"timestamp": timestamp,
		"nonce": nonce,
		"request_body": body,
		"key": key,
	}


func _is_public_ping(body: PackedByteArray) -> bool:
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return false
	var request: Dictionary = parser.data
	for raw_key: Variant in request.keys():
		if typeof(raw_key) != TYPE_STRING or str(raw_key) not in ["jsonrpc", "id", "method", "params"]:
			return false
	if typeof(request.get("jsonrpc", null)) != TYPE_STRING or request.get("jsonrpc") != "2.0":
		return false
	if typeof(request.get("method", null)) != TYPE_STRING or request.get("method") != "ping":
		return false
	if not request.has("params"):
		return true
	var params: Variant = request.get("params")
	return typeof(params) == TYPE_DICTIONARY and params.is_empty()


func _valid_nonce(nonce: String) -> bool:
	if nonce.length() != 32:
		return false
	for index: int in range(nonce.length()):
		var code: int = nonce.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _purge_expired_nonces(now: int) -> void:
	var expired: Array[String] = []
	for replay_key: String in _seen_nonces:
		if int(_seen_nonces[replay_key]) < now - REPLAY_RETENTION_SECONDS:
			expired.append(replay_key)
	for replay_key: String in expired:
		_seen_nonces.erase(replay_key)


func _load_bridge_hmac_key() -> String:
	var path: String = _bridge_auth_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(document) != TYPE_DICTIONARY:
		return ""
	if int(document.get("version", 0)) != 2 or str(document.get("algorithm", "")) != BRIDGE_AUTH_ALGORITHM:
		return ""
	var key: String = str(document.get("bridge_hmac_key", "")).strip_edges()
	return key if key.length() >= 32 else ""


func _bridge_auth_path() -> String:
	var explicit_file: String = OS.get_environment("REVVY_BRIDGE_AUTH_FILE").strip_edges()
	if not explicit_file.is_empty():
		return _expand_user_path(explicit_file)
	var security_dir: String = OS.get_environment("REVVY_SECURITY_DIR").strip_edges()
	if not security_dir.is_empty():
		return _expand_user_path(security_dir).path_join("bridge-auth.json")
	if OS.get_name() == "Windows":
		var local_app_data: String = OS.get_environment("LOCALAPPDATA").strip_edges()
		if local_app_data.is_empty():
			local_app_data = OS.get_environment("USERPROFILE").path_join("AppData/Local")
		return local_app_data.path_join("Revvy/Security/bridge-auth.json")
	var state_home: String = OS.get_environment("XDG_STATE_HOME").strip_edges()
	if not state_home.is_empty():
		return _expand_user_path(state_home).path_join("Revvy/Security/bridge-auth.json")
	return OS.get_environment("HOME").path_join(".local/state/Revvy/Security/bridge-auth.json")


func _expand_user_path(path: String) -> String:
	if path == "~":
		return OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	if path.begins_with("~/") or path.begins_with("~\\"):
		var home: String = OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
		return home.path_join(path.substr(2))
	return path


func _hmac_sha1_hex(key: String, data: PackedByteArray) -> String:
	var context := HMACContext.new()
	if context.start(HashingContext.HASH_SHA1, key.to_utf8_buffer()) != OK:
		return ""
	if context.update(data) != OK:
		return ""
	return context.finish().hex_encode()


func _constant_time_equals(left: String, right: String) -> bool:
	if left.length() != right.length():
		return false
	var difference := 0
	for index: int in range(left.length()):
		difference |= left.unicode_at(index) ^ right.unicode_at(index)
	return difference == 0


func _response_signature(auth: Dictionary, status: int, response_body: PackedByteArray) -> String:
	if not bool(auth.get("signed", false)):
		return ""
	var request_body: PackedByteArray = auth.get("request_body", PackedByteArray())
	var prefix := (
		"revvy-bridge-response-v2\n%s\n%s\n%d\n%s\n%s\n%d\n%d\n"
		% [
			auth.get("scope", ""),
			auth.get("instance", ""),
			_port,
			auth.get("timestamp", ""),
			auth.get("nonce", ""),
			status,
			request_body.size(),
		]
	).to_utf8_buffer()
	var separator := "\n%d\n" % response_body.size()
	var canonical: PackedByteArray = prefix.duplicate()
	canonical.append_array(request_body)
	canonical.append_array(separator.to_utf8_buffer())
	canonical.append_array(response_body)
	return BRIDGE_SIGNATURE_VERSION + "=" + _hmac_sha1_hex(str(auth.get("key", "")), canonical)


func _descriptor_is_safe_read_only(descriptor: Dictionary) -> bool:
	var annotations: Variant = descriptor.get("annotations", {})
	return (
		typeof(annotations) == TYPE_DICTIONARY
		and annotations.get("readOnlyHint", false) == true
		and annotations.get("destructiveHint", false) != true
	)


func _descriptor_read_only_actions(descriptor: Dictionary) -> Array[String]:
	var annotations: Variant = descriptor.get("annotations", {})
	if typeof(annotations) != TYPE_DICTIONARY:
		return []
	var raw_actions: Variant = annotations.get("readOnlyActions", [])
	if typeof(raw_actions) != TYPE_ARRAY:
		return []
	var actions: Array[String] = []
	for raw_action: Variant in raw_actions:
		if typeof(raw_action) != TYPE_STRING:
			continue
		var action: String = str(raw_action).strip_edges().to_lower()
		if not action.is_empty() and action not in actions:
			actions.append(action)
	return actions


func _descriptor_visible_to_read_only(descriptor: Dictionary) -> bool:
	return _descriptor_is_safe_read_only(descriptor) or not _descriptor_read_only_actions(descriptor).is_empty()


func _narrow_read_only_descriptor(descriptor: Dictionary) -> Dictionary:
	var allowed: Array[String] = _descriptor_read_only_actions(descriptor)
	if allowed.is_empty():
		return {}
	var schema: Variant = descriptor.get("inputSchema", {})
	if typeof(schema) == TYPE_DICTIONARY:
		var properties: Variant = schema.get("properties", {})
		if typeof(properties) == TYPE_DICTIONARY:
			var action_schema: Variant = properties.get("action", {})
			if typeof(action_schema) == TYPE_DICTIONARY:
				var action_enum: Variant = action_schema.get("enum", null)
				if typeof(action_enum) == TYPE_ARRAY:
					var surviving: Array = []
					for raw_action: Variant in action_enum:
						if typeof(raw_action) == TYPE_STRING and str(raw_action).strip_edges().to_lower() in allowed:
							surviving.append(raw_action)
					if surviving.is_empty():
						return {}
					action_schema["enum"] = surviving
	descriptor["description"] = (
		str(descriptor.get("description", ""))
		+ " Safe (read-only) session: only these actions are available — "
		+ ", ".join(allowed)
		+ "."
	).strip_edges()
	return descriptor


func _read_only_denial(tool_name: String, arguments: Dictionary) -> String:
	var tool = _tools.get(tool_name)
	if tool == null:
		return "This Revvy session is Safe/read-only. Start a Full access session to run mutating tools."
	var descriptor: Dictionary = tool.descriptor()
	if _descriptor_is_safe_read_only(descriptor):
		return ""
	var allowed: Array[String] = _descriptor_read_only_actions(descriptor)
	if allowed.is_empty():
		return "This Revvy session is Safe/read-only. Start a Full access session to run mutating tools."
	var action: String = str(arguments.get("action", "")).strip_edges().to_lower()
	if action in allowed:
		return ""
	return (
		"Action '%s' needs a Full access session. This Safe session offers: %s."
		% [action, ", ".join(allowed)]
	)


func _handle_rpc(body: String, access_scope: String = "full") -> Dictionary:
	var parser := JSON.new()
	var parse_error: Error = parser.parse(body)
	if parse_error != OK:
		return {"response": _rpc_error(null, -32700, "Parse error: " + parser.get_error_message())}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"response": _rpc_error(null, -32600, "Invalid Request: expected an object")}

	var request: Dictionary = parser.data
	var request_id: Variant = request.get("id", null)
	var is_notification: bool = not request.has("id") or request_id == null
	if is_notification:
		return {"notification": true}
	if str(request.get("jsonrpc", "")) != "2.0":
		return {"response": _rpc_error(request_id, -32600, "Invalid Request: jsonrpc must be '2.0'")}

	var method_value: Variant = request.get("method", null)
	if typeof(method_value) != TYPE_STRING or str(method_value).is_empty():
		return {"response": _rpc_error(request_id, -32600, "Invalid Request: missing method")}

	var params: Variant = request.get("params", {})
	if params == null:
		params = {}
	if typeof(params) != TYPE_DICTIONARY:
		return {"response": _rpc_error(request_id, -32602, "Params must be an object")}

	var method: String = method_value
	match method:
		"initialize":
			var requested: String = str(params.get("protocolVersion", SUPPORTED_PROTOCOL_VERSIONS[0]))
			var negotiated: String = requested if requested in SUPPORTED_PROTOCOL_VERSIONS else SUPPORTED_PROTOCOL_VERSIONS[0]
			var session_id: String = Crypto.new().generate_random_bytes(16).hex_encode()
			_sessions[session_id] = true
			return {
				"headers": {"Mcp-Session-Id": session_id},
				"response": _rpc_result(request_id, {
					"protocolVersion": negotiated,
					"capabilities": {"tools": {}},
					"serverInfo": {"name": "revvy-godot", "version": _version},
				}),
			}
		"ping":
			return {"response": _rpc_result(request_id, _bridge_identity())}
		"tools/list":
			return {
				"response": _rpc_result(
					request_id,
					{"tools": tool_descriptors(access_scope == "read_only")},
				),
			}
		"tools/call":
			return {
				"response": _rpc_result(
					request_id,
					_call_tool(params, access_scope == "read_only"),
				),
			}
		_:
			return {"response": _rpc_error(request_id, -32601, "Method not found: " + method)}


func _bridge_identity() -> Dictionary:
	return {
		"engine": "godot",
		"project_path": CONFIG_SCRIPT.current_project_path(),
		"bridge_instance_id": _bridge_instance_id,
		"editor_port": _port,
	}


func _call_tool(params: Dictionary, read_only: bool = false) -> Dictionary:
	var tool_name: String = str(params.get("name", ""))
	if tool_name.is_empty():
		return _tool_result({"success": false, "error": "tools/call requires a name"}, true)

	var arguments: Variant = params.get("arguments", {})
	if arguments == null:
		arguments = {}
	if typeof(arguments) != TYPE_DICTIONARY:
		return _tool_result({"success": false, "error": "Tool arguments must be an object"}, true)

	var tool = _tools.get(tool_name)
	if tool == null:
		return _tool_result({"success": false, "error": "Unknown tool: " + tool_name}, true)
	if read_only:
		var denial: String = _read_only_denial(tool_name, arguments)
		if not denial.is_empty():
			return _tool_result({"success": false, "error": denial}, true)

	var payload: Variant = tool.invoke(arguments)
	if typeof(payload) != TYPE_DICTIONARY:
		return _tool_result({"success": false, "error": "Tool returned a non-object payload"}, true)
	return _tool_result(payload, not bool(payload.get("success", false)))


func _tool_result(payload: Dictionary, is_error: bool) -> Dictionary:
	# Tier-10 §4: a tool attaches non-text MCP content blocks through the
	# reserved _content_blocks payload key. The key is lifted out and removed
	# before the payload is serialized into the text block, so a large
	# attachment is carried once as its own block and never duplicated into the
	# text block's JSON. The text block stays first and stays the complete JSON
	# result; non-object entries are dropped so a malformed attachment cannot
	# produce an invalid MCP result.
	var attachments: Variant = payload.get("_content_blocks", null)
	payload.erase("_content_blocks")
	var content: Array = [{"type": "text", "text": JSON.stringify(payload)}]
	if typeof(attachments) == TYPE_ARRAY:
		for block: Variant in attachments:
			if typeof(block) == TYPE_DICTIONARY:
				content.append(block)
	return {
		"content": content,
		"isError": is_error,
	}


func _rpc_result(request_id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": request_id, "result": result}


func _rpc_error(request_id: Variant, code: int, message: String) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": request_id,
		"error": {"code": code, "message": message},
	}


func _send_json(
	peer: StreamPeerTCP,
	status: int,
	reason: String,
	value: Variant,
	extra_headers: Dictionary = {},
	auth: Dictionary = {},
) -> void:
	_send_response(
		peer,
		status,
		reason,
		"application/json; charset=utf-8",
		JSON.stringify(value).to_utf8_buffer(),
		extra_headers,
		auth,
	)


func _send_response(
	peer: StreamPeerTCP,
	status: int,
	reason: String,
	content_type: String,
	body: PackedByteArray,
	extra_headers: Dictionary,
	auth: Dictionary = {},
) -> void:
	var head := "HTTP/1.1 %d %s\r\n" % [status, reason]
	if not content_type.is_empty():
		head += "Content-Type: %s\r\n" % content_type
	head += "Content-Length: %d\r\n" % body.size()
	head += "Cache-Control: no-store\r\n"
	head += "Connection: close\r\n"
	var response_headers: Dictionary = extra_headers.duplicate()
	var signature: String = _response_signature(auth, status, body)
	if not signature.is_empty():
		response_headers["X-Revvy-Response-Signature"] = signature
	for header_name: String in response_headers:
		var header_value: String = str(response_headers[header_name])
		if not header_name.contains("\r") and not header_name.contains("\n") and not header_value.contains("\r") and not header_value.contains("\n"):
			head += "%s: %s\r\n" % [header_name, header_value]
	head += "\r\n"

	var response: PackedByteArray = head.to_utf8_buffer()
	response.append_array(body)
	peer.put_data(response)
	peer.disconnect_from_host()


func _base_response_headers(origin: String) -> Dictionary:
	var headers := {
		"Access-Control-Allow-Headers": "Content-Type, Authorization, Mcp-Session-Id, MCP-Protocol-Version, Accept, Last-Event-ID, X-Revvy-Bridge-Instance, X-Revvy-Access-Scope, X-Revvy-Request-Timestamp, X-Revvy-Request-Nonce, X-Revvy-Request-Signature",
		"Access-Control-Expose-Headers": "Mcp-Session-Id, X-Revvy-Response-Signature",
		"Server": "revvy-godot/" + _version,
	}
	if not origin.is_empty():
		headers["Access-Control-Allow-Origin"] = origin
		headers["Vary"] = "Origin"
	return headers


func _origin_allowed(origin: String) -> bool:
	if origin.is_empty():
		return true
	if origin.contains("\r") or origin.contains("\n"):
		return false

	var scheme_end: int = origin.find("://")
	if scheme_end <= 0:
		return false
	var scheme: String = origin.substr(0, scheme_end).to_lower()
	if scheme != "http" and scheme != "https":
		return false

	var authority: String = origin.substr(scheme_end + 3).get_slice("/", 0)
	if authority.is_empty() or authority.contains("@"):
		return false

	if authority.begins_with("["):
		var close_bracket: int = authority.find("]")
		if close_bracket < 0 or authority.substr(0, close_bracket + 1).to_lower() != "[::1]":
			return false
		return _valid_optional_port(authority.substr(close_bracket + 1))

	if authority.count(":") > 1:
		return false
	var colon: int = authority.rfind(":")
	var host: String = authority.substr(0, colon) if colon >= 0 else authority
	var port_suffix: String = authority.substr(colon) if colon >= 0 else ""
	if host.to_lower() != "localhost" and host != "127.0.0.1":
		return false
	return _valid_optional_port(port_suffix)


func _valid_optional_port(suffix: String) -> bool:
	if suffix.is_empty():
		return true
	if not suffix.begins_with(":"):
		return false
	var port_text: String = suffix.substr(1)
	if not port_text.is_valid_int():
		return false
	var port: int = port_text.to_int()
	return port >= 1 and port <= 65535
