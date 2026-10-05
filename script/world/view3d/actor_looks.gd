class_name ActorLooks
extends RefCounted
## 사람마다 다른 외형(옷 색·모자·등짐·손 소품). 값은 data/shop/catalogs/actor_looks_3d.csv 에 있다(코드에 박지 않음).
## 손님은 소분류 id(없으면 대분류 id)로, 그 밖의 사람은 "player" "worker" 같은 역할 키로 찾는다. 빈 칸은 기본 외형 값을 쓴다.

const DATA_PATH: String = "res://data/shop/catalogs/actor_looks_3d.csv"
const COLOR_KEYS: Array = ["skin", "hair", "shirt", "apron", "pants", "shoe"]

static var _rows: Dictionary = {}
static var _loaded: bool = false


# key 에 해당하는 외형 사전. 없으면 빈 사전(= 기본 외형).
static func get_look(key: String) -> Dictionary:
	if not _loaded:
		_load()

	return _rows.get(key, {})


# 손님 소분류 id → 외형 키. 소분류 행이 없으면 대분류 id 로 대신한다.
static func customer_key(customer_type_id: String) -> String:
	if ActFourCustomers.TYPES.has(customer_type_id): customer_type_id = str(ActFourCustomers.TYPES[customer_type_id]["source"])
	if not _loaded:
		_load()

	if _rows.has(customer_type_id):
		return customer_type_id

	CustomerTypeData.ensure_loaded()
	var group_id: String = CustomerTypeData.get_group_id(customer_type_id)
	return group_id if _rows.has(group_id) else customer_type_id


static func _load() -> void:
	_loaded = true
	_rows.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_warning("[ActorLooks] 파일 없음: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() < header.size() or cells[0].strip_edges().is_empty():
			continue

		var look: Dictionary = {}

		for i in range(1, header.size()):
			var col: String = header[i].strip_edges()
			var v: String = cells[i].strip_edges()

			if v.is_empty():
				continue

			if col in COLOR_KEYS or col.ends_with("_color"):
				look[col] = Color.html(v)
			elif col == "total" or col == "head_ratio":
				look[col] = float(v)
			else:
				look[col] = v

		_rows[cells[0].strip_edges()] = look
