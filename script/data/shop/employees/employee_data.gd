class_name EmployeeData
extends RefCounted

const DATA_PATH: String = "res://data/shop/employees/employees.csv"

# 모든 직원에게 공통으로 적용
const PREFERRED_WORK_SPEED_MULTIPLIER: float = 1.2

const PERIOD_NAMES: Dictionary = {
	"morning": "아침",
	"day": "낮",
	"evening": "저녁",
	"night": "심야"
}

static var employees: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_error("[직원 데이터] 파일 열기 실패: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for index in range(header.size()):
		indexes[header[index].strip_edges()] = index

	var required_headers: Array[String] = [
		"employee_id",
		"display_name",
		"speed",
		"checkout_time",
		"restock_time",
		"can_checkout",
		"can_restock",
		"default_work_periods",
		"hire_cost",
		"initially_hired",
		"preferred_period",
		"monthly_salary"
	]

	for column in required_headers:
		if not indexes.has(column):
			file.close()
			push_error("[직원 데이터] CSV 열 없음: " + column)
			return

	var loaded_data: Dictionary = {}
	var line_number: int = 1

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		line_number += 1

		if row.is_empty():
			continue

		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue

		var data: Dictionary = {}

		for column in required_headers:
			var index: int = int(indexes[column])

			if index >= row.size():
				file.close()
				push_error(
					"[직원 데이터] 열 수 부족 / 줄: "
					+ str(line_number)
				)
				return

			data[column] = row[index].strip_edges()

		var valid: bool = (
			not str(data["employee_id"]).is_empty()
			and not str(data["display_name"]).is_empty()
			and not loaded_data.has(data["employee_id"])
			and PERIOD_NAMES.has(data["preferred_period"])
		)

		for key in ["speed", "checkout_time", "restock_time"]:
			var value_text: String = str(data[key])

			if not value_text.is_valid_float():
				valid = false
				continue

			var value: float = float(value_text)

			if not is_finite(value) or value <= 0.0:
				valid = false

			data[key] = value

		for key in [
			"hire_cost",
			"monthly_salary"
		]:
			var value_text: String = str(data[key])

			if not value_text.is_valid_int():
				valid = false
				continue

			var value: int = int(value_text)

			if value < 0:
				valid = false

			data[key] = value

		for key in [
			"can_checkout",
			"can_restock",
			"initially_hired"
		]:
			var value_text: String = str(data[key]).to_lower()

			if value_text != "true" and value_text != "false":
				valid = false

			data[key] = value_text == "true"

		var periods: Array[String] = []
		var periods_text: String = str(
			data["default_work_periods"]
		).strip_edges()

		if not periods_text.is_empty():
			for raw_period in periods_text.split("|"):
				periods.append(raw_period.strip_edges())

		if not is_work_periods_valid(periods):
			valid = false

		data["default_work_periods"] = periods

		if not valid:
			file.close()
			push_error(
				"[직원 데이터] 잘못된 값 또는 중복 ID / 줄: "
				+ str(line_number)
			)
			return

		loaded_data[data["employee_id"]] = data

	file.close()

	employees = loaded_data
	_loaded = true


static func get_employee(employee_id: String) -> Dictionary:
	ensure_loaded()

	if not employees.has(employee_id):
		return {}

	return employees[employee_id].duplicate(true)

static func get_monthly_salary(
	employee_id: String
) -> int:
	var employee: Dictionary = get_employee(
		employee_id
	)

	if employee.is_empty():
		return 0

	return maxi(
		int(employee.get("monthly_salary", 0)),
		0
	)


static func get_period_name(period: String) -> String:
	return str(PERIOD_NAMES.get(period, period))

# 하루의 시간대를 시간 순서대로 둔 고리(심야 → 아침 → 낮 → 저녁 → 심야).
const PERIOD_CYCLE: Array[String] = ["night", "morning", "day", "evening"]

# 근무표는 시간대가 겹치지 않는 최대 2개, 두 개일 때는 이어진 시간대여야 한다
# (심야+아침, 아침+낮, 낮+저녁, 저녁+심야). 자정을 넘는 저녁+심야도 이어진 것으로 본다.
static func is_work_periods_valid(periods: Array[String]) -> bool:
	if periods.is_empty():
		return true

	var unique: Array[String] = []

	for period in periods:
		if not PERIOD_NAMES.has(period):
			return false

		if unique.has(period):
			return false

		unique.append(period)

	if unique.size() > 2:
		return false

	if unique.size() == 2:
		var gap: int = absi(
			PERIOD_CYCLE.find(unique[0])
			- PERIOD_CYCLE.find(unique[1])
		)

		# 고리에서 이웃이면 차이가 1 또는 3(처음과 끝)이다.
		return gap == 1 or gap == PERIOD_CYCLE.size() - 1

	return true


static func get_period_at_hour(hour: int) -> String:
	if hour < 0 or hour > 23:
		return ""

	if (
		hour >= GameConfig.MORNING_PERIOD_START_HOUR
		and hour < GameConfig.DAY_PERIOD_START_HOUR
	):
		return "morning"

	if (
		hour >= GameConfig.DAY_PERIOD_START_HOUR
		and hour < GameConfig.EVENING_PERIOD_START_HOUR
	):
		return "day"

	if hour >= GameConfig.EVENING_PERIOD_START_HOUR:
		return "evening"

	return "night"

static func get_all_employee_ids() -> Array[String]:
	ensure_loaded()

	var result: Array[String] = []

	for raw_id in employees:
		result.append(str(raw_id))

	return result
