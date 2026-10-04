class_name SeasonStyle
extends RefCounted
## 계절별 3D 마을 꾸밈 표(data/shop/catalogs/season_3d.csv): 땅 색, 잎 색, 낙엽수 맨가지, 지붕 눈, 풀 다발, 빛 색조.
## 값을 바꾸려면 코드가 아니라 이 CSV 를 고친다.

const CSV_PATH := "res://data/shop/catalogs/season_3d.csv"
const SEASONS: Array = ["spring", "summer", "autumn", "winter"]
const COLOR_KEYS: Array = ["grass_tint", "road_tint", "paving_tint", "leaf_tint", "pine_tint", "bush_tint", "tuft_tint", "sun_tint", "ambient_tint"]
const NUM_KEYS: Array = ["bare_trees", "roof_white", "tufts", "flower_rate", "tree_keep", "hide_shrubs", "snowman_rate", "bush_rate", "tuft_density", "tuft_height", "leaf_fall", "tree_rate", "litter_rate"]
# 낙엽수(겨울에 맨가지가 되고, 가을에는 단풍이 드는 나무)
const DECIDUOUS: Array = ["round", "birch", "big_oak", "autumn", "cherry", "willow", "poplar"]
# 가을 단풍 색 곱(나무마다 번호로 고른다): 주황 그대로 / 붉게 / 노랗게
const AUTUMN_LEAF_TINTS: Array = ["ffffff", "ff9a84", "ffe48a", "ffc070"]

static var _cache: Dictionary = {}


static func style(season_id: String) -> Dictionary:
	if _cache.is_empty():
		_load()

	return _cache.get(season_id, _cache.get("spring", {}))


static func season_of_day(total_day: int) -> String:
	return CalendarData.get_season_id(total_day)


static func _load() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)

	if file == null:
		push_warning("계절 표를 열 수 없습니다: " + CSV_PATH)
		_cache["spring"] = _fallback()
		return

	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() < header.size() or cells[0].strip_edges().is_empty():
			continue

		var row: Dictionary = {}

		for i in range(header.size()):
			var key: String = header[i].strip_edges()
			var value: String = cells[i].strip_edges()

			if key in COLOR_KEYS:
				row[key] = Color.html(value)
			elif key in NUM_KEYS:
				row[key] = float(value)
			else:
				row[key] = value

		_cache[str(row["season"])] = row


static func _fallback() -> Dictionary:
	return {"season": "spring", "grass_kind": "grass", "grass_tint": Color.WHITE, "road_tint": Color.WHITE, "paving_tint": Color.WHITE, "leaf_tint": Color.WHITE, "pine_tint": Color.WHITE, "bush_tint": Color.WHITE, "tuft_tint": Color.WHITE, "sun_tint": Color.WHITE, "ambient_tint": Color.WHITE, "bare_trees": 0.0, "roof_white": 0.0, "tufts": 1.0, "flower_rate": 1.0, "tree_keep": 1.0, "hide_shrubs": 0.0, "snowman_rate": 0.0, "bush_rate": 0.03, "tuft_density": 0.56, "tuft_height": 1.0, "leaf_fall": 0.0, "tree_rate": 0.01, "litter_rate": 0.0}


# 규칙(rule)을 계절에 맞게 고친다: 나무 종류(벚꽃은 봄에만, 겨울엔 낙엽수가 맨가지)와 지붕 눈.
static func adjust_rule(rule: Dictionary, season_id: String, seed_value: int) -> Dictionary:
	var st: Dictionary = style(season_id)
	var kind: String = str(rule.get("kind", ""))
	var r: Dictionary = rule.duplicate()

	if str(rule.get("style", "")) == "tree":
		var v: String = str(rule.get("variant", ""))

		if season_id != "spring" and v == "cherry":
			v = "round" if season_id == "summer" else "autumn"

		if season_id == "spring" or season_id == "summer":
			if v == "autumn":
				v = "round"
		elif season_id == "autumn" and DECIDUOUS.has(v) and v != "willow":
			v = "autumn"
			r["season_leaf"] = Color.html(AUTUMN_LEAF_TINTS[absi(seed_value) % AUTUMN_LEAF_TINTS.size()])
		elif season_id == "autumn" and v == "willow":
			r["season_leaf"] = Color.html("ffe8a0")

		if float(st.get("bare_trees", 0.0)) > 0.5 and DECIDUOUS.has(v):
			v = "dead"

		# 손으로 놓은 나무도 3D 에서는 그 자리에 고정하지 않는다(채집 자리 제외): 풀밭에 랜덤하게 자라는 나무(VillageMirror._sync_trees)가 대신한다.
		if not bool(rule.get("fixed_spot", false)) and not bool(rule.get("generated", false)):
			r["season_hide"] = true

		# 겨울 등 tree_keep < 1: 낙엽수 중 일부만 남기고(맨가지) 나머지는 안 보이게 한다. 소나무·고목은 그대로.
		if DECIDUOUS.has(str(rule.get("variant", ""))) or str(rule.get("variant", "")) == "":
			if float(st.get("tree_keep", 1.0)) < 1.0 and float(absi(seed_value * 31 + 7) % 100) >= float(st["tree_keep"]) * 100.0 and v != "pine":
				r["season_hide"] = true

		r["variant"] = v

	# 손으로 놓은 덤불(꽃 덤불·산딸기 덤불)은 3D 에서 그 자리에 고정하지 않는다: 안 보이게 하고, 풀밭에 계절·날짜에 따라 새로 자라는 덤불(VillageMirror._sync_bushes)이 대신한다.
	if str(rule.get("style", "")) == "flower_bush" and str(rule.get("variant", "")) != "hedge" and not bool(rule.get("fixed_spot", false)) and not bool(rule.get("generated", false)):
		r["season_hide"] = true

	# 덤불·꽃밭·산울타리는 겨울에 눈에 묻혀 안 보인다. 집 옆 덤불(extras)과 창 화분도 뺀다.
	if float(st.get("hide_shrubs", 0.0)) > 0.5:
		var sty: String = str(rule.get("style", ""))

		if sty == "flower_bush" or sty == "flowerbed":
			r["season_hide"] = true

		if rule.has("extras"):
			var keep: PackedStringArray = PackedStringArray()

			for tok in str(rule["extras"]).split(";", false):
				if not tok.begins_with("bush"):
					keep.append(tok)

			r["extras"] = ";".join(keep)

		r["planters"] = false

	var white: float = float(st.get("roof_white", 0.0))

	if white > 0.0 and kind == "gable" and r.has("roof_tint"):
		r["roof_tint"] = (r["roof_tint"] as Color).lerp(Color(0.96, 0.97, 1.0), white)

	return r


# 만들어진 면 사양(spec) 중 잎·덤불·꽃 면의 색 곱(tint)을 계절 색으로 바꾼다(원래 색은 건드리지 않게 복사본의 tint 에 곱한다).
static func tint_specs(specs: Array, rule: Dictionary, season_id: String) -> void:
	var st: Dictionary = style(season_id)

	for sp in specs:
		var d: Dictionary = sp
		var name: String = str(d.get("name", ""))
		var mul: Color = Color.WHITE

		if name.contains("pine"):
			mul = st["pine_tint"]
		elif name.contains("hedge") or name.contains("bush") or name.contains("berry") or name.contains("planter_flowers"):
			mul = st["bush_tint"]
		elif name.contains("foliage") or name.contains("bloom"):
			mul = st["leaf_tint"]

			if rule.has("season_leaf"):
				mul = mul * (rule["season_leaf"] as Color)
		else:
			continue

		d["tint"] = (d.get("tint", Color.WHITE) as Color) * mul
