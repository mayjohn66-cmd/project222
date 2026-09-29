extends Node

const INVENTORY_GROUP_SHELF: String = "shelf"
const INVENTORY_GROUP_FURNITURE: String = "furniture"
const INVENTORY_GROUP_EXPEDITION: String = "expedition"

const CATEGORY_FOOD: String = "food"
const CATEGORY_CONSUMABLE: String = "consumable"
const CATEGORY_MATERIAL: String = "material"
const CATEGORY_TOOL: String = "tool"
const CATEGORY_ETC: String = "etc"

const ITEM_TYPE_STORE_PRODUCT: String = "store_product"
const ITEM_TYPE_MATERIAL: String = "material"
const ITEM_TYPE_EQUIPMENT: String = "equipment"
const ITEM_TYPE_EXPEDITION_CONSUMABLE: String = "expedition_consumable"
const ITEM_TYPE_SPECIAL: String = "special"

const EXPEDITION_STORAGE_BAG: String = "bag"
const EXPEDITION_STORAGE_INVENTORY: String = "inventory"


const VALID_INVENTORY_GROUPS: Array[String] = [
	INVENTORY_GROUP_SHELF,
	INVENTORY_GROUP_FURNITURE,
	INVENTORY_GROUP_EXPEDITION
]

const VALID_ITEM_TYPES: Array[String] = [
	ITEM_TYPE_STORE_PRODUCT,
	ITEM_TYPE_MATERIAL,
	ITEM_TYPE_EQUIPMENT,
	ITEM_TYPE_EXPEDITION_CONSUMABLE,
	ITEM_TYPE_SPECIAL
]

const VALID_CATEGORIES: Array[String] = [
	CATEGORY_FOOD,
	CATEGORY_CONSUMABLE,
	CATEGORY_MATERIAL,
	CATEGORY_TOOL,
	CATEGORY_ETC
]


const REQUIRED_FIELDS: Array[String] = [
	"name",
	"item_type",
	"category",
	"inventory_group",
	"price",
	"icon",
	"shelf_allowed",
	"sellable"
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
		DebugLog.write(
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

func get_inventory_group(
	item_id: String
) -> String:
	var data: Dictionary = get_item(
		item_id
	)

	if data.is_empty():
		return ""

	return str(
		data.get(
			"inventory_group",
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
		# 통합 인벤토리 분류 검사
		# =========================

		var inventory_group: String = str(
			data.get(
				"inventory_group",
				""
			)
		)

		if not VALID_INVENTORY_GROUPS.has(
			inventory_group
		):
			push_error(
				"[ItemData] 잘못된 inventory_group: "
				+ item_id
				+ " / "
				+ inventory_group
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

		var item_type: String = str(
			data.get(
				"item_type",
				""
			)
		)

		if not VALID_ITEM_TYPES.has(
			item_type
		):
			push_error(
				"[ItemData] 잘못된 item_type: "
				+ item_id
				+ " / "
				+ item_type
			)

			all_valid = false
			continue

		# 원정에서 사용할 아이템만
		# expedition_storage와 bag_size가 필요하다.
		if is_expedition_item(item_id):
			if not data.has(
				"expedition_storage"
			):
				push_error(
					"[ItemData] 원정 아이템에 expedition_storage 없음: "
					+ item_id
				)

				all_valid = false
			else:
				var storage: String = (
					get_expedition_storage(
						item_id
					)
				)

				if (
					storage
					!= EXPEDITION_STORAGE_BAG
					and storage
					!= EXPEDITION_STORAGE_INVENTORY
				):
					push_error(
						"[ItemData] 잘못된 expedition_storage: "
						+ item_id
						+ " / "
						+ storage
					)

					all_valid = false

			if not data.has("bag_size"):
				push_error(
					"[ItemData] 원정 아이템에 bag_size 없음: "
					+ item_id
				)

				all_valid = false
			else:
				var bag_size = data.get(
					"bag_size"
				)

				if not bag_size is Vector2i:
					push_error(
						"[ItemData] bag_size가 Vector2i가 아님: "
						+ item_id
					)

					all_valid = false

				elif (
					bag_size.x <= 0
					or bag_size.y <= 0
				):
					push_error(
						"[ItemData] 잘못된 bag_size: "
						+ item_id
						+ " / "
						+ str(bag_size)
					)

					all_valid = false


	return all_valid

func get_items_by_inventory_group(
	inventory_group: String
) -> Array[String]:
	var result: Array[String] = []

	if not VALID_INVENTORY_GROUPS.has(
		inventory_group
	):
		return result

	for raw_item_id in items.keys():
		var item_id: String = str(
			raw_item_id
		)

		if (
			get_inventory_group(item_id)
			!= inventory_group
		):
			continue

		result.append(
			item_id
		)

	return result

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

func get_item_type(
	item_id: String
) -> String:
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return ""

	return str(
		data.get(
			"item_type",
			""
		)
	)


func is_store_product(
	item_id: String
) -> bool:
	return (
		get_item_type(item_id)
		== ITEM_TYPE_STORE_PRODUCT
	)

func is_expedition_item(
	item_id: String
) -> bool:
	var item_type: String = (
		get_item_type(item_id)
	)

	return (
		item_type == ITEM_TYPE_MATERIAL
		or item_type == ITEM_TYPE_EQUIPMENT
		or item_type == ITEM_TYPE_EXPEDITION_CONSUMABLE
		or item_type == ITEM_TYPE_SPECIAL
	)

func get_bag_size(
	item_id: String,
	rotated: bool = false
) -> Vector2i:
	if not is_expedition_item(item_id):
		return Vector2i.ZERO

	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return Vector2i.ZERO

	var bag_size: Vector2i = data.get(
		"bag_size",
		Vector2i.ZERO
	)

	if rotated:
		return Vector2i(
			bag_size.y,
			bag_size.x
		)

	return bag_size

func get_expedition_storage(item_id: String) -> String:
	var data: Dictionary = get_item(item_id)

	if data.is_empty():
		return ""

	return str(
		data.get(
			"expedition_storage",
			EXPEDITION_STORAGE_BAG
		)
	)


func can_store_in_expedition_bag(item_id: String) -> bool:
	if not is_expedition_item(item_id):
		return false

	var storage: String = get_expedition_storage(item_id)

	# 정산 후 보관 위치와 관계없이 원정 중에는 가방에 담는다.
	return (
		storage == EXPEDITION_STORAGE_BAG
		or storage == EXPEDITION_STORAGE_INVENTORY
	)

func should_deposit_after_expedition(item_id: String) -> bool:
	if not is_expedition_item(item_id):
		return false

	return (
		get_expedition_storage(item_id)
		== EXPEDITION_STORAGE_INVENTORY
	)
