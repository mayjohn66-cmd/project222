class_name CheckoutOptions
extends RefCounted
## 간편 계산 옵션(스캔 없이 예전처럼 자동 결제). 설정 파일 `gameplay/simple_checkout`에 저장된다.

static var _simple: int = -1   # -1: 아직 설정 파일을 읽지 않음
static var _forced: int = -1   # 시험용 고정값(-1: 없음). 설정 메뉴가 불러와도 바뀌지 않는다


static func simple() -> bool:
	if _forced >= 0:
		return _forced == 1
	if _simple < 0:
		var config := ConfigFile.new()
		var loaded: bool = config.load(GameConfig.SETTINGS_PATH) == OK
		# 기본값은 간편 계산(켜짐). 설정 파일이 없거나 항목이 없으면 간편 계산이다.
		_simple = 1 if (not loaded or bool(config.get_value("gameplay", "simple_checkout", true))) else 0
	return _simple == 1


static func set_simple(value: bool) -> void:
	_simple = 1 if value else 0


# 시험에서 설정 파일·메뉴와 상관없이 값을 고정한다.
static func force_for_test(value: bool) -> void:
	_forced = 1 if value else 0
