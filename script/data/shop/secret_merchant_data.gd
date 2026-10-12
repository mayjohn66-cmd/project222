class_name SecretMerchantData
extends RefCounted


# 심야 비밀 상인의 판매 목록을 CSV에서 읽고, 방문할 때마다 오늘의 진열을 정한다.
# 열: item_id, price, min_stock, max_stock, offer_chance(%), kind(item 또는 furniture, 비우면 item).
# kind가 furniture이면 item_id는 가구 ID이고 산 뒤 가구 인벤토리에 들어간다.
# item_id가 scroll_random이면 아직 배우지 않았고 갖고 있지 않은 레시피 두루마리 중 하나를 뽑고,
# 가격은 행의 가격 x (두루마리 희귀도 - 1)이다(희귀도 2 = 기준가, 3 = 2배).

const CSV_PATH: String = "res://data/shop/catalogs/economy/secret_merchant.csv"
const RANDOM_SCROLL_ID: String = "scroll_random"

static var entries: Array[Dictionary] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	entries.clear()

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error("[SecretMerchantData] 파일 열기 실패: " + CSV_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	for column in ["item_id", "price", "min_stock", "max_stock", "offer_chance"]:
		if not indexes.has(column):
			push_error("[SecretMerchantData] CSV 열 없음: " + column)
			return

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		var item_id: String = CsvReader.get_cell(row, indexes, "item_id")

		if item_id.is_empty():
			continue

		var kind: String = CsvReader.get_cell(row, indexes, "kind")

		if kind.is_empty():
			kind = "item"

		if kind != "item" and kind != "furniture":
			push_warning("[SecretMerchantData] 알 수 없는 종류: " + kind + " / " + item_id)
			continue

		if kind == "furniture":
			if FurnitureData.get_furniture(item_id).is_empty():
				push_warning("[SecretMerchantData] 없는 가구: " + item_id)
				continue
		elif item_id != RANDOM_SCROLL_ID and not ItemData.has_item(item_id):
			push_warning("[SecretMerchantData] 없는 아이템: " + item_id)
			continue

		var price: int = int(CsvReader.get_cell(row, indexes, "price"))
		var min_stock: int = maxi(int(CsvReader.get_cell(row, indexes, "min_stock")), 1)
		var max_stock: int = maxi(int(CsvReader.get_cell(row, indexes, "max_stock")), min_stock)
		var chance: float = clampf(
			float(CsvReader.get_cell(row, indexes, "offer_chance")),
			0.0,
			100.0
		)

		if price <= 0:
			push_warning("[SecretMerchantData] 잘못된 가격: " + item_id)
			continue

		entries.append({
			"item_id": item_id,
			"price": price,
			"min_stock": min_stock,
			"max_stock": max_stock,
			"offer_chance": chance,
			"kind": kind
		})


static func reload() -> void:
	_loaded = false
	ensure_loaded()


# 이번 방문의 진열을 정한다. 반환: [{item_id, price, stock}, ...]. 최소 1개는 나온다.
static func roll_offers() -> Array[Dictionary]:
	ensure_loaded()

	var offers: Array[Dictionary] = []

	for entry in entries:
		if randf() * 100.0 >= float(entry["offer_chance"]):
			continue

		var offer: Dictionary = _make_offer(entry)

		if not offer.is_empty():
			offers.append(offer)

	# 아무것도 안 나오면 서운하지 않게 하나는 반드시 진열한다.
	if offers.is_empty() and not entries.is_empty():
		var offer: Dictionary = _make_offer(entries.pick_random())

		if not offer.is_empty():
			offers.append(offer)

	return offers


static func _make_offer(
	entry: Dictionary
) -> Dictionary:
	var item_id: String = str(entry["item_id"])

	if item_id == RANDOM_SCROLL_ID:
		item_id = _pick_random_scroll()

		if item_id.is_empty():
			return {}

	# 두루마리는 희귀도에 비례해 비싸진다(희귀도 2 = 기준가, 3 = 2배).
	var price: int = int(entry["price"])

	if str(entry["item_id"]) == RANDOM_SCROLL_ID:
		price *= maxi(ItemData.get_rarity(item_id) - 1, 1)

	return {
		"item_id": item_id,
		"kind": str(entry.get("kind", "item")),
		"price": price,
		"stock": randi_range(
			int(entry["min_stock"]),
			int(entry["max_stock"])
		)
	}


static func _pick_random_scroll() -> String:
	var candidates: Array[String] = []

	for scroll_id in RecipeUnlockData.get_all_scroll_item_ids():
		if RecipeUnlockData.is_scroll_worth_dropping(scroll_id):
			candidates.append(scroll_id)

	if candidates.is_empty():
		return ""

	return candidates.pick_random()
