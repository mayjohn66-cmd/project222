class_name OpeningStoreLayout
extends RefCounted
## 프롤로그 가게 안 집기 배치(연출용). 파일(`data/shop/opening_store_layout.json`)이 있으면 그것을, 없으면 `default_props()`를 쓴다.
## 개발자 모드(F10, `OpeningLayoutEditor`)에서 배치하고 저장하면 이 파일이 만들어진다. 청소 더미·손님 동선·점원 자리는 이 배치에서 자동으로 정해진다.
## 칸 좌표: 문 (0,4), 매장은 (0..9, 0..7). rot 0 이면 앞면(상품·손님 쪽)이 +y(화면 앞), 1 은 +x, 2 는 -y, 3 은 -x.

const PATH := "res://data/shop/opening_store_layout.json"
const USER_PATH := "user://opening_store_layout.json"
const STORE_CELLS := Rect2i(0, 0, 10, 8)

# 종류별 기본 크기(길이 방향 칸 수)와 두께(칸). 개발자 모드의 "종류 바꾸기"와 새로 놓기에 쓴다.
const KINDS := {
	"cooler": {"length": 1, "depth": 0.85, "name": "음료 냉장고"},
	"gondola": {"length": 3, "depth": 0.55, "name": "진열대"},
	"chest": {"length": 2, "depth": 0.9, "name": "아이스크림 쇼케이스"},
	"counter": {"length": 3, "depth": 0.8, "name": "계산대"},
	"rack": {"length": 1, "depth": 0.5, "name": "상품 걸이"},
	"table": {"length": 1, "depth": 1.0, "name": "취식 탁자"},
	"cabinet": {"length": 2, "depth": 0.8, "name": "커피 기계 장"},
}
const KIND_ORDER := ["cooler", "gondola", "chest", "counter", "rack", "table", "cabinet"]

static var _props: Array = []
static var _loaded: bool = false


static func default_props() -> Array:
	return [
		_p("cooler", 2, 0, 1, 1, 0), _p("cooler", 3, 0, 1, 1, 0), _p("cooler", 4, 0, 1, 1, 0),
		_p("cooler", 5, 0, 1, 1, 0), _p("cooler", 6, 0, 1, 1, 0), _p("cooler", 7, 0, 1, 1, 0),
		_p("chest", 8, 0, 2, 1, 0),
		_p("gondola", 0, 1, 1, 2, 1), _p("gondola", 0, 6, 1, 2, 1),
		_p("gondola", 2, 2, 3, 1, 0), _p("gondola", 6, 2, 3, 1, 0),
		_p("gondola", 3, 4, 3, 1, 0), _p("gondola", 7, 4, 2, 1, 0),
		_p("counter", 6, 6, 3, 1, 0),
	]


static func _p(model: String, x: int, y: int, w: int, h: int, rot: int) -> Dictionary:
	return {"model": model, "anchor": Vector2i(x, y), "size": Vector2i(w, h), "depth": float(KINDS[model]["depth"]), "rot": rot}


static func props() -> Array:
	if not _loaded:
		reload()

	return _props


static func reload() -> void:
	_loaded = true
	# 프로젝트 파일(저장소에 올라가는 것)을 먼저, 없으면 사용자 폴더의 것을 쓴다(오래된 사용자 파일이 저장소 파일을 덮어쓰지 않게).
	_props = _read(PATH)

	if _props.is_empty():
		_props = _read(USER_PATH)

	if _props.is_empty():
		_props = default_props()


static func set_props(list: Array) -> void:
	_props = list
	_loaded = true


# 저장: 프로젝트 파일(편집기에서 실행했을 때)과 사용자 폴더 둘 다에 쓴다. 실패한 쪽의 오류 문구를 돌려준다(성공이면 빈 문자열).
static func save() -> String:
	var json: String = JSON.stringify({"version": 1, "props": _to_json(props())}, "\t")
	var errors: Array[String] = []

	for path in [PATH, USER_PATH]:
		var file := FileAccess.open(path, FileAccess.WRITE)

		if file == null:
			errors.append("%s: 쓸 수 없음" % path)
			continue

		file.store_string(json)

	return "" if errors.size() < 2 else "; ".join(errors)


static func rect_of(prop: Dictionary) -> Rect2:
	var anchor: Vector2i = prop["anchor"]
	var size: Vector2i = prop["size"]
	var lo := Vector2(float(anchor.x) - 0.5, float(anchor.y) - 0.5)
	var hi := Vector2(float(anchor.x + size.x) - 0.5, float(anchor.y + size.y) - 0.5)
	var depth: float = float(prop["depth"])

	match posmod(int(prop["rot"]), 4):
		0:
			hi.y = lo.y + depth
		1:
			hi.x = lo.x + depth
		2:
			lo.y = hi.y - depth
		3:
			lo.x = hi.x - depth

	return Rect2(lo, hi - lo)


# 집기가 놓이는 칸 사각형(걷지 못하는 칸 계산용)
static func cells_of(prop: Dictionary) -> Rect2i:
	var anchor: Vector2i = prop["anchor"]
	return Rect2i(anchor, prop["size"])


# 칸 크기와 두께를 종류·회전에 맞게 만든 새 집기
static func make(model: String, anchor: Vector2i, rot: int) -> Dictionary:
	var info: Dictionary = KINDS[model]
	var length: int = int(info["length"])
	var along_x: bool = posmod(rot, 2) == 0
	return {"model": model, "anchor": anchor, "size": Vector2i(length, 1) if along_x else Vector2i(1, length), "depth": float(info["depth"]), "rot": posmod(rot, 4)}


static func _read(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))

	if not parsed is Dictionary or not (parsed as Dictionary).has("props"):
		return []

	var result: Array = []

	for raw in (parsed as Dictionary)["props"]:
		if not raw is Dictionary or not KINDS.has(str(raw.get("model", ""))):
			continue

		var anchor: Array = raw.get("anchor", [0, 0])
		var size: Array = raw.get("size", [1, 1])
		result.append({
			"model": str(raw["model"]),
			"anchor": Vector2i(int(anchor[0]), int(anchor[1])),
			"size": Vector2i(maxi(1, int(size[0])), maxi(1, int(size[1]))),
			"depth": float(raw.get("depth", KINDS[str(raw["model"])]["depth"])),
			"rot": posmod(int(raw.get("rot", 0)), 4),
		})

	return result


static func _to_json(list: Array) -> Array:
	var out: Array = []

	for prop in list:
		var a: Vector2i = prop["anchor"]
		var s: Vector2i = prop["size"]
		out.append({"model": prop["model"], "anchor": [a.x, a.y], "size": [s.x, s.y], "depth": prop["depth"], "rot": prop["rot"]})

	return out
