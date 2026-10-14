class_name TerrainFade
extends RefCounted
## 초반 땅이 마을 지형으로 열리는 과정(점점 밝히기, store_exterior.gd 의 _begin_reveal)을 켜고 끄는 스위치.
## 헤드리스(시험)에서는 기다리지 않고 바로 열린다. 시험에서 켜고 끄려면 force_for_test.
## (예전에는 화면을 어둡게 가리는 암전을 여기서 했으나, 지형이 가게에서 바깥으로 천천히 열리는 방식으로 바꿨다.)

static var _forced: int = -1


static func enabled() -> bool:
	if _forced >= 0:
		return _forced == 1
	return DisplayServer.get_name() != "headless"


static func force_for_test(value: bool) -> void:
	_forced = 1 if value else 0
