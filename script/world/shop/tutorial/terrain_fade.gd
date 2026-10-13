class_name TerrainFade
extends RefCounted
## 낯선 땅 → 마을 지형으로 바뀌는 순간의 암전·페이드. 화면이 검게 가려진 사이에 지형을 갈아끼우고 서서히 밝힌다.
## 헤드리스(시험)에서는 기다리지 않고 바로 바꾼다. 시험에서 켜고 끄려면 force_for_test.

const FADE_OUT := 0.7      # 어두워지는 시간(초)
const HOLD := 0.35         # 완전히 어두운 채로 지형을 바꾸고 기다리는 시간
const FADE_IN := 1.1       # 밝아지는 시간
const LAYER := 90          # 게임 화면과 안내 글 위, 메뉴·시작 화면 아래

static var _forced: int = -1


static func enabled() -> bool:
	if _forced >= 0:
		return _forced == 1
	return DisplayServer.get_name() != "headless"


static func force_for_test(value: bool) -> void:
	_forced = 1 if value else 0


# at_black 은 화면이 완전히 어두울 때 한 번 불린다. 전체 길이는 FADE_OUT + HOLD + FADE_IN.
static func run(owner: Node, at_black: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.name = "TerrainFade"
	layer.layer = LAYER
	var cover := ColorRect.new()
	cover.color = Color(0.02, 0.03, 0.02, 1.0)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.modulate.a = 0.0
	layer.add_child(cover)
	owner.get_tree().root.add_child(layer)
	var tween := layer.create_tween()
	tween.tween_property(cover, "modulate:a", 1.0, FADE_OUT)
	tween.tween_callback(at_black)
	tween.tween_interval(HOLD)
	tween.tween_property(cover, "modulate:a", 0.0, FADE_IN)
	tween.tween_callback(layer.queue_free)
