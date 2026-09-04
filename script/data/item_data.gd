extends Node


const REQUIRED_FIELDS: Array[String] = [
	"name",
	"category",
	"price",
	"icon",
	"shelf_allowed",
	"sellable"
]


const CATEGORY_FOOD: String = "food"
const CATEGORY_POTION: String = "potion"
const CATEGORY_TOOL: String = "tool"
const CATEGORY_ETC: String = "etc"


const VALID_CATEGORIES: Array[String] = [
	CATEGORY_FOOD,
	CATEGORY_POTION,
	CATEGORY_TOOL,
	CATEGORY_ETC
]

# =========================================================
# 아이템 데이터
# =========================================================

var items: Dictionary = {}


# =========================================================
# 기본 조회
# =========================================================

func _ready():
	load_item_catalog()

	var valid := validate_all_items()

	if valid:
		print(
			"[ItemData] 데이터 검증 완료 / 아이템 수: ",
			items.size()
		)

func load_item_catalog():
	items = ItemCatalog.ITEMS.duplicate(true)

func has_item(
	item_id: String
) -> bool:
	return items.has(item_id)


func get_item(
	item_id: String
) -> Dictionary:
	if not items.has(item_id):
		return {}

	return items[item_id]


func get_item_name(
	item_id: String
) -> String:
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return item_id

	return str(
		data.get(
			"name",
			item_id
		)
	)


func get_item_price(
	item_id: String
) -> int:
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return 0

	return int(
		data.get(
			"price",
			0
		)
	)


func get_item_category(
	item_id: String
) -> String:
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return ""

	return str(
		data.get(
			"category",
			""
		)
	)


func get_item_icon(
	item_id: String
):
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return null

	return data.get(
		"icon",
		null
	)



# =========================================================
# 카테고리
# =========================================================

func get_items_by_category(
	category: String
) -> Array[String]:
	var result: Array[String] = []

	for item_id in items.keys():
		var id: String = str(item_id)

		if get_item_category(id) != category:
			continue

		result.append(id)

	return result

func validate_all_items() -> bool:
	var all_valid := true

	for raw_item_id in items.keys():
		var item_id: String = str(raw_item_id)
		var data = items[item_id]

		if not data is Dictionary:
			push_error(
				"[ItemData] 아이템 데이터가 Dictionary가 아님: "
				+ item_id
			)
			all_valid = false
			continue

		# =========================
		# 필수 필드 검사
		# =========================

		var missing_field := false

		for field_name in REQUIRED_FIELDS:
			if data.has(field_name):
				continue

			push_error(
				"[ItemData] 필수 필드 누락: "
				+ item_id
				+ " / "
				+ field_name
			)

			all_valid = false
			missing_field = true

		if missing_field:
			continue

		# =========================
		# 이름 검사
		# =========================

		var item_name: String = str(
			data.get(
				"name",
				""
			)
		)

		if item_name.strip_edges().is_empty():
			push_error(
				"[ItemData] 이름이 비어 있음: "
				+ item_id
			)

			all_valid = false

		# =========================
		# 카테고리 검사
		# =========================

		var category: String = str(
			data.get(
				"category",
				""
			)
		)

		if not VALID_CATEGORIES.has(category):
			push_error(
				"[ItemData] 잘못된 카테고리: "
				+ item_id
				+ " / "
				+ category
			)

			all_valid = false

		# =========================
		# 가격 검사
		# =========================

		var price_value = data.get(
			"price",
			0
		)

		if not (
			price_value is int
			or price_value is float
		):
			push_error(
				"[ItemData] 가격이 숫자가 아님: "
				+ item_id
			)

			all_valid = false

		elif int(price_value) < 0:
			push_error(
				"[ItemData] 가격이 음수임: "
				+ item_id
				+ " / "
				+ str(price_value)
			)

			all_valid = false


		# =========================
		# 아이콘 검사
		# =========================

		var icon_value = data.get(
			"icon",
			null
		)

		if icon_value == null:
			push_warning(
				"[ItemData] 아이콘 없음: "
				+ item_id
			)

	return all_valid

func is_shelf_allowed(
	item_id: String
) -> bool:
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return false

	return bool(
		data.get(
			"shelf_allowed",
			false
		)
	)


func is_sellable(
	item_id: String
) -> bool:
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return false

	return bool(
		data.get(
			"sellable",
			false
		)
	)

func get_sellable_items() -> Array[String]:
	var result: Array[String] = []

	for raw_item_id in items.keys():
		var item_id: String = str(raw_item_id)

		if is_sellable(item_id):
			result.append(item_id)

	return result
