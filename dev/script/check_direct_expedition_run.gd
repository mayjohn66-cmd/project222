extends "res://tools/check_expedition_run.gd"

# Claude 담당 검증 도구의 공통 시나리오를 상속하고 방 조작만 확장한다.
func _drain(inst) -> void:
	if inst.expedition_room_controller.is_active():
		var played: bool = await ExpeditionRoomTestDriver.play(inst.expedition_room_controller)
		if not played:
			report["stuck"] += 1
	await super._drain(inst)
