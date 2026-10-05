extends "res://script/objects/shop/decoration.gd"
## 냉장함·냉동함. 가게에 놓는 가구이면서, 플레이어가 상호작용하면 보존 보관 창(PreservationPanel)을 연다.
## 가구를 만들어 놓은 것이 곧 설치이므로 설치 대금은 받지 않는다. 같은 종류를 여러 대 놓아도 보관함(PreservationService)은 하나를 같이 쓴다.

const UNIT_BY_BUILD: Dictionary = {"fridge_unit": "fridge", "freezer_unit": "freezer"}


func _ready() -> void:
	add_to_group("preservation_unit")


# 이 가구가 여는 보관 설비 id("fridge" / "freezer"). 알 수 없으면 빈 문자열.
func unit_id() -> String:
	return str(UNIT_BY_BUILD.get(str(get_meta("build_id", furniture_id)), ""))
