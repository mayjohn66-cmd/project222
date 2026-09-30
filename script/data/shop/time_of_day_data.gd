class_name TimeOfDayData
extends RefCounted


# 하루 중 시각별 배경 색조를 CSV에서 읽어 시각 사이를 부드럽게 이어 준다.
# 열: hour(0~24), tint(16진수 색). 하루가 끝(24시)과 시작(0시)이 이어지도록 계산한다.
# 하루 4등분(6~12 / 12~18 / 18~24 / 0~6)은 이름과 근무 시간대용이고,
# 화면은 이 표로 서서히 어두워졌다 밝아진다.

const PATH: String = "res://data/shop/time_of_day.csv"

static var hours: Array[float] = []
static var tints: Array[Color] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true

	var file := FileAccess.open(
		PATH,
		FileAccess.READ
	)

	if file == null:
		push_error("[TimeOfDayData] 파일 열기 실패: " + PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	var hour_column: int = header.find("hour")
	var tint_column: int = header.find("tint")

	if hour_column < 0 or tint_column < 0:
		push_error("[TimeOfDayData] hour/tint 열이 없습니다: " + PATH)
		return

	var rows: Array[Dictionary] = []

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() <= maxi(hour_column, tint_column):
			continue

		var hour_text: String = row[hour_column].strip_edges()
		var tint_text: String = row[tint_column].strip_edges()

		if not hour_text.is_valid_float() or not Color.html_is_valid(tint_text):
			continue

		rows.append({
			"hour": float(hour_text),
			"tint": Color.html(tint_text)
		})

	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["hour"]) < float(b["hour"])
	)

	for row_data in rows:
		hours.append(float(row_data["hour"]))
		tints.append(row_data["tint"])


# hour: 0.0 이상 24.0 미만의 게임 시각(예: 13.5 = 13시 30분).
static func get_tint(hour: float) -> Color:
	ensure_loaded()

	if hours.is_empty():
		return Color.WHITE

	var time: float = fposmod(hour, 24.0)
	var count: int = hours.size()

	# 시각이 표의 마지막 키보다 크거나 첫 키보다 작으면 하루 경계를 넘어 이어 준다.
	var next_index: int = 0

	while next_index < count and hours[next_index] <= time:
		next_index += 1

	var previous_index: int = (next_index - 1 + count) % count
	next_index = next_index % count

	var previous_hour: float = hours[previous_index]
	var next_hour: float = hours[next_index]

	if next_hour <= previous_hour:
		next_hour += 24.0

	if time < previous_hour:
		time += 24.0

	var span: float = next_hour - previous_hour

	if span <= 0.0:
		return tints[previous_index]

	return tints[previous_index].lerp(
		tints[next_index],
		clampf((time - previous_hour) / span, 0.0, 1.0)
	)
