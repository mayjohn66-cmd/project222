class_name WorldWeatherData
extends RefCounted
## 3D WeatherSystem과 같은 CSV·날짜 난수·시간 경계를 사용한다.
const PATH := "res://data/shop/catalogs/weather_3d.csv"
static var rows: Dictionary = {}

static func day_plan(day: int) -> Dictionary:
	if rows.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file != null:
			var header := file.get_csv_line()
			while not file.eof_reached():
				var cells := file.get_csv_line()
				if cells.size() < header.size(): continue
				var entry := {}
				for i in range(header.size()):
					entry[header[i]] = cells[i] if header[i] in ["season", "note"] else float(cells[i])
				rows[str(entry["season"])] = entry
	var t: Dictionary = rows.get(CalendarData.get_season_id(day), {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day * 7919 + 20261003)
	var roll := rng.randf()
	var kind := "clear"
	if roll < float(t.get("snow_chance", 0.0)): kind = "snow"
	elif roll < float(t.get("snow_chance", 0.0)) + float(t.get("rain_chance", 0.0)): kind = "rain"
	var length := rng.randf_range(float(t.get("min_hours", 3)), float(t.get("max_hours", 6)))
	var start := rng.randf_range(5.0, maxf(5.1, 22.0 - length))
	var lo := float(t.get("snow_min", 0.5)) if kind == "snow" else float(t.get("rain_min", 0.5))
	var hi := float(t.get("snow_max", 0.9)) if kind == "snow" else float(t.get("rain_max", 0.9))
	return {"kind":kind, "start":start, "end":start + length, "peak":rng.randf_range(lo, hi)}

static func forecast(day: int, hour: float) -> Dictionary:
	# 3D 브랜치가 합쳐지면 실제 WeatherSystem을 사용하여 F7 개발 날씨도 일치한다.
	if ResourceLoader.exists("res://script/world/view3d/weather_system.gd"):
		var shared = load("res://script/world/view3d/weather_system.gd")
		if shared != null and shared.has_method("forecast"): return shared.forecast(day, hour)
	var plan := day_plan(day)
	var h := fposmod(hour, 24.0)
	var up := clampf(h - float(plan["start"]), 0.0, 1.0)
	var down := clampf(float(plan["end"]) - h, 0.0, 1.0)
	var intensity := minf(up, down) * float(plan["peak"])
	return {"kind":plan["kind"] if plan["kind"] != "clear" and intensity > 0.001 else "clear", "intensity":intensity if plan["kind"] != "clear" else 0.0}
