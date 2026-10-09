class_name BuildObjectData
extends RefCounted


const DATA_PATH: String = (
	"res://data/shop/catalogs/build_objects.csv"
)


const PLACEMENT_NORMAL: String = "normal"
const PLACEMENT_WALL: String = "wall"


const VALID_PLACEMENT_RULES: Array[String] = [
	PLACEMENT_NORMAL,
	PLACEMENT_WALL
]

const BUILD_TYPE_SHELF: String = "shelf"
const BUILD_TYPE_REGISTER: String = "register"
const BUILD_TYPE_DOOR: String = "door"
const BUILD_TYPE_PRODUCTION_DOOR: String = "production_door"
const BUILD_TYPE_WAREHOUSE_DOOR: String = "warehouse_door"
const BUILD_TYPE_PRODUCTION_FACILITY: String = "production_facility"
const BUILD_TYPE_DECORATION: String = "decoration"
const BUILD_TYPE_WAREHOUSE_STORAGE: String = (
	"warehouse_storage"
)

const VALID_BUILD_TYPES: Array[String] = [
	BUILD_TYPE_SHELF,
	BUILD_TYPE_REGISTER,
	BUILD_TYPE_DOOR,
	BUILD_TYPE_PRODUCTION_DOOR,
	BUILD_TYPE_WAREHOUSE_DOOR,
	BUILD_TYPE_PRODUCTION_FACILITY,
	BUILD_TYPE_WAREHOUSE_STORAGE,
	BUILD_TYPE_DECORATION
]

static var objects: Dictionary = {}

# CSV에 작성된 가구 순서를 보존
static var object_ids: Array[String] = []

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	load_data()


static func load_data() -> void:
	objects.clear()
	object_ids.clear()

	if not FileAccess.file_exists(
		DATA_PATH
	):
		push_error(
			"[BuildObjectData] 파일 없음: "
			+ DATA_PATH
		)
		return

	var file := FileAccess.open(
		DATA_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[BuildObjectData] 파일 열기 실패"
		)
		return

	# 헤더 건너뛰기
	if not file.eof_reached():
		file.get_csv_line()

	while not file.eof_reached():
		var row := file.get_csv_line()

		if row.is_empty():
			continue

		if row.size() < 8:
			push_warning(
				"[BuildObjectData] 잘못된 행: "
				+ str(row)
			)
			continue

		var build_id := str(
			row[0]
		).strip_edges()

		if build_id.is_empty():
			continue

		if objects.has(build_id):
			push_warning(
				"[BuildObjectData] 중복된 build_id: "
				+ build_id
			)

			continue

		if build_id.is_empty():
			continue

		var scene_path := str(
			row[1]
		).strip_edges()

		var grid_w := int(
			row[2]
		)

		var grid_h := int(
			row[3]
		)

		var rotatable := (
			str(row[4]).strip_edges().to_lower()
			== "true"
		)

		var blocks_movement := (
			str(row[5]).strip_edges().to_lower()
			== "true"
		)

		var placement_rule := str(
			row[6]
		).strip_edges()

		var build_type: String = str(
			row[7]
		).strip_edges()

		var area_profile_path: String = ""

		if row.size() >= 9:
			area_profile_path = str(row[8]).strip_edges()

		# 기존 8열 CSV와 기본 계산대 설정 호환
		if (
			build_type == BUILD_TYPE_REGISTER
			and area_profile_path.is_empty()
		):
			area_profile_path = (
				"res://data/shop/catalogs/register_area_default.tres"
			)

		if not VALID_BUILD_TYPES.has(
			build_type
		):
			push_error(
				"[BuildObjectData] 잘못된 build_type: "
				+ build_id
				+ " / "
				+ build_type
			)

			continue

		if grid_w <= 0 or grid_h <= 0:
			push_error(
				"[BuildObjectData] 잘못된 grid size: "
				+ build_id
			)
			continue

		if not VALID_PLACEMENT_RULES.has(
			placement_rule
		):
			push_error(
				"[BuildObjectData] 잘못된 placement_rule: "
				+ build_id
				+ " / "
				+ placement_rule
			)
			continue

		if not ResourceLoader.exists(
			scene_path
		):
			push_error(
				"[BuildObjectData] 씬 없음: "
				+ build_id
				+ " / "
				+ scene_path
			)
			continue

		objects[build_id] = {
			"id": build_id,
			"scene_path": scene_path,
			"grid_size": Vector2i(
				grid_w,
				grid_h
			),
			"rotatable": rotatable,
			"blocks_movement": blocks_movement,
			"placement_rule": placement_rule,
			"build_type": build_type,
			"area_profile_path": area_profile_path
		}

		object_ids.append(build_id)

	_loaded = true


	DebugLog.write(
		"[BuildObjectData] 로드 완료 / 건축물 수: ",
		objects.size()
	)


static func has_build_object(
	build_id: String
) -> bool:
	ensure_loaded()

	return objects.has(
		build_id
	)


static func get_build_object(
	build_id: String
) -> Dictionary:
	ensure_loaded()

	if not objects.has(
		build_id
	):
		return {}

	return objects[
		build_id
	].duplicate(true)


static func get_build_scene(
	build_id: String
) -> PackedScene:
	var data := get_build_object(
		build_id
	)

	if data.is_empty():
		return null

	var scene_path := str(
		data.get(
			"scene_path",
			""
		)
	)

	if scene_path.is_empty():
		return null

	return load(
		scene_path
	) as PackedScene


static func get_build_type(
	build_id: String
) -> String:
	var data: Dictionary = (
		get_build_object(build_id)
	)

	if data.is_empty():
		return ""

	return str(
		data.get(
			"build_type",
			""
		)
	)

static func get_all_build_ids() -> Array[String]:
	ensure_loaded()

	var result: Array[String] = []

	for build_id in object_ids:
		result.append(build_id)

	return result

static func get_placement_rule(
	build_id: String
) -> String:
	var data: Dictionary = (
		get_build_object(build_id)
	)

	if data.is_empty():
		return ""

	return str(
		data.get(
			"placement_rule",
			""
		)
	)

static func is_rotatable(
	build_id: String
) -> bool:
	var data: Dictionary = (
		get_build_object(build_id)
	)

	if data.is_empty():
		return false

	return bool(
		data.get(
			"rotatable",
			false
		)
	)

static func get_register_area_profile(
	build_id: String
) -> RegisterAreaProfile:
	var data: Dictionary = get_build_object(build_id)

	if data.is_empty():
		return null

	if str(data.get("build_type", "")) != BUILD_TYPE_REGISTER:
		return null

	var path: String = str(
		data.get("area_profile_path", "")
	)

	if path.is_empty() or not ResourceLoader.exists(path):
		push_error(
			"[건축 데이터] 계산대 영역 리소스 없음: "
			+ build_id
			+ " / "
			+ path
		)
		return null

	var profile: RegisterAreaProfile = (
		load(path) as RegisterAreaProfile
	)

	if profile == null:
		push_error(
			"[건축 데이터] RegisterAreaProfile 타입이 아님: "
			+ path
		)

	return profile
