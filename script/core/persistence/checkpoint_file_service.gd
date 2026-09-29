class_name CheckpointFileService
extends RefCounted


func write_verified_checkpoint(
	data: Dictionary,
	target_path: String
) -> Dictionary:
	if target_path.is_empty():
		return _failure("저장 경로가 비어 있습니다.")

	var temporary_path: String = target_path + ".tmp"

	if not GameState.write_save_file(data, temporary_path):
		return _failure("파일을 기록하지 못했습니다.")

	var verified: Dictionary = GameState.read_save_file(
		temporary_path
	)

	if verified != data:
		return _failure("저장 파일을 확인하지 못했습니다.")

	var replace_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(target_path)
	)

	if replace_error != OK:
		return _failure(
			"저장 파일을 교체하지 못했습니다.",
			replace_error
		)

	return {
		"success": true,
		"message": ""
	}


func _failure(
	message: String,
	error: Error = OK
) -> Dictionary:
	if error == OK:
		push_error("[저장] " + message)
	else:
		push_error(
			"[저장] " + message + " / 오류: " + str(error)
		)

	return {
		"success": false,
		"message": message
	}
