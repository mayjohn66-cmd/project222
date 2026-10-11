class_name NatureStateArt
extends RefCounted
## 기존 나무/덤불의 상태 그림. 채집 진행이나 계절 해금은 바꾸지 않는다.
const DATA_PATH := "res://data/art/nature_state_assets.json"
static var _assets: Dictionary = {}
static var _loaded := false

static func assets() -> Dictionary:
	if not _loaded:
		_loaded = true
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if data is Dictionary: _assets = data
	return _assets

static func state_id(rule: Dictionary) -> String:
	if str(rule.get("style", "")) == "tree" and (str(rule.get("variant", "")) == "autumn" or rule.has("season_leaf")):
		var leaf: Color = rule.get("season_leaf", Color.WHITE)
		var base_variant := str(rule.get("nature_base_variant", "round"))
		if base_variant not in ["round", "birch", "big_oak", "cherry", "poplar", "willow"]:
			base_variant = "round"
		if base_variant == "willow" and leaf.is_equal_approx(Color.html("ffe8a0")):
			leaf = Color.html("ffc070")
		for id in assets():
			var row: Dictionary = assets()[id]
			if row.get("base_variant", "round") == base_variant and row.has("leaf_tint") and leaf.is_equal_approx(Color.html(str(row.leaf_tint))): return str(id)
		return "autumn_" + (base_variant + "_" if base_variant != "round" else "") + "orange"
	if str(rule.get("style", "")) == "flower_bush" and str(rule.get("variant", "")) == "berry":
		return "berry_empty" if str(rule.get("berry_state", "ready")) == "empty" else "berry_ready"
	return ""

static func render(view: StoreView3D, key: String, lo: Vector2, hi: Vector2,
		rule: Dictionary, signature: String, scale_factor: float) -> bool:
	var row: Dictionary = assets().get(state_id(rule), {})
	if row.is_empty(): return false
	var texture := ReceivedWorldArt.texture(str(row.path))
	if texture == null: return false
	var anchor := Vector2(float(row.anchor[0]), float(row.anchor[1]))
	ReceivedWorldArt.billboard(view, key, texture, anchor, lo, hi, (lo+hi)*0.5,
		signature, Color.WHITE, scale_factor, str(row.normal_source))
	view._items[key]["nature_state"] = state_id(rule)
	return true
