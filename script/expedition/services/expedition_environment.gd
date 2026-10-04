class_name ExpeditionEnvironment
extends RefCounted
const SEASONS := {"spring":"봄", "summer":"여름", "autumn":"가을", "winter":"겨울"}
const WEATHER := {"clear":"맑음", "rain":"비", "snow":"눈"}

static func capture() -> Dictionary:
	var context: Dictionary = GameState.get_meta("shop_return_context", {})
	var hour := float(context.get("hour", GameConfig.DAY_START_HOUR)) + float(context.get("minute", 0)) / 60.0
	var weather := WorldWeatherData.forecast(GameState.total_day, hour)
	return {"day":GameState.total_day, "hour":hour, "season":CalendarData.get_season_id(GameState.total_day), "weather":str(weather["kind"])}

static func matches(entry: Dictionary, environment: Dictionary) -> bool:
	var state := capture() if environment.is_empty() else environment
	for field in ["season", "weather"]:
		var filter := str(entry.get(field + "_filter", "")).strip_edges().to_lower()
		if not filter.is_empty() and filter != "any" and str(state.get(field, "")) not in filter.split("|"): return false
	return true

static func label(state: Dictionary) -> String:
	return "%s · %s" % [SEASONS.get(state.get("season", ""), "봄"), WEATHER.get(state.get("weather", ""), "맑음")]

static func preparation(region: String) -> String:
	var state := capture()
	var lines: Array[String] = [label(state)]
	var file := FileAccess.open("res://data/expedition/expedition_environment_hints.csv", FileAccess.READ)
	if file == null: return lines[0]
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 4: continue
		if region not in row[0].split("|"): continue
		if matches({"season_filter":row[1], "weather_filter":row[2]}, state): lines.append(row[3])
	return "\n".join(lines)

static func floor_tint(base: Color, state: Dictionary, grassy: bool) -> Color:
	if not grassy: return base
	match str(state.get("season", "")):
		"spring": return base.lerp(Color("66875c"), 0.18)
		"summer": return base.lerp(Color("386d43"), 0.18)
		"autumn": return base.lerp(Color("9a7046"), 0.35)
		"winter": return base.lerp(Color("b6cbd0"), 0.50)
	return base

static func ground_overlay(state: Dictionary, grassy: bool) -> Color:
	if not grassy: return Color.TRANSPARENT
	match str(state.get("season", "")):
		"spring": return Color(0.65, 0.86, 0.48, 0.06)
		"summer": return Color(0.2, 0.6, 0.25, 0.08)
		"autumn": return Color(0.72, 0.41, 0.19, 0.20)
		"winter": return Color(0.82, 0.90, 0.94, 0.36)
	return Color.TRANSPARENT
