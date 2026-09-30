class_name GameSettingsService
extends RefCounted


func load_settings() -> Dictionary:
	var config := ConfigFile.new()

	var load_error: Error = config.load(
		GameConfig.SETTINGS_PATH
	)

	# 설정 파일이 없는 최초 실행은 정상 상태다.
	if load_error == ERR_FILE_NOT_FOUND:
		return {
			"success": true,
			"master_volume": 100.0,
			"fullscreen": false,
			"game_speed": 1.0
		}

	if load_error != OK:
		return {
			"success": false,
			"message": "설정 파일 불러오기 실패: " + str(load_error)
		}

	return {
		"success": true,
		"master_volume": clampf(
			float(config.get_value("audio", "master_volume", 100.0)),
			0.0,
			100.0
		),
		"fullscreen": bool(
			config.get_value("display", "fullscreen", false)
		),
		"game_speed": float(
			config.get_value("gameplay", "game_speed", 1.0)
		)
	}


func save_settings(
	master_volume: float,
	fullscreen: bool,
	game_speed: float = 1.0
) -> bool:
	var config := ConfigFile.new()

	config.set_value(
		"audio",
		"master_volume",
		clampf(master_volume, 0.0, 100.0)
	)

	config.set_value(
		"display",
		"fullscreen",
		fullscreen
	)

	config.set_value(
		"gameplay",
		"game_speed",
		game_speed
	)

	var save_error: Error = config.save(
		GameConfig.SETTINGS_PATH
	)

	if save_error != OK:
		push_warning(
			"[설정] 저장 실패: " + str(save_error)
		)
		return false

	return true


func apply_master_volume(value: float) -> void:
	var master_bus_index: int = AudioServer.get_bus_index(
		"Master"
	)

	if master_bus_index < 0:
		return

	var volume_ratio: float = clampf(
		value / 100.0,
		0.0,
		1.0
	)

	AudioServer.set_bus_mute(
		master_bus_index,
		volume_ratio <= 0.0
	)

	if volume_ratio > 0.0:
		AudioServer.set_bus_volume_db(
			master_bus_index,
			linear_to_db(volume_ratio)
		)


func apply_fullscreen(enabled: bool) -> void:
	var target_mode: int = (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)

	DisplayServer.window_set_mode(target_mode)
