class_name DebugLog
extends RefCounted


# 개발 중 확인용 출력. print 대신 사용한다.
# 내보낸(배포) 빌드에서는 자동으로 출력하지 않으며,
# GameConfig.DEBUG_LOG_ENABLED를 false로 바꾸면 편집기에서도 끌 수 있다.
# print처럼 여러 값을 이어 붙여 한 줄로 출력한다.
static func write(...args: Array) -> void:
	if not GameConfig.DEBUG_LOG_ENABLED:
		return

	if not OS.is_debug_build():
		return

	var text: String = ""

	for value in args:
		text += str(value)

	print(text)
