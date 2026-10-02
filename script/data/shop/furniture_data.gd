class_name FurnitureData
extends RefCounted


const DATA_PATH: String = (
	"res://data/shop/catalogs/furniture_items.csv"
)


# =========================
# 기본 가구 분류
# =========================

const CATEGORY_SALES: String = "sales"
const CATEGORY_PRODUCTION: String = "production"
const CATEGORY_STORAGE: String = "storage"
const CATEGORY_FACILITY: String = "facility"
const CATEGORY_DECORATION: String = "decoration"


const VALID_CATEGORIES: Array[String] = [
	CATEGORY_SALES,
	CATEGORY_PRODUCTION,
	CATEGORY_STORAGE,
	CATEGORY_FACILITY,
	CATEGORY_DECORATION
]


# =========================
# 제작 화면 분류
# =========================

const CRAFT_CATEGORY_STORE: String = "store"
const CRAFT_CATEGORY_PRODUCTION: String = "production"
const CRAFT_CATEGORY_INTERIOR: String = "interior"
const CRAFT_CATEGORY_CONSTRUCTION: String = "construction"


const VALID_CRAFT_CATEGORIES: Array[String] = [
	CRAFT_CATEGORY_STORE,
	CRAFT_CATEGORY_PRODUCTION,
	CRAFT_CATEGORY_INTERIOR,
	CRAFT_CATEGORY_CONSTRUCTION
]


# =========================
# 인테리어 효과
# =========================

const EFFECT_REPUTATION: String = "reputation"
const EFFECT_PURCHASE_DESIRE: String = "purchase_desire"
const EFFECT_CUSTOMER_WEIGHT: String = "customer_weight"


const VALID_EFFECT_TYPES: Array[String] = [
	"",
	EFFECT_REPUTATION,
	EFFECT_PURCHASE_DESIRE,
	EFFECT_CUSTOMER_WEIGHT
]


# =========================
# 데이터 저장
# =========================

static var furniture: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	load_data()


static func load_data() -> void:
	furniture.clear()
	_loaded = false

	if not FileAccess.file_exists(DATA_PATH):
		push_error(
			"[FurnitureData] 파일 없음: "
			+ DATA_PATH
		)
		return

	var file := FileAccess.open(
		DATA_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[FurnitureData] 파일 열기 실패: "
			+ DATA_PATH
		)
		return

	if file.eof_reached():
		file.close()

		push_error(
			"[FurnitureData] CSV가 비어 있습니다."
		)
		return

	# =========================
	# 헤더 검사
	# =========================

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for index in range(header.size()):
		var column_name: String = str(
			header[index]
		).strip_edges()

		if column_name.is_empty():
			continue

		if indexes.has(column_name):
			file.close()

			push_error(
				"[FurnitureData] 중복된 CSV 열: "
				+ column_name
			)
			return

		indexes[column_name] = index

	var required_headers: Array[String] = [
		"id",
		"name",
		"category",
		"icon_path",
		"description",
		"craft_category",
		"effect_type",
		"effect_value",
		"effect_target"
	]

	for column in required_headers:
		if indexes.has(column):
			continue

		file.close()

		push_error(
			"[FurnitureData] CSV 열 없음: "
			+ column
		)
		return

	# 완전히 검증된 뒤에만 실제 데이터에 적용한다.
	var loaded_data: Dictionary = {}
	var line_number: int = 1

	# =========================
	# 행 읽기
	# =========================

	while file.get_position() < file.get_length():
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		line_number += 1

		if row.is_empty():
			continue

		if (
			row.size() == 1
			and row[0].strip_edges().is_empty()
		):
			continue

		var data: Dictionary = {}

		for column in required_headers:
			var column_index: int = int(
				indexes[column]
			)

			if column_index >= row.size():
				file.close()

				push_error(
					"[FurnitureData] 열 수 부족 / 줄: "
					+ str(line_number)
					+ " / 열: "
					+ column
				)
				return

			data[column] = str(
				row[column_index]
			).strip_edges()

		# =========================
		# 기본 정보 검사
		# =========================

		var furniture_id: String = str(
			data["id"]
		)

		var furniture_name: String = str(
			data["name"]
		)

		var category: String = str(
			data["category"]
		)

		var icon_path: String = str(
			data["icon_path"]
		)

		var description: String = str(
			data["description"]
		)

		var craft_category: String = str(
			data["craft_category"]
		)

		var effect_type: String = str(
			data["effect_type"]
		)

		var effect_target: String = str(
			data["effect_target"]
		)

		if effect_type == EFFECT_CUSTOMER_WEIGHT:
			if effect_target.is_empty():
				file.close()
				push_error(
					"[FurnitureData] customer_weight의 대상 없음 / ID: "
					+ furniture_id
				)
				return

			if not CustomerTypeData.has_customer_target(effect_target):
				file.close()
				push_error(
					"[FurnitureData] 등록되지 않은 대상 손님 / 가구: "
					+ furniture_id
					+ " / 손님: "
					+ effect_target
				)
				return
		elif not effect_target.is_empty():
			file.close()
			push_error(
				"[FurnitureData] customer_weight만 effect_target 사용 가능 / ID: "
				+ furniture_id
			)
			return

		if furniture_id.is_empty():
			file.close()

			push_error(
				"[FurnitureData] 가구 ID가 비어 있음 / 줄: "
				+ str(line_number)
			)
			return

		if furniture_name.is_empty():
			file.close()

			push_error(
				"[FurnitureData] 가구 이름이 비어 있음 / ID: "
				+ furniture_id
			)
			return

		if loaded_data.has(furniture_id):
			file.close()

			push_error(
				"[FurnitureData] 중복 ID: "
				+ furniture_id
			)
			return

		if not VALID_CATEGORIES.has(category):
			file.close()

			push_error(
				"[FurnitureData] 잘못된 category / ID: "
				+ furniture_id
				+ " / 값: "
				+ category
			)
			return

		if not VALID_CRAFT_CATEGORIES.has(
			craft_category
		):
			file.close()

			push_error(
				"[FurnitureData] 잘못된 craft_category / ID: "
				+ furniture_id
				+ " / 값: "
				+ craft_category
			)
			return

		if not VALID_EFFECT_TYPES.has(
			effect_type
		):
			file.close()

			push_error(
				"[FurnitureData] 잘못된 effect_type / ID: "
				+ furniture_id
				+ " / 값: "
				+ effect_type
			)
			return

		# =========================
		# 효과 숫자 검사
		# =========================

		var effect_value_text: String = str(
			data["effect_value"]
		)

		if not effect_value_text.is_valid_float():
			file.close()

			push_error(
				"[FurnitureData] 잘못된 effect_value / ID: "
				+ furniture_id
				+ " / 값: "
				+ effect_value_text
			)
			return

		var effect_value: float = float(
			effect_value_text
		)

		if (
			not is_finite(effect_value)
			or effect_value < 0.0
		):
			file.close()

			push_error(
				"[FurnitureData] effect_value 범위 오류 / ID: "
				+ furniture_id
			)
			return


		# =========================
		# 효과 조합 검사
		# =========================

		if effect_type.is_empty():
			if effect_value != 0.0:
				file.close()

				push_error(
					"[FurnitureData] 효과 없는 가구의 설정 오류 / ID: "
					+ furniture_id
				)
				return
		else:
			if category != CATEGORY_DECORATION:
				file.close()

				push_error(
					"[FurnitureData] 효과 가구의 category는 decoration이어야 함 / ID: "
					+ furniture_id
				)
				return

			if (
				craft_category
				!= CRAFT_CATEGORY_INTERIOR
			):
				file.close()

				push_error(
					"[FurnitureData] 효과 가구의 craft_category는 interior여야 함 / ID: "
					+ furniture_id
				)
				return

			if effect_value <= 0.0:
				file.close()

				push_error(
					"[FurnitureData] 인테리어 효과 설정 오류 / ID: "
					+ furniture_id
				)
				return

		# =========================
		# 아이콘 로딩
		# =========================

		var icon: Texture2D = null

		if not icon_path.is_empty():
			if not ResourceLoader.exists(icon_path):
				push_warning(
					"[FurnitureData] 아이콘 없음 / ID: "
					+ furniture_id
					+ " / 경로: "
					+ icon_path
				)
			else:
				icon = load(
					icon_path
				) as Texture2D

				if icon == null:
					push_warning(
						"[FurnitureData] 아이콘 형식 오류 / ID: "
						+ furniture_id
					)

		# =========================
		# 최종 데이터 저장
		# =========================

		loaded_data[furniture_id] = {
			"id": furniture_id,
			"name": furniture_name,
			"category": category,
			"icon_path": icon_path,
			"icon": icon,
			"description": description,
			"craft_category": craft_category,
			"effect_type": effect_type,
			"effect_target": effect_target,
			"effect_value": effect_value
		}

	file.close()

	furniture = loaded_data
	_loaded = true

	DebugLog.write(
		"[FurnitureData] 로드 완료 / 가구 수: ",
		furniture.size()
	)


