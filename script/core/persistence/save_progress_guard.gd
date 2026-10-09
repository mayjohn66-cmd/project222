class_name SaveProgressGuard
extends RefCounted
## Old saves may omit progress; a present non-dictionary cannot be loaded safely.
static func valid(data: Dictionary) -> bool:
	return not data.has("progress") or data["progress"] is Dictionary
