class_name CheckoutData
extends RefCounted
## 계산 손맛(손님 인내심·스캔 타이밍·팁) 수치를 CSV에서 읽는다(`data/shop/catalogs/economy/checkout_settings.csv`).

const PATH: String = "res://data/shop/catalogs/economy/checkout_settings.csv"
const DEFAULTS: Dictionary = {
	"patience_seconds": 40.0, "patience_warn_ratio": 0.5, "scan_sweep_seconds": 0.9,
	"scan_perfect_half": 0.07, "scan_good_half": 0.17, "scan_miss_limit": 2.0,
	"tip_rate": 0.05, "tip_min": 1.0,
}

static var values: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	values = DEFAULTS.duplicate()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("[CheckoutData] 파일 없음: " + PATH)
		return
	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}
	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		var key: String = CsvReader.get_cell(row, indexes, "key")
		if key.is_empty() or key.begins_with("#"):
			continue
		values[key] = float(CsvReader.get_cell(row, indexes, "value"))


static func reload_data() -> void:
	_loaded = false
	ensure_loaded()


static func value(key: String) -> float:
	ensure_loaded()
	return float(values.get(key, DEFAULTS.get(key, 0.0)))
