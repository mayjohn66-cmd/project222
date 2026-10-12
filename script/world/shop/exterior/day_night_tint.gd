class_name DayNightTint
extends CanvasModulate


# 게임 시각에 맞춰 월드 화면 색조를 서서히 바꾼다(밤에는 어둡게, 낮에는 밝게).
# 시각은 DayManager의 현재 시(정수)와 HourTimer 진행률로 계산해 시간 사이도 끊김 없이 이어진다.
# UI는 별도 CanvasLayer라서 영향을 받지 않는다.

@export var day_manager_path: NodePath = ^"../DayManager"

var day_manager: Node = null


func _ready() -> void:
	day_manager = get_node_or_null(day_manager_path)

	if day_manager == null:
		push_warning("[DayNightTint] DayManager를 찾지 못했습니다.")

	color = _get_target_color()


func _process(_delta: float) -> void:
	color = _get_target_color()


func _get_target_color() -> Color:
	if day_manager == null:
		return Color.WHITE

	var hour: float = float(day_manager.current_hour)
	var timer: Timer = day_manager.hour_timer

	# 시계가 흐르는 동안에는 이번 시(時)가 얼마나 지났는지를 소수부로 더한다.
	if timer != null and not timer.is_stopped() and timer.wait_time > 0.0:
		hour += clampf(
			1.0 - timer.time_left / timer.wait_time,
			0.0,
			1.0
		)

	return TimeOfDayData.get_tint(hour)
