class_name Furniture3DData
extends RefCounted
## 가구의 3D 표현 값(높이 등). 값은 data/shop/catalogs/furniture_3d.csv 에 있다(코드에 박지 않음).

const DATA_PATH: String = "res://data/shop/catalogs/furniture_3d.csv"
const DEFAULT_ROW: Dictionary = {"kind": "box", "height_blocks": 1.0, "depth_ratio": 1.0, "stack_step_blocks": 0.0, "base_blocks": 0.0, "texture": "plank", "tint": Color.WHITE}

static var _rows: Dictionary = {}
static var _loaded: bool = false


static func get_row(build_id: String) -> Dictionary:
	if not _loaded:
		_load()

	return _rows.get(build_id, DEFAULT_ROW)


static func _load() -> void:
	_loaded = true
	_rows.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_warning("[Furniture3DData] 파일 없음: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() < header.size() or cells[0].strip_edges().is_empty():
			continue

		var d: Dictionary = {}

		for i in range(header.size()):
			d[header[i].strip_edges()] = cells[i].strip_edges()

		_rows[d["build_id"]] = {
			"kind": d["kind"],
			"height_blocks": float(d["height_blocks"]),
			"depth_ratio": float(d["depth_ratio"]),
			"stack_step_blocks": float(d["stack_step_blocks"]),
			"base_blocks": float(d.get("base_blocks", "0")),
			"texture": d["texture"],
			"tint": Color.html(d["tint"]),
		}
