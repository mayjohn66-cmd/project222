class_name ExpeditionClock
extends Node


# 원정을 실제로 돌리는 동안(RUN 단계) 걸린 실제 시간을 센다.
# 초는 shop_return_context["expedition_seconds"]에 쌓이고(원정 체크포인트에도 함께 저장됨),
# 편의점으로 돌아오면 DayManager가 게임 시간으로 바꿔 자리를 비운 동안의 상점을 정산한다.
# 일시정지 중에는 _process가 멈추므로 시간이 세어지지 않는다.


func _process(delta: float) -> void:
	var host: Node = get_parent()

	if host == null:
		return

	if int(host.get("current_expedition_phase")) != int(host.ExpeditionPhase.RUN):
		return

	if not GameState.has_meta("shop_return_context"):
		return

	var context: Variant = GameState.get_meta("shop_return_context")

	if not context is Dictionary:
		return

	context["expedition_seconds"] = (
		float(context.get("expedition_seconds", 0.0))
		+ delta
	)
