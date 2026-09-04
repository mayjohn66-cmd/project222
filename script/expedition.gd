extends Node2D


enum Weekday {
	MONDAY = 1,
	TUESDAY = 2,
	WEDNESDAY = 3,
	THURSDAY = 4,
	FRIDAY = 5,
	SATURDAY = 6,
	SUNDAY = 7
}


@onready var day_label: Label = (
	$UI/Panel/VBoxContainer/DayLabel
)

@onready var status_label: Label = (
	$UI/Panel/VBoxContainer/StatusLabel
)

@onready var complete_button: Button = (
	$UI/Panel/VBoxContainer/CompleteButton
)


var current_day: int = Weekday.SATURDAY


func _ready():
	current_day = GameState.current_day

	# 원정 씬은 토/일만 허용
	if (
		current_day != Weekday.SATURDAY
		and current_day != Weekday.SUNDAY
	):
		current_day = Weekday.SATURDAY
		GameState.current_day = current_day

	complete_button.pressed.connect(
		complete_expedition_day
	)

	update_ui()

	print(
		"[원정] 시작: ",
		get_day_name()
	)


func get_day_name() -> String:
	match current_day:
		Weekday.SATURDAY:
			return "토요일"

		Weekday.SUNDAY:
			return "일요일"

	return ""


func update_ui():
	day_label.text = get_day_name()

	if current_day == Weekday.SATURDAY:
		status_label.text = "원정 1일차"
		complete_button.text = "토요일 원정 완료"

	elif current_day == Weekday.SUNDAY:
		status_label.text = "원정 2일차"
		complete_button.text = "원정 종료"

func complete_expedition_day():
	# =========================
	# 토요일 → 일요일
	# =========================
	if current_day == Weekday.SATURDAY:
		current_day = Weekday.SUNDAY
		GameState.current_day = current_day

		update_ui()

		print(
			"[원정] 일요일 시작"
		)

		return

	# =========================
	# 일요일 → 다음 월요일
	# =========================
	if current_day == Weekday.SUNDAY:
		finish_expedition()


func finish_expedition():
	print("[원정] 주간 원정 완료")

	current_day = Weekday.MONDAY
	GameState.current_day = current_day

	get_tree().change_scene_to_file(
		"res://scenes/main.tscn"
	)
