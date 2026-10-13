class_name ShopPricingData
extends RefCounted
## 가격 단계·손님 민감도·계수를 CSV에서 읽는다(`data/shop/catalogs/economy/pricing_*.csv`). 수치는 코드에 박지 않는다.

const STEPS_PATH: String = "res://data/shop/catalogs/economy/pricing_steps.csv"
const SENSITIVITY_PATH: String = "res://data/shop/catalogs/economy/pricing_sensitivity.csv"
const SETTINGS_PATH: String = "res://data/shop/catalogs/economy/pricing_settings.csv"
const DEFAULT_STEPS: Dictionary = {0: {"label": "기본", "multiplier": 1.0}}
const DEFAULT_SETTINGS: Dictionary = {"expensive_slope": 1.2, "cheap_bonus_slope": 1.5, "min_accept": 0.05, "max_bonus": 0.9}

static var steps: Dictionary = {}          # step(int) -> {label, multiplier}
static var sensitivity: Dictionary = {}    # group_id -> float
static var settings: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	steps = _read(STEPS_PATH, "step", func(row: PackedStringArray, ix: Dictionary) -> Variant:
		return {"label": CsvReader.get_cell(row, ix, "label"), "multiplier": float(CsvReader.get_cell(row, ix, "multiplier"))})
	sensitivity = _read(SENSITIVITY_PATH, "group_id", func(row: PackedStringArray, ix: Dictionary) -> Variant:
		return float(CsvReader.get_cell(row, ix, "sensitivity")))
	settings = _read(SETTINGS_PATH, "key", func(row: PackedStringArray, ix: Dictionary) -> Variant:
		return float(CsvReader.get_cell(row, ix, "value")))
	if steps.is_empty():
		steps = DEFAULT_STEPS.duplicate(true)
	for key in DEFAULT_SETTINGS:
		if not settings.has(key):
			settings[key] = DEFAULT_SETTINGS[key]


static func reload_data() -> void:
	_loaded = false
	ensure_loaded()


# 단계 번호 목록(작은 값부터).
static func step_ids() -> Array:
	ensure_loaded()
	var ids: Array = steps.keys()
	ids.sort()
	return ids


static func _read(path: String, key_column: String, build: Callable) -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[ShopPricingData] 파일 없음: " + path)
		return result
	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}
	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		var key: String = CsvReader.get_cell(row, indexes, key_column)
		if key.is_empty() or key.begins_with("#"):
			continue
		var value: Variant = build.call(row, indexes)
		result[int(key) if key_column == "step" else key] = value
	return result
