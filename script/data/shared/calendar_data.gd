class_name CalendarData
extends RefCounted


enum Season {
	SPRING,
	SUMMER,
	AUTUMN,
	WINTER
}


enum Weekday {
	MONDAY = 1,
	TUESDAY = 2,
	WEDNESDAY = 3,
	THURSDAY = 4,
	FRIDAY = 5,
	SATURDAY = 6,
	SUNDAY = 7
}


const DAYS_PER_WEEK: int = 7
const DAYS_PER_SEASON: int = 28
const SEASONS_PER_YEAR: int = 4
const DAYS_PER_YEAR: int = (
	DAYS_PER_SEASON
	* SEASONS_PER_YEAR
)


static func get_year(
	total_day: int
) -> int:
	var safe_day: int = maxi(
		total_day,
		1
	)

	return (
		floori(
			float(safe_day - 1)
			/ float(DAYS_PER_YEAR)
		)
		+ 1
	)


static func get_day_of_year(
	total_day: int
) -> int:
	var safe_day: int = maxi(
		total_day,
		1
	)

	return (
		(safe_day - 1)
		% DAYS_PER_YEAR
		+ 1
	)


static func get_season(
	total_day: int
) -> Season:
	var day_of_year: int = (
		get_day_of_year(total_day)
	)

	var season_index: int = floori(
		float(day_of_year - 1)
		/ float(DAYS_PER_SEASON)
	)

	return season_index as Season


static func get_season_id(
	total_day: int
) -> String:
	match get_season(total_day):
		Season.SPRING:
			return "spring"

		Season.SUMMER:
			return "summer"

		Season.AUTUMN:
			return "autumn"

		Season.WINTER:
			return "winter"

	return "spring"


static func get_season_name(
	total_day: int
) -> String:
	match get_season(total_day):
		Season.SPRING:
			return "봄"

		Season.SUMMER:
			return "여름"

		Season.AUTUMN:
			return "가을"

		Season.WINTER:
			return "겨울"

	return "봄"


static func get_day_of_season(
	total_day: int
) -> int:
	var day_of_year: int = (
		get_day_of_year(total_day)
	)

	return (
		(day_of_year - 1)
		% DAYS_PER_SEASON
		+ 1
	)


static func get_weekday(
	total_day: int
) -> int:
	var safe_day: int = maxi(
		total_day,
		1
	)

	return (
		(safe_day - 1)
		% DAYS_PER_WEEK
		+ 1
	)


static func get_display_date(
	total_day: int
) -> String:
	return (
		"%d년차 %s %d일"
		% [
			get_year(total_day),
			get_season_name(total_day),
			get_day_of_season(total_day)
		]
	)


