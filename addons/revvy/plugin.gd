@tool
extends EditorPlugin

const BRIDGE_VERSION := "0.2.0"

const CONFIG_SCRIPT := preload("res://addons/revvy/revvy_config.gd")
const SERVER_SCRIPT := preload("res://addons/revvy/revvy_server.gd")
const LOG_CAPTURE_SCRIPT := preload("res://addons/revvy/log_capture.gd")
const EXECUTE_SCRIPT_TOOL := preload("res://addons/revvy/tools/execute_script.gd")
const MANAGE_ASSET_TOOL := preload("res://addons/revvy/tools/manage_asset.gd")
const READ_LOGS_TOOL := preload("res://addons/revvy/tools/read_logs.gd")
const EDITOR_STATUS_TOOL := preload("res://addons/revvy/tools/editor_status.gd")
const MANAGE_PLAY_MODE_TOOL := preload("res://addons/revvy/tools/manage_play_mode.gd")
const INSPECT_SCENE_TOOL := preload("res://addons/revvy/tools/inspect_scene.gd")
const MUTATE_SCENE_TOOL := preload("res://addons/revvy/tools/mutate_scene.gd")
const CAPTURE_VIEWPORT_TOOL := preload("res://addons/revvy/tools/capture_viewport.gd")
const SIMULATE_INPUT_TOOL := preload("res://addons/revvy/tools/simulate_input.gd")
const MANAGE_PROPERTIES_TOOL := preload("res://addons/revvy/tools/manage_properties.gd")
const MANAGE_PREFAB_TOOL := preload("res://addons/revvy/tools/manage_prefab.gd")

var _server = null
var _log_capture = null
var _tools: Dictionary = {}


func _enter_tree() -> void:
	set_process(false)

	if DisplayServer.get_name() == "headless" and OS.get_environment("REVVY_ALLOW_HEADLESS").strip_edges() != "1":
		print("Revvy: headless bridge disabled; set REVVY_ALLOW_HEADLESS=1 to enable it.")
		return

	_log_capture = LOG_CAPTURE_SCRIPT.new()
	OS.add_logger(_log_capture)

	var editor_tree: SceneTree = get_tree()
	var play_mode_tool = MANAGE_PLAY_MODE_TOOL.new()
	_tools = {
		"execute_script": EXECUTE_SCRIPT_TOOL.new(),
		"manage_asset": MANAGE_ASSET_TOOL.new(),
		"read_logs": READ_LOGS_TOOL.new(_log_capture),
		"editor_status": EDITOR_STATUS_TOOL.new(editor_tree),
		"manage_play_mode": play_mode_tool,
		"inspect_scene": INSPECT_SCENE_TOOL.new(play_mode_tool),
		"mutate_scene": MUTATE_SCENE_TOOL.new(play_mode_tool),
		# capture_viewport reads the editor viewport and stays available
		# during play mode, so it needs no play_mode_tool dependency.
		"capture_viewport": CAPTURE_VIEWPORT_TOOL.new(),
		# simulate_input only delivers during play mode, but its own guard is
		# EditorInterface.is_playing_scene(), so it needs no dependency either.
		"simulate_input": SIMULATE_INPUT_TOOL.new(),
		# manage_properties refuses every action during play mode, so it takes
		# the play_mode_tool dependency for transition detection, exactly like
		# inspect_scene and mutate_scene.
		"manage_properties": MANAGE_PROPERTIES_TOOL.new(play_mode_tool),
		# manage_prefab refuses every action during play mode, so it takes the
		# same play_mode_tool dependency as manage_properties.
		"manage_prefab": MANAGE_PREFAB_TOOL.new(play_mode_tool),
	}

	_server = SERVER_SCRIPT.new(_tools, BRIDGE_VERSION)
	var port: int = CONFIG_SCRIPT.resolve_editor_port()
	var listen_error: Error = _server.start(port)
	if listen_error != OK:
		push_error("Revvy: could not bind 127.0.0.1:%d (error %d)." % [port, listen_error])
		_cleanup()
		return

	var config_error: Error = CONFIG_SCRIPT.write_runtime_config(port, _server.bridge_instance_id())
	if config_error != OK:
		push_error("Revvy: runtime config write failed (error %d)." % config_error)

	var manifest_error: Error = CONFIG_SCRIPT.write_tools_manifest(_server.tool_descriptors())
	if manifest_error != OK:
		push_error("Revvy: tools-manifest write failed (error %d)." % manifest_error)

	set_process(true)
	print("Revvy: Godot MCP bridge listening on http://127.0.0.1:%d/mcp" % port)


func _process(_delta: float) -> void:
	if _server != null:
		_server.poll()


func _exit_tree() -> void:
	set_process(false)
	_cleanup()


func _cleanup() -> void:
	if _server != null:
		_server.stop()
		_server = null

	if _log_capture != null:
		OS.remove_logger(_log_capture)
		_log_capture = null

	_tools.clear()


func _get_plugin_name() -> String:
	return "Revvy"


func _get_plugin_icon() -> Texture2D:
	return load("res://addons/revvy/icon.svg") as Texture2D
