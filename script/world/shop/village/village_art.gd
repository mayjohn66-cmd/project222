class_name VillageArt
extends Node2D
## 마을 건물·소품의 "그림 자리표". 예전에는 2D 스프라이트(Sprite2D)로 그림을 그렸지만, 지금은 3D 거울(StoreView3D)이 모양을 그리므로
## 이미지를 읽지 않고 어떤 그림이었는지(art_path)와 크기(data/shop/catalogs/village_art.csv)만 기록한다.
## 3D 쪽은 art_path 로 건물·소품 종류(규칙)를, 이미지 높이 × 배율(scale)로 소품 높이를 정한다. 위치·배율은 Node2D 값을 그대로 쓴다.

const DATA_PATH: String = "res://data/shop/catalogs/village_art.csv"

## 원래 그림의 res:// 경로. 복제(duplicate)해도 따라가도록 export 로 둔다.
@export var art_path: String = ""

static var _sizes: Dictionary = {}
static var _loaded: bool = false


static func _load() -> void:
	_loaded = true
	_sizes.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_warning("[VillageArt] 파일 없음: " + DATA_PATH)
		return

	file.get_csv_line()

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() >= 3 and not row[0].is_empty():
			_sizes[row[0].strip_edges()] = Vector2(float(row[1]), float(row[2]))


## 그림 원본 크기(px). 기록이 없으면 (0, 0).
static func size_of(path: String) -> Vector2:
	if not _loaded:
		_load()

	return _sizes.get(path, Vector2.ZERO)


func get_art_size() -> Vector2:
	return size_of(art_path)
