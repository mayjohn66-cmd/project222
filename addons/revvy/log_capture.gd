@tool
extends Logger

const DEFAULT_CAPACITY := 1000

var _capacity: int
var _entries: Array[Dictionary] = []
var _mutex := Mutex.new()
var _sequence := 0


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = maxi(1, capacity)


func _log_message(message: String, error: bool) -> void:
	_append_entry("error" if error else "info", message, {})


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace],
) -> void:
	var severity := "error"
	if error_type == Logger.ERROR_TYPE_WARNING:
		severity = "warning"
	elif error_type == Logger.ERROR_TYPE_SCRIPT:
		severity = "script_error"
	elif error_type == Logger.ERROR_TYPE_SHADER:
		severity = "shader_error"

	var message: String = rationale if not rationale.is_empty() else code
	_append_entry(severity, message, {
		"function": function,
		"file": file,
		"line": line,
		"code": code,
		"editor_notify": editor_notify,
		"error_type": error_type,
	})


func read_entries(
	limit: int = 100,
	query: String = "",
	severities: PackedStringArray = PackedStringArray(),
) -> Array:
	var snapshot: Array = []
	_mutex.lock()
	for entry: Dictionary in _entries:
		snapshot.append(entry.duplicate(true))
	_mutex.unlock()

	var query_lower: String = query.to_lower()
	var severity_filter: Dictionary = {}
	for severity: String in severities:
		severity_filter[severity] = true

	var filtered: Array = []
	for entry: Dictionary in snapshot:
		if not severity_filter.is_empty() and not severity_filter.has(str(entry.get("severity", ""))):
			continue
		if not query_lower.is_empty():
			var searchable: String = (
				str(entry.get("message", "")) + " " + JSON.stringify(entry.get("source", {}))
			).to_lower()
			if not searchable.contains(query_lower):
				continue
		filtered.append(entry)

	var bounded_limit: int = clampi(limit, 1, _capacity)
	if filtered.size() > bounded_limit:
		return filtered.slice(filtered.size() - bounded_limit)
	return filtered


func entry_count() -> int:
	_mutex.lock()
	var count: int = _entries.size()
	_mutex.unlock()
	return count


func clear() -> void:
	_mutex.lock()
	_entries.clear()
	_mutex.unlock()


func _append_entry(severity: String, message: String, source: Dictionary) -> void:
	# Logger callbacks may run concurrently on engine worker threads. Do not call
	# print(), push_error(), or any editor API while holding this mutex.
	_mutex.lock()
	_sequence += 1
	_entries.append({
		"sequence": _sequence,
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
		"severity": severity,
		"message": message,
		"source": source,
	})
	while _entries.size() > _capacity:
		_entries.pop_front()
	_mutex.unlock()