# =========================
# 기본 조회
# =========================

static func has_furniture(
	furniture_id: String
) -> bool:
	ensure_loaded()

	return furniture.has(
		furniture_id
	)


static func get_furniture(
	furniture_id: String
) -> Dictionary:
	ensure_loaded()

	if not furniture.has(furniture_id):
		return {}

	return furniture[
		furniture_id
	].duplicate(true)


static func get_furniture_name(
	furniture_id: String
) -> String:
	var data: Dictionary = get_furniture(
		furniture_id
	)

	if data.is_empty():
		return furniture_id

	return str(
		data.get(
			"name",
			furniture_id
		)
	)

static func get_furniture_icon(
	furniture_id: String
) -> Texture2D:
	var data: Dictionary = get_furniture(
		furniture_id
	)

	if data.is_empty():
		return null

	return data.get(
		"icon",
		null
	) as Texture2D

static func get_all_furniture() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for data in furniture.values():
		result.append(
			data.duplicate(true)
		)

	return result


# =========================
# 분류 조회
# =========================

static func get_by_category(
	category: String
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for data in furniture.values():
		if str(
			data.get(
				"category",
				""
			)
		) != category:
			continue

		result.append(
			data.duplicate(true)
		)

	return result


static func get_by_craft_category(
	craft_category: String
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for data in furniture.values():
		if str(
			data.get(
				"craft_category",
				""
			)
		) != craft_category:
			continue

		result.append(
			data.duplicate(true)
		)

	return result


# =========================
# 효과 조회
# =========================

static func has_effect(
	furniture_id: String
) -> bool:
	var data: Dictionary = get_furniture(
		furniture_id
	)

	if data.is_empty():
		return false

	return not str(
		data.get(
			"effect_type",
			""
		)
	).is_empty()


static func get_effect_data(
	furniture_id: String
) -> Dictionary:
	var data: Dictionary = get_furniture(
		furniture_id
	)

	if data.is_empty():
		return {}

	var effect_type: String = str(
		data.get(
			"effect_type",
			""
		)
	)

	if effect_type.is_empty():
		return {}

	return {
		"effect_type": effect_type,

		"effect_target": str(
			data.get(
				"effect_target",
				""
			)
		),

		"effect_value": float(
			data.get(
				"effect_value",
				0.0
			)
		)
	}
