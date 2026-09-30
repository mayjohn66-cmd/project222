class_name GameSpeed
extends RefCounted


# 게임 속도 배율. 설정에서 고르며 상점 화면에서만 적용된다(원정은 실시간 조작이라 항상 1배).
# 적용은 Engine.time_scale로 하므로 시계·손님·직원·이동이 함께 빨라진다.
# 값은 설정 파일에 저장되고, ShopSpeedController(상점 씬)가 적용과 해제를 맡는다.

const LISTENER_GROUP: String = "game_speed_listener"

static var current: float = 1.0
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true

	var settings: Dictionary = GameSettingsService.new().load_settings()

	if bool(settings.get("success", false)):
		current = sanitize(float(settings.get("game_speed", 1.0)))


# 허용된 배율 중 가장 가까운 값으로 고른다(설정 파일이 손상돼도 안전하게).
static func sanitize(value: float) -> float:
	var best: float = float(GameConfig.GAME_SPEED_OPTIONS[0])

	for option in GameConfig.GAME_SPEED_OPTIONS:
		if absf(float(option) - value) < absf(best - value):
			best = float(option)

	return best


static func get_current() -> float:
	ensure_loaded()

	return current


static func set_current(
	value: float,
	tree: SceneTree
) -> void:
	_loaded = true
	current = sanitize(value)

	# 상점 씬이 열려 있으면 바로 반영한다.
	if tree != null:
		tree.call_group(
			LISTENER_GROUP,
			"on_game_speed_changed"
		)
