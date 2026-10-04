class_name WeatherSystem
extends RefCounted
## 날씨 계산(순수 함수, 저장할 값 없음). 날짜(total_day)와 시각만으로 "그날 몇 시부터 몇 시까지 비/눈"이 정해진다.
## 같은 날은 언제 불러도 같은 결과라서 저장·불러오기와 상관없이 일정하다. 확률·길이는 data/shop/catalogs/weather_3d.csv.
## 게임 쪽(손님 수 등)에서 쓰려면 WeatherSystem.forecast(GameState.total_day, 시각) 를 그냥 부르면 된다.

const CSV_PATH := "res://data/shop/catalogs/weather_3d.csv"
const FADE_HOURS: float = 1.0  # 시작·끝에서 서서히 세지고 약해지는 시간

static var _cache: Dictionary = {}
# 개발용 강제 날씨("" = 끔, clear/rain/snow). F7 키나 --weather 인자로 StoreView3D 가 넣는다.
static var debug_kind: String = ""
static var debug_intensity: float = 0.85


static func table(season_id: String) -> Dictionary:
	if _cache.is_empty():
		_load()

	return _cache.get(season_id, {"rain_chance": 0.0, "snow_chance": 0.0, "min_hours": 3.0, "max_hours": 6.0, "rain_min": 0.4, "rain_max": 0.8, "snow_min": 0.5, "snow_max": 0.8})


static func _load() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)

	if file == null:
		_cache["spring"] = {"rain_chance": 0.1, "snow_chance": 0.0, "min_hours": 3.0, "max_hours": 6.0, "rain_min": 0.4, "rain_max": 0.8, "snow_min": 0.5, "snow_max": 0.8}
		return

	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() < header.size() or cells[0].strip_edges().is_empty():
			continue

		var row: Dictionary = {}

		for i in range(header.size()):
			var key: String = header[i].strip_edges()
			row[key] = cells[i].strip_edges() if key in ["season", "note"] else float(cells[i])

		_cache[str(row["season"])] = row


# 그날의 날씨 일정: {"kind": "clear"|"rain"|"snow", "start": 시, "end": 시, "peak": 0.5~1.0}
static func day_plan(total_day: int) -> Dictionary:
	var t: Dictionary = table(SeasonStyle.season_of_day(total_day))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(total_day * 7919 + 20261003)
	var roll: float = rng.randf()
	var kind: String = "clear"

	if roll < float(t["snow_chance"]):
		kind = "snow"
	elif roll < float(t["snow_chance"]) + float(t["rain_chance"]):
		kind = "rain"

	var length: float = rng.randf_range(float(t["min_hours"]), float(t["max_hours"]))
	var start: float = rng.randf_range(5.0, maxf(5.1, 22.0 - length))
	var lo_k: float = float(t.get("snow_min", 0.5)) if kind == "snow" else float(t.get("rain_min", 0.5))
	var hi_k: float = float(t.get("snow_max", 0.9)) if kind == "snow" else float(t.get("rain_max", 0.9))
	return {"kind": kind, "start": start, "end": start + length, "peak": rng.randf_range(lo_k, hi_k)}


# 지금(날짜, 시각 0~24) 날씨: {"kind": 종류, "intensity": 0~1}. 맑으면 intensity 0.
static func forecast(total_day: int, hour: float) -> Dictionary:
	if debug_kind != "":
		return {"kind": debug_kind, "intensity": 0.0 if debug_kind == "clear" else debug_intensity}

	var plan: Dictionary = day_plan(total_day)

	if plan["kind"] == "clear":
		return {"kind": "clear", "intensity": 0.0}

	var h: float = fposmod(hour, 24.0)
	var up: float = clampf((h - float(plan["start"])) / FADE_HOURS, 0.0, 1.0)
	var down: float = clampf((float(plan["end"]) - h) / FADE_HOURS, 0.0, 1.0)
	var k: float = minf(up, down) * float(plan["peak"])

	if k <= 0.001:
		return {"kind": "clear", "intensity": 0.0}

	return {"kind": plan["kind"], "intensity": k}


static func kind_name(kind: String) -> String:
	match kind:
		"rain":
			return "비"
		"snow":
			return "눈"

	return "맑음"
