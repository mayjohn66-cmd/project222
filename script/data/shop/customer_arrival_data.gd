class_name CustomerArrivalData
extends RefCounted


# 시간당 도착률 λ(명/게임 1시간)를 CSV에서 읽는다. 열: hour(0~23), rate.
# 값은 "가게 앞을 지나던 행인이 입장하는 최종 손님 수"의 기대값이다(평판 0 기준).
# 손님 생성기가 이 값으로 행인이 나타날 확률을 정한다(CustomerSpawner 참고).

const PATH: String = "res://data/shop/customer_arrival.csv"

static var rates: Dictionary = {}
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
		push_error("[CustomerArrivalData] 파일 열기 실패: " + PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	var hour_column: int = header.find("hour")
	var rate_column: int = header.find("rate")

	if hour_column < 0 or rate_column < 0:
		push_error("[CustomerArrivalData] hour/rate 열이 없습니다: " + PATH)
		return

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() <= maxi(hour_column, rate_column):
			continue

		var hour_text: String = row[hour_column].strip_edges()
		var rate_text: String = row[rate_column].strip_edges()

		if not hour_text.is_valid_int() or not rate_text.is_valid_float():
			continue

		rates[int(hour_text)] = maxf(float(rate_text), 0.0)


static func get_rate(hour: int) -> float:
	ensure_loaded()

	return float(
		rates.get(
			posmod(hour, 24),
			0.0
		)
	)
